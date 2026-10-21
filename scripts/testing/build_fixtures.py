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
REVIEW_AT = 3  # risk_review_threshold: this many issue cases go to PATTERN_REVIEW (D-062)
ESC_SIZE = 41  # Insiders with no cases: FX-CLEAN, then one each for scenarios that issue or create Cases


def dump(org):
    p = subprocess.run(["sf", "apex", "run", "--file", os.path.join(REPO, "scripts/apex/dump-test-fixtures.apex"),
                        "-o", org, "--json"], capture_output=True, text=True, cwd=REPO)
    return json.loads(p.stdout[p.stdout.find("{"):])


def resolved(org):
    """Order ids that already have a CARES_Resolution__c: a second payout on them is refused (D-048)."""
    p = subprocess.run(["sf", "data", "query", "-q", "SELECT Order_Id__c FROM CARES_Resolution__c", "-o", org, "--json"],
                       capture_output=True, text=True, cwd=REPO)
    return {r["Order_Id__c"] for r in json.loads(p.stdout)["result"]["records"]}


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
                              "issues": int(f[7]) if len(f) > 7 else int(f[6])}
    return contacts, orders


def items(order):
    names = [n.strip() for n in order["items"].split(";") if n.strip()]
    names = [n.split(" ", 1)[1] if n[:1].isdigit() and n[1:3] == "x " else n for n in names]
    total = Decimal(order["tot"]).quantize(Decimal("0.01"))
    each = (total / len(names)).quantize(Decimal("0.01"), rounding=ROUND_DOWN)
    prices = [each] * len(names)
    prices[-1] = total - each * (len(names) - 1)
    return list(zip(names, prices)), total


def offer(tier, affected, total, clean=False):
    mx, cmx, bonus = POLICY[tier]
    refund = min(affected, Decimal(cmx if clean else mx), total).quantize(Decimal("0.01"))
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
          "latest": latest["id"], "latest_status": latest["st"], "order": dl["id"], "total": str(total),
          "item_count": len(it), "items_all": ", ".join(names[:-1]) + (" and " if len(names) > 1 else "") + names[-1]}
    for i, (n, p) in enumerate(it[:3], 1):
        fx[f"item{i}"], fx[f"price{i}"] = n, str(p)
    # Since G-084 was fixed the Risk Flow works, so a contact with no issue cases gets the clean-history cap
    clean = c["issues"] == 0
    fx["offer_one"], fx["credit_one"] = offer(c["tier"], it[0][1], total, clean)
    if len(it) > 1:
        fx["offer_two"], fx["credit_two"] = offer(c["tier"], it[0][1] + it[1][1], total, clean)
    fx["offer_all"], fx["credit_all"] = offer(c["tier"], total, total, clean)
    fx["offer_all_clean"], fx["credit_all_clean"] = offer(c["tier"], total, total, clean=True)
    fx["offer_all_std"], fx["credit_all_std"] = offer(c["tier"], total, total)
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

    for key, name in NAMED.items():
        add(key, name)
    for pool, names in POOLS.items():
        out["pools"][pool] = []
        for n in names:
            key = next((k for k, v in NAMED.items() if v == n), key_for("P", n))
            if key not in out["fixtures"]:
                add(key, n)
            out["pools"][pool].append(key)
    used = set(NAMED.values()) | {n for ns in POOLS.values() for n in ns}
    # FX-CLEAN and the ESC pool need no cases and no payout yet, so earlier live runs never leak into them
    paid = set() if args.from_log else resolved(args.org)
    esc = [n for n, (app, c) in sorted(by_name.items()) if c["tier"] == "Insider" and c["cases"] == 0
           and n not in used and app in orders and fixture(c, orders[app])["order"] not in paid][:ESC_SIZE]
    add("FX-CLEAN", esc[0])  # generic clean contact for scenarios that never issue or escalate
    # NOT_CLEAN but under the review threshold, with an order above the clean cap: shows the standard cap
    low = [n for n, (app, c) in sorted(by_name.items(), key=lambda kv: (kv[1][1]["issues"], kv[0]))
           if 0 < c["issues"] < REVIEW_AT and n not in used and app in orders
           and fixture(c, orders[app])["order"] not in paid
           and Decimal(fixture(c, orders[app])["total"]) > POLICY[c["tier"]][1]]
    add("FX-NOTCLEAN", low[0])
    esc = esc[1:]
    out["pools"]["ESC"] = []
    for n in esc:
        key = key_for("E", n)
        add(key, n)
        out["pools"]["ESC"].append(key)
    other = out["fixtures"]["FX-OTHER"]
    out["globals"] = {"other_order": other["latest"], "other_email": other["email"], "other_name": other["name"]}
    path = os.path.join(REPO, "scripts", "testing", "fixtures.json")
    json.dump(out, open(path, "w"), indent=1, ensure_ascii=False)
    print("wrote", path, len(out["fixtures"]), "fixtures")


if __name__ == "__main__":
    main()
