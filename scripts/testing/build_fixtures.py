#!/usr/bin/env python3
"""Build scripts/testing/fixtures.json from the demo data in the team org.

  python3 scripts/testing/build_fixtures.py [--org team-pronto] [--from-log saved-apex-output.json]

Runs scripts/apex/dump-test-fixtures.apex (read-only), then computes for each named fixture its
latest order, latest delivered order, the item values (total / items, D-072), the risk the Risk Flow
will return and the expected offers from the policy rows below. If the policy rows change in the org,
change POLICY here.
"""
import argparse
import html
import json
import os
import re
import subprocess
from decimal import Decimal, ROUND_DOWN, ROUND_HALF_EVEN

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Tier: (Max_Refund__c, Clean_History_Max_Refund__c, Store_Credit_Bonus_Pct__c), same for all outcomes
POLICY = {"Explorer": (25, 35, 10), "Insider": (40, 55, 15), "Pronto Plus": (60, 80, 20)}
OTHER = "Garrik Forman"  # owns the "another customer's order"

NAMED = {
    "FX-EXP": "Geoff Wyllt", "FX-EXP-2": "Giacopo Maryet", "FX-INS": "Calley MacIntyre",
    "FX-INS-2": "Ring Velden", "FX-PP": "Gage Balwin", "FX-PP-2": "Jess Gadault", "FX-ONE": "Duky Atkyns",
    "FX-BIG": "Nert Tungay", "FX-OFD": "Devin De Mattia", "FX-PREP": "Delmore Decroix",
    "FX-CANC": "Rubia A'Barrow", "FX-OTHER": OTHER, "FX-DIRTY": "Alex Morgan", "FX-CLEAN-BIG": "Boyce Antrag",
}
POOLS = {
    "R-EXP": ["Geoff Wyllt", "Giacopo Maryet", "Petronille Lyste", "Jeffrey Valentine"],
    "R-INS": ["Calley MacIntyre", "Ring Velden", "Humfrid Jendrusch", "Beatrix Shooter", "Diane-marie Pantry"],
    "R-PP": ["Jess Gadault", "Gage Balwin", "Marta Bassindale", "Rozanne Devereux", "Peyton Batrick"],
    "R-ONE": ["Duky Atkyns", "Dore Briant", "Bruce Clemendot", "Penny Danforth"],
    "R-OFD": ["Devin De Mattia", "Angele Evins"],
    "R-PREP": ["Delmore Decroix", "Ellery Collopy", "Corie Fairleigh"],
    "R-CANC": ["Rubia A'Barrow", "Karena Cowburn", "Evanne Fosberry", "Candace Pigford"],
}
# Pool each named fixture comes from, to swap it when its order is already paid (G-108)
NAMED_POOL = {"FX-EXP": "R-EXP", "FX-EXP-2": "R-EXP", "FX-INS": "R-INS", "FX-INS-2": "R-INS", "FX-PP": "R-PP",
              "FX-PP-2": "R-PP", "FX-ONE": "R-ONE", "FX-OFD": "R-OFD", "FX-PREP": "R-PREP", "FX-CANC": "R-CANC"}
# Named fixtures that only need a tier: with no unpaid spare in their pool, any clean contact of that tier will do
TIER_ONLY = {"FX-EXP", "FX-EXP-2", "FX-INS", "FX-INS-2", "FX-PP", "FX-PP-2"}
REVIEW_AT = 3  # risk_review_threshold: this many issue cases go to PATTERN_REVIEW (D-062)
RETENTION_BONUS_PCT = 5  # Retention_Bonus_Pct__c seeded by seed-refund-tiers.apex (D-083, mock data, [$])
# Mock sentiment context (D-083): contact name => Has_Open_Context__c is true. These are the two
# contacts scripts/apex/seed-customer-context.apex seeds. Risk status still decides eligibility:
# a PATTERN_REVIEW contact here (Alex Morgan) never reaches the context read at all.
CONTEXT_CONTACTS = {"Boyce Antrag", "Alex Morgan", "Barclay Scarsbrooke"}
ESC_SIZE = 41  # contacts with no cases: FX-CLEAN (an Insider), then one each for scenarios that issue or create Cases
ESC_LOW_SIZE = 8  # contacts Stolen & Delayed does not trust, for the "never arrived" scenarios that escalate
# Stolen & Delayed trusts a customer only with this many non-canceled orders and a claim rate at most this
# (High_Trust_Min_Orders__c and High_Trust_Max_Claim_Rate__c on CARES_Stolen_Delayed_Policy.Default, D-090).
# Anyone else gets MANUAL_REVIEW. Tier does not count
HIGH_TRUST_MIN_ORDERS = 5
HIGH_TRUST_MAX_CLAIM_RATE = Decimal("0.05")
# The Stolen & Delayed demo orders (mock telemetry, D-096; timing demo clock, D-100) live in this seed. Their
# customers are reserved for the demo: a test that pays or escalates on them spends the demo order (G-108)
DEMO_SEED = os.path.join(REPO, "scripts", "apex", "seed-delivery-telemetry.apex")
# Delivery timing (D-100): the customer who owns each order, found by the order id. Delivered in 43 and 58 min
# (promise 40: minor and severe delay), delivered on time, and a demo order still within its time (demo clock,
# 20 min). The not-late-yet path offers no money and logs nothing, so it does not spend the demo order
TIMING = {"FX-LATE-MINOR": "PR-240831-SO0F85U", "FX-LATE-SEVERE": "PR-240819-E6PVNNW",
          "FX-ONTIME": "PR-240817-Q4ZTFF0", "FX-NOTLATE": "PR-240614-8T45OO8"}
# Minor_Delay_Pct__c and Severe_Delay_Pct__c on CARES_Stolen_Delayed_Policy.Default: the delay value is the order total
# times this, and Refund caps it with the tier's Delayed row (D-100)
DELAY_PCT = {"FX-LATE-MINOR": 15, "FX-LATE-SEVERE": 50}


def demo_orders():
    code = "\n".join(l.split("//", 1)[0] for l in open(DEMO_SEED).read().splitlines())
    return set(re.findall(r"'(PR-\d{6}-[A-Z0-9]+)'", code))


def dump(org):
    p = subprocess.run(["sf", "apex", "run", "--file", os.path.join(REPO, "scripts/apex/dump-test-fixtures.apex"),
                        "-o", org, "--json"], capture_output=True, text=True, cwd=REPO)
    return json.loads(p.stdout[p.stdout.find("{"):])


def resolved(org):
    """Order ids that already have a CARES_Resolution__c: a second payout on them is refused (D-048).
    Also the resolutions per contact, which Stolen & Delayed counts as claims (D-090)."""
    p = subprocess.run(["sf", "data", "query", "-q", "SELECT Order_Id__c, Contact__c FROM CARES_Resolution__c",
                        "-o", org, "--json"], capture_output=True, text=True, cwd=REPO)
    rows = json.loads(p.stdout)["result"]["records"]
    claims = {}
    for r in rows:
        claims[r["Contact__c"]] = claims.get(r["Contact__c"], 0) + 1
    return {r["Order_Id__c"] for r in rows}, claims


def load(path):
    text = open(path).read()
    return json.loads(text[text.find("{"):])


def parse(raw):
    logs = raw["result"]["logs"]
    contacts, orders = {}, {}
    for line in logs.splitlines():
        if "|DEBUG|" not in line:
            continue
        msg = html.unescape(line.split("|DEBUG|", 1)[1])
        f = msg.split("|")
        if f[0] == "FXO" and len(f) >= 7:
            orders.setdefault(f[1], []).append({"id": f[2], "st": f[3], "cr": f[4], "tot": f[5], "items": f[6]})
        elif f[0] == "FXC" and len(f) >= 7:
            contacts[f[5]] = {"cid": f[1], "name": f[2], "email": f[3], "tier": f[4], "cases": int(f[6]),
                              "issues": int(f[7]) if len(f) > 7 else int(f[6]),
                              "open_ctx": f[8] == "1" if len(f) > 8 else None}
    return contacts, orders


def items(order):
    names = [n.strip() for n in order["items"].split(";") if n.strip()]
    names = [n.split(" ", 1)[1] if n[:1].isdigit() and n[1:3] == "x " else n for n in names]
    total = Decimal(order["tot"]).quantize(Decimal("0.01"))
    each = (total / len(names)).quantize(Decimal("0.01"), rounding=ROUND_DOWN)
    prices = [each] * len(names)
    prices[-1] = total - each * (len(names) - 1)
    return list(zip(names, prices)), total


def offer(tier, affected, total, clean=False, retention_eligible=False):
    mx, cmx, bonus = POLICY[tier]
    refund = min(affected, Decimal(cmx if clean else mx), total).quantize(Decimal("0.01"))
    # Retention bonus (D-083, mock data): a modest extra on the already-capped standard refund,
    # applied only when Risk Detection signals genuine recent frustration for a customer not
    # already NOT_CLEAN by pattern. Mirrors CARES_Refund_CalculateOffer.cls exactly.
    if retention_eligible:
        refund = (refund * (1 + Decimal(RETENTION_BONUS_PCT) / 100)).quantize(Decimal("0.01"))
    credit = (refund * (1 + Decimal(bonus) / 100)).quantize(Decimal("0.01"), rounding=ROUND_HALF_EVEN)
    return str(refund), str(credit)


def risk(issues):
    return "CLEAN" if issues == 0 else "NOT_CLEAN" if issues < REVIEW_AT else "PATTERN_REVIEW"


def key_for(prefix, name):
    return prefix + "-" + "".join(ch for ch in name.upper().replace(" ", "-") if ch.isalnum() or ch == "-")


def fixture(c, orders):
    os_ = sorted(orders, key=lambda o: o["cr"], reverse=True)
    latest = os_[0]
    dl = next(o for o in os_ if o["st"] == "Delivered")
    it, total = items(dl)
    names = [n for n, _ in it]
    fx = {"cid": c["cid"], "name": c["name"], "email": c["email"], "tier": c["tier"], "cases": c["cases"],
          "issues": c["issues"], "risk": risk(c["issues"]),
          "latest": latest["id"], "latest_status": latest["st"],
          "latest_total": str(Decimal(latest["tot"]).quantize(Decimal("0.01"))), "order": dl["id"], "total": str(total),
          "orders_ok": sum(1 for o in orders if o["st"] != "Canceled"),
          "item_count": len(it), "items_all": ", ".join(names[:-1]) + (" and " if len(names) > 1 else "") + names[-1]}
    for i, (n, p) in enumerate(it[:3], 1):
        fx[f"item{i}"], fx[f"price{i}"] = n, str(p)
    # Since G-084 was fixed the Risk Flow works, so a contact with no issue cases gets the clean-history cap
    clean = c["issues"] == 0
    # Retention bonus (D-083): only when the contact has a seeded context row AND is not NOT_CLEAN
    # by pattern - "pay to keep a customer, not to have one". Mirrors Risk Detection's gate exactly.
    # The real open context row when the dump has it: the agent writes one on every saved rating
    fx["has_context"] = c["open_ctx"] if c.get("open_ctx") is not None else c["name"] in CONTEXT_CONTACTS
    retention_eligible = fx["has_context"] and fx["risk"] != "NOT_CLEAN" and fx["risk"] != "PATTERN_REVIEW"
    fx["retention_eligible"] = retention_eligible
    fx["offer_one"], fx["credit_one"] = offer(c["tier"], it[0][1], total, clean, retention_eligible)
    if len(it) > 1:
        fx["offer_two"], fx["credit_two"] = offer(c["tier"], it[0][1] + it[1][1], total, clean, retention_eligible)
    fx["offer_all"], fx["credit_all"] = offer(c["tier"], total, total, clean, retention_eligible)
    fx["offer_all_clean"], fx["credit_all_clean"] = offer(c["tier"], total, total, clean=True, retention_eligible=retention_eligible)
    fx["offer_all_std"], fx["credit_all_std"] = offer(c["tier"], total, total, retention_eligible=retention_eligible)
    return fx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--org", default="team-pronto")
    ap.add_argument("--from-log")
    args = ap.parse_args()
    raw = load(args.from_log) if args.from_log else dump(args.org)
    contacts, orders = parse(raw)
    by_name = {c["name"]: (app, c) for app, c in contacts.items()}
    out = {"fixtures": {}, "pools": {}, "globals": {}}

    def add(key, name):
        app, c = by_name[name]
        out["fixtures"][key] = fixture(c, orders[app])

    paid, claims = (set(), {}) if args.from_log else resolved(args.org)
    demo = demo_orders()
    reserved = {n for n, (app, c) in by_name.items() if any(o["id"] in demo for o in orders.get(app, []))}
    # The timing fixtures' owners stay out of every pool too: a payout on their order would turn the timing
    # check into DUPLICATE_CLAIM
    timing_owners = {c["name"] for app, c in contacts.items() if any(o["id"] in TIMING.values() for o in orders.get(app, []))}
    reserved |= timing_owners
    pooled = {n for ns in POOLS.values() for n in ns}
    # G-108: a named fixture whose latest delivered order was already paid gets "already has a refund";
    # swap it for a clean contact of the same pool whose order is still unpaid
    named = dict(NAMED)
    for key, pool in NAMED_POOL.items():
        app, c = by_name[named[key]]
        if fixture(c, orders[app])["order"] not in paid:
            continue
        spare = [n for n in POOLS[pool] if n not in named.values() and n not in reserved and n in by_name and by_name[n][0] in orders
                 and c["tier"] == by_name[n][1]["tier"] and by_name[n][1]["issues"] == 0
                 and not by_name[n][1].get("open_ctx")
                 and fixture(by_name[n][1], orders[by_name[n][0]])["order"] not in paid]
        if not spare and key in TIER_ONLY:
            spare = [n for n, (a2, c2) in sorted(by_name.items()) if n not in named.values() and n not in pooled
                     and n not in reserved and a2 in orders and c2["tier"] == c["tier"] and c2["cases"] == 0
                     and not c2.get("open_ctx") and fixture(c2, orders[a2])["order"] not in paid
                     and fixture(c2, orders[a2])["latest_status"] == "Delivered"
                     and fixture(c2, orders[a2])["item_count"] >= 2]
        if spare:
            print(f"{key}: {named[key]}'s order is paid, using {spare[0]}")
            named[key] = spare[0]
        else:
            print(f"WARNING: {key}: {named[key]}'s order is paid and {pool} has no unpaid spare")
    for key, name in named.items():
        add(key, name)
    for pool, names in POOLS.items():
        out["pools"][pool] = []
        for n in names:
            if n in reserved and n not in named.values():
                continue
            key = next((k for k, v in named.items() if v == n), key_for("P", n))
            if key not in out["fixtures"]:
                add(key, n)
            out["pools"][pool].append(key)
    used = set(named.values()) | pooled
    # FX-CLEAN and the ESC pool need no cases and no payout yet, so earlier live runs never leak into them
    def low_trust(app, c):
        ok = fixture(c, orders[app])["orders_ok"]
        return ok < HIGH_TRUST_MIN_ORDERS or Decimal(claims.get(c["cid"], 0)) / ok > HIGH_TRUST_MAX_CLAIM_RATE

    fresh = [(n, app, c) for n, (app, c) in sorted(by_name.items()) if c["cases"] == 0 and n not in used
             and n not in reserved
             and app in orders and fixture(c, orders[app])["order"] not in paid]
    # ESC: trusted contacts, so a "never arrived" claim is not sent to a person for lack of trust. Any tier:
    # the offers are computed per tier. FX-CLEAN stays an Insider
    trusted = [n for n, app, c in fresh if not low_trust(app, c)]
    # FX-CLEAN shows the clean cap with no retention bonus, so prefer a contact with no open context
    clean = next((n for n in trusted if by_name[n][1]["tier"] == "Insider" and not by_name[n][1].get("open_ctx")),
                 next(n for n in trusted if by_name[n][1]["tier"] == "Insider"))
    esc = [clean] + [n for n in trusted if n != clean][:ESC_SIZE - 1]
    # ESC-LOW: any tier, but Stolen & Delayed does not trust them (too few orders or too many claims),
    # so a "never arrived" claim always goes to a person. The pools never share a contact
    esc_low = [n for n, app, c in fresh if low_trust(app, c)][:ESC_LOW_SIZE]
    add("FX-CLEAN", esc[0])  # generic clean contact for scenarios that never issue or escalate
    # NOT_CLEAN but under the review threshold, with an order above the clean cap: shows the standard cap
    low = [n for n, (app, c) in sorted(by_name.items(), key=lambda kv: (kv[1][1]["issues"], kv[0]))
           if 0 < c["issues"] < REVIEW_AT and n not in used and app in orders
           and fixture(c, orders[app])["order"] not in paid
           and Decimal(fixture(c, orders[app])["total"]) > POLICY[c["tier"]][1]]
    if low:
        add("FX-NOTCLEAN", low[0])
    else:  # Risk Flow v3 skips CARES's own escalation Cases (D-082), so the org may have no 1-2 issue contact
        print("WARNING: no FX-NOTCLEAN contact (1-2 issue Cases); its scenarios will have no fixture")
    esc = esc[1:]
    for pool, names in (("ESC", esc), ("ESC-LOW", esc_low)):
        out["pools"][pool] = []
        for n in names:
            add(key_for("E", n), n)
            out["pools"][pool].append(key_for("E", n))
    for key, oid in TIMING.items():
        app = next((app for app, os_ in orders.items() if any(o["id"] == oid for o in os_)), None)
        if app not in contacts:
            print(f"WARNING: {key}: no contact owns {oid}; its scenarios will have no fixture")
            continue
        out["fixtures"][key] = fixture(contacts[app], orders[app])
        o = next(o for o in orders[app] if o["id"] == oid)
        fx, claim_total = out["fixtures"][key], Decimal(o["tot"]).quantize(Decimal("0.01"))
        fx.update({"claim_order": oid, "claim_status": o["st"], "claim_total": str(claim_total)})
        if key in DELAY_PCT:
            value = (claim_total * DELAY_PCT[key] / 100).quantize(Decimal("0.01"))
            fx["delay_value"] = str(value)
            fx["delay_offer"], fx["delay_credit"] = offer(fx["tier"], value, claim_total, fx["issues"] == 0,
                                                          fx["retention_eligible"])
    other = out["fixtures"]["FX-OTHER"]
    out["globals"] = {"other_order": other["latest"], "other_email": other["email"], "other_name": other["name"]}
    path = os.path.join(REPO, "scripts", "testing", "fixtures.json")
    json.dump(out, open(path, "w"), indent=1, ensure_ascii=False)
    print("wrote", path, len(out["fixtures"]), "fixtures;", len(reserved), "customers reserved (demo and timing):",
          ", ".join(sorted(reserved)))


if __name__ == "__main__":
    main()
