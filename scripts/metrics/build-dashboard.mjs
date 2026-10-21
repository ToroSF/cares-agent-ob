#!/usr/bin/env node
// Builds docs/metrics/index.html: one self-contained page with CARES metrics.
//
// Sources:
//   repo docs + CARES.agent        (working tree, or --docs-ref <git ref>)
//   the org, read only              (sf CLI; skipped with --offline, then the last snapshot is used)
//   Testing Center results          (docs/metrics/data/testing-center/*.json, normalized)
//
// Usage:
//   node scripts/metrics/build-dashboard.mjs [--target-org <alias>] [--offline]
//        [--docs-ref <ref>] [--compare-ref <ref>]
//
// The repo is public: only aggregated numbers are written. No record ids, names, emails or message text.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const OUT_DIR = join(ROOT, "docs/metrics");
const DATA_DIR = join(OUT_DIR, "data");
const TC_DIR = join(DATA_DIR, "testing-center");
const AGENT_PATH = "force-app/main/default/aiAuthoringBundles/CARES/CARES.agent";

const args = parseArgs(process.argv.slice(2));
const docsRef = args["docs-ref"] || "";
const compareRef = args["compare-ref"] || "";
const targetOrg = args["target-org"] || "team-pronto";

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      out[key] = next;
      i++;
    } else out[key] = true;
  }
  return out;
}

function git(...a) {
  return execFileSync("git", ["-C", ROOT, ...a], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
}

// Read a repo file from the working tree, or from a git ref when one is given
function readRepo(path, ref = docsRef) {
  try {
    if (ref) return git("show", `${ref}:${path}`);
    const p = join(ROOT, path);
    return existsSync(p) ? readFileSync(p, "utf8") : null;
  } catch {
    return null;
  }
}

function count(list, key) {
  const out = {};
  for (const item of list) {
    const k = typeof key === "function" ? key(item) : item[key];
    out[k] = (out[k] || 0) + 1;
  }
  return out;
}

function tableRows(md, idPattern) {
  if (!md) return [];
  return md
    .split("\n")
    .filter((l) => idPattern.test(l))
    .map((l) =>
      l
        .replace(/^\|/, "")
        .replace(/\|\s*$/, "")
        .split("|")
        .map((c) => c.trim())
    );
}

// ---------- repo: agent definition ----------

function parseAgent(src) {
  if (!src) return null;
  const lines = src.split("\n");
  const blocks = [];
  let cur = null;
  let section = "";
  let variables = 0;
  let inVariables = false;
  for (const line of lines) {
    const top = line.match(/^(start_agent|subagent)\s+(\w+):/);
    if (top) {
      cur = { name: top[2], label: top[2], start: top[1] === "start_agent", actions: [], tools: [], goesTo: new Set() };
      blocks.push(cur);
      section = "";
      inVariables = false;
      continue;
    }
    if (/^\S/.test(line)) {
      inVariables = /^variables:/.test(line);
      if (!/^(start_agent|subagent)/.test(line)) cur = null;
      continue;
    }
    if (inVariables && /^ {4}\w+: (mutable|linked) /.test(line)) variables++;
    if (!cur) continue;
    const label = line.match(/^ {4}label:\s*"(.*)"/);
    if (label) cur.label = label[1];
    const sec = line.match(/^ {4}(\w+):\s*$/);
    if (sec) section = sec[1];
    // Action definitions: "    actions:" > "        name:" > "            target: ..."
    if (section === "actions") {
      const def = line.match(/^ {8}(\w+):\s*$/);
      if (def) cur.actions.push({ name: def[1], type: "?" });
      const target = line.match(/^ {12}target:\s*"(\w+):\/\/([^"]+)"/);
      if (target && cur.actions.length) {
        const t = target[1];
        cur.actions[cur.actions.length - 1].type =
          t === "standardInvocableAction" ? "standard" : t === "apex" ? "apex" : t === "flow" ? "flow" : t;
      }
    }
    // Tools the model can call, under reasoning: "            name: @actions.x" or "@utils.transition"
    const tool = line.match(/^ {12}(\w+):\s*@(actions|utils)\.(\w+)/);
    if (tool) cur.tools.push({ name: tool[1], kind: tool[2] === "utils" ? tool[3] : "action" });
    for (const m of line.matchAll(/transition to @subagent\.(\w+)/g)) cur.goesTo.add(m[1]);
  }
  const subagents = blocks.map((b) => ({ ...b, goesTo: [...b.goesTo] }));
  const actions = subagents.flatMap((s) => s.actions);
  return {
    lines: lines.length,
    variables,
    subagents,
    actionCount: actions.length,
    actionsByType: count(actions, "type"),
    transitions: subagents.reduce((n, s) => n + s.goesTo.length, 0),
    hasKnowledge: /^knowledge:/m.test(src),
  };
}

// ---------- repo: docs ----------

const STATUS_EMOJI = ["✅", "🟡", "🔴", "⬜", "❓", "∅", "🚫"];
function policyStatus(cell) {
  for (const ch of [...cell]) if (STATUS_EMOJI.includes(ch)) return ch;
  return "?";
}

function parseDocs() {
  const decisions = tableRows(readRepo("docs/DECISIONS.md"), /^\| D-\d+/).map((c) => ({
    id: c[0],
    status: (c[2].match(/^[A-Z]+/) || ["OTHER"])[0],
  }));
  const gaps = tableRows(readRepo("docs/GAPS.md"), /^\| G-\d+/).map((c) => {
    const s = c[c.length - 1].toUpperCase();
    const status = s.startsWith("PARTLY") ? "PARTLY CLOSED" : /^(CLOSED|FIXED)/.test(s) ? "CLOSED" : /^(MITIGATED|DECIDED)/.test(s) ? "MITIGATED" : s.startsWith("OPEN") ? "OPEN" : "OTHER";
    return { id: c[0], status };
  });
  const risks = tableRows(readRepo("docs/RISKS.md"), /^\| R-\d+/).map((c) => ({
    id: c[0],
    status: (c[c.length - 1].match(/^[A-Z]+/) || ["OTHER"])[0],
  }));
  const policyRows = tableRows(readRepo("docs/POLICY_ALIGNMENT.md"), /^\| POL-/).map((c) => ({
    id: c[0],
    source: c[0].replace(/^POL-([A-Z]).*/, "$1"),
    v0: policyStatus(c[3] || ""),
    v1: policyStatus(c[5] || ""),
    critical: /critical/i.test(c[3] || ""),
  }));
  const personasMd = readRepo(".claude/skills/cares-testing/personas.md") || "";
  const scenarios = [];
  let persona = "";
  for (const line of personasMd.split("\n")) {
    const h = line.match(/^## (P\d+)\.\s*(.+)/);
    if (h) persona = `${h[1]} ${h[2].replace(/\(.*?\)/g, "").trim()}`;
    const s = line.match(/\*\*(B-[A-Z]+-\d+)\*\*\s*(?:_\(added[^)]*\)_\s*)?`(P\d)`/);
    if (s && persona) scenarios.push({ id: s[1], persona, priority: s[2] });
  }
  const golden = readRepo("docs/grounding/golden-set.md") || "";
  const goldenIds = golden.match(/^\| [QOA]-\d+/gm) || [];
  const goldenQuestions = goldenIds.length;
  const goldenByKind = count(goldenIds, (id) => ({ Q: "in the documents", O: "outside (must decline)", A: "adversarial" })[id[2]]);
  const runLog = tableRows(readRepo("docs/TEST_PLAN.md"), /^\| (\d{4}-\d\d-\d\d)? *\| [^-]/)
    .filter((c) => c.length >= 4 && c[0] !== "Date" && c[0] !== "Level")
    .map((c) => {
      const r = c[c.length - 1];
      return { result: /^pass/i.test(r) ? "Pass" : /^fail/i.test(r) ? "Fail" : /OPEN|BLOCKED/.test(r) ? "Open" : "Other" };
    });
  return {
    decisions: { total: decisions.length, byStatus: count(decisions, "status") },
    gaps: { total: gaps.length, byStatus: count(gaps, "status") },
    risks: { total: risks.length, byStatus: count(risks, "status") },
    policy: {
      rules: policyRows.length,
      v0: count(policyRows, "v0"),
      v1: count(policyRows, "v1"),
      bySource: count(policyRows, "source"),
      critical: policyRows.filter((r) => r.critical).map((r) => ({ id: r.id, v0: r.v0, v1: r.v1 })),
    },
    scenarios: {
      total: scenarios.length,
      p0: scenarios.filter((s) => s.priority === "P0").length,
      byPersona: count(scenarios, "persona"),
    },
    goldenQuestions,
    goldenByKind,
    runLog: { total: runLog.length, byResult: count(runLog, "result") },
  };
}

// ---------- org (read only) ----------

function sf(argv) {
  const raw = execFileSync("sf", [...argv, "--target-org", targetOrg, "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 64 * 1024 * 1024,
  });
  return JSON.parse(raw.slice(raw.indexOf("{")));
}
function soql(q) {
  const res = sf(["data", "query", "-q", q]);
  if (res.status !== 0) throw new Error(res.message);
  return res.result.records;
}
function tryQuery(q) {
  try {
    return soql(q);
  } catch (e) {
    console.warn(`  skipped: ${q.slice(0, 70)}… (${String(e.message).split("\n")[0]})`);
    return null;
  }
}

function collectOrg() {
  console.log(`Reading the org (${targetOrg}), read only…`);
  const day = (iso) => iso.slice(0, 10);
  const versions = tryQuery(
    "SELECT Id, VersionNumber, Status, LastModifiedDate FROM BotVersion WHERE BotDefinition.DeveloperName = 'CARES' ORDER BY VersionNumber"
  );
  const cases = tryQuery(
    "SELECT Type, Reason, Priority, Status, Origin, CreatedDate, Subject FROM Case WHERE Origin IN ('Agentforce','Chat') ORDER BY CreatedDate"
  );
  const sessions = tryQuery("SELECT Status, CreatedDate FROM MessagingSession ORDER BY CreatedDate");
  const csat = tryQuery("SELECT Score__c, CreatedDate FROM CSAT_Rating__c");
  const caseKind = (s = "") => (/escalat/i.test(s) ? "Escalation" : /refund|credit/i.test(s) ? "Refund" : "Other");
  return {
    readAt: new Date().toISOString(),
    versions: versions?.map((v) => ({ version: v.VersionNumber, status: v.Status, date: day(v.LastModifiedDate) })) ?? null,
    cases: cases && {
      total: cases.length,
      byDay: count(cases, (c) => day(c.CreatedDate)),
      byType: count(cases, (c) => c.Type || "(none)"),
      byReason: count(cases, (c) => c.Reason || "(none)"),
      byPriority: count(cases, (c) => c.Priority || "(none)"),
      byStatus: count(cases, (c) => c.Status || "(none)"),
      byOrigin: count(cases, (c) => c.Origin || "(none)"),
      byKind: count(cases, (c) => caseKind(c.Subject)),
    },
    sessions: sessions && { total: sessions.length, byDay: count(sessions, (s) => day(s.CreatedDate)), byStatus: count(sessions, "Status") },
    csat: csat && { total: csat.length, byScore: count(csat, (c) => String(c.Score__c ?? "(none)")) },
    conversations: versions?.length ? collectConversations(versions) : null,
  };
}

// Agent conversations from the platform's own session log (ConversationDefinitionSession + EventLog).
// Session tracing in Data Cloud would add per-turn subagent, action and latency; it is not on in the team org.
const MODE_LABEL = { Preview: "Builder preview", Normal: "Live chat (website)", null: "Other (tests, API)" };
function collectConversations(versions) {
  const ids = versions.map((v) => `'${v.Id}'`).join(",");
  const versionOf = Object.fromEntries(versions.map((v) => [v.Id, `v${v.VersionNumber}`]));
  const sessions = tryQuery(
    `SELECT Id, ConversationDefinitionId, SessionStartTime, SessionStatus, SessionEndType, SessionTransferResult, Mode, WasSessionEngaged FROM ConversationDefinitionSession WHERE ConversationDefinitionId IN (${ids})`
  );
  if (!sessions) return null;
  const events = tryQuery(`SELECT ParentId, LogType, EventTarget FROM ConversationDefinitionEventLog WHERE ConversationDefinitionId IN (${ids})`) || [];
  const transferDialog = new Set((tryQuery("SELECT Id FROM ConversationDefinitionDialog WHERE DeveloperName = 'Transfer_To_Agent'") || []).map((d) => d.Id));
  const turns = {};
  const escalated = new Set();
  for (const e of events) {
    if (e.LogType === "InputMessage") turns[e.ParentId] = (turns[e.ParentId] || 0) + 1;
    if (e.LogType === "StartDialog" && transferDialog.has(e.EventTarget)) escalated.add(e.ParentId);
  }
  const agg = (list) => {
    const t = list.map((s) => turns[s.Id] || 0).sort((a, b) => a - b);
    const esc = list.filter((s) => escalated.has(s.Id)).length;
    return {
      sessions: list.length,
      engaged: list.filter((s) => s.WasSessionEngaged).length,
      escalated: esc,
      transferred: list.filter((s) => s.SessionTransferResult === "TransferSuccessful").length,
      customerMessages: t.length ? { mean: +(t.reduce((a, b) => a + b, 0) / t.length).toFixed(2), median: t[Math.floor(t.length / 2)], max: t[t.length - 1] } : null,
    };
  };
  const group = (keyFn) => {
    const out = {};
    for (const s of sessions) (out[keyFn(s)] ??= []).push(s);
    return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, agg(v)]));
  };
  return {
    ...agg(sessions),
    byMode: group((s) => MODE_LABEL[s.Mode] || s.Mode),
    byVersion: group((s) => versionOf[s.ConversationDefinitionId]),
    byEnd: count(sessions, (s) => s.SessionEndType || "(still open)"),
    byDay: count(sessions, (s) => s.SessionStartTime.slice(0, 10)),
    turnsHistogram: count(sessions, (s) => Math.min(turns[s.Id] || 0, 5)),
  };
}

// ---------- Testing Center ----------

const PII = [/[\w.+-]+@[\w-]+\.[\w.]+/g, /\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\b(?=\W|$)/g];
function scrub(text = "") {
  return PII.reduce((t, re) => t.replace(re, "[hidden]"), String(text)).slice(0, 200);
}

function loadTestingCenter() {
  if (!existsSync(TC_DIR)) return [];
  return readdirSync(TC_DIR)
    .filter((f) => f.endsWith(".json") && !f.endsWith(".raw.json"))
    .map((f) => JSON.parse(readFileSync(join(TC_DIR, f), "utf8")))
    .map((run) => ({
      ...run,
      cases: (run.cases || []).map((c) => ({ ...c, utterance: scrub(c.utterance), responseExcerpt: scrub(c.responseExcerpt) })),
    }))
    .sort((a, b) => String(a.runAt).localeCompare(String(b.runAt)));
}

// ---------- live batch runs (scripts/testing/run_batch.py) ----------

// Counts only: outcomes per run and the latest outcome per scenario, from test-results.json
const OUTCOMES = ["PASS", "EXPECTED_FAIL", "FLAKY", "FAIL", "UNEXPECTED_PASS", "N/A"];
function loadBatch() {
  const results = JSON.parse(readRepo(".claude/skills/cares-testing/test-results.json") || '{"runs":[]}');
  const dir = ".claude/skills/cares-testing/scenarios";
  const files = (git("ls-tree", "--name-only", docsRef || "HEAD", `${dir}/`) || "").split("\n").filter((f) => f.endsWith(".json"));
  const checked = new Set(files.flatMap((f) => (JSON.parse(readRepo(f) || '{"scenarios":[]}').scenarios || []).map((s) => s.id.replace(/[a-z]$/, ""))));
  // Persona of each scenario, as written in personas.md (run labels are not personas)
  const personaOf = {};
  let persona = "";
  for (const line of (readRepo(".claude/skills/cares-testing/personas.md") || "").split("\n")) {
    const h = line.match(/^## (P\d+)\.\s*(.+)/);
    if (h) persona = `${h[1]} ${h[2].replace(/\(.*?\)/g, "").trim()}`;
    const m = line.match(/\*\*(B-[A-Z]+-\d+)\*\*/);
    if (m && persona) personaOf[m[1]] ??= persona;
  }
  const outcomeOf = (r) => r.result || ((u) => (u.length === 1 ? u[0] : "FLAKY"))([...new Set((r.outcomes || []).filter((o) => o !== "ERROR"))]);
  const latest = {};
  const runs = (results.runs || []).filter((run) => run.tier === "L").map((run) => {
    const rows = Object.values(run.personas || {}).flatMap((p) => p.results || []);
    for (const r of rows) latest[r.scenario] = { outcome: outcomeOf(r), persona: personaOf[r.scenario.replace(/[a-z]$/, "")] || "other" };
    return {
      at: run.timestamp,
      file: String(run.scenarioFile || "").replace(/^.*\//, "").replace(/ .*/, ""),
      agentVersion: run.agentVersion,
      scenarios: rows.length,
      sessions: run.summary?.runs ?? null,
      byOutcome: count(rows, outcomeOf),
    };
  });
  const latestRows = Object.values(latest);
  return {
    checkedScenarios: checked.size,
    runs,
    totalSessions: runs.reduce((a, r) => a + (r.sessions || 0), 0),
    latest: { total: latestRows.length, byOutcome: count(latestRows, "outcome") },
    byPersona: Object.fromEntries(Object.entries(latestRows.reduce((o, r) => ((o[r.persona] ??= []).push(r), o), {})).map(([k, v]) => [k, count(v, "outcome")])),
    outcomes: OUTCOMES,
  };
}

// ---------- build ----------

mkdirSync(TC_DIR, { recursive: true });
const orgSnapshot = join(DATA_DIR, "org.json");
let org;
if (args.offline) {
  org = existsSync(orgSnapshot) ? JSON.parse(readFileSync(orgSnapshot, "utf8")) : null;
  console.log(org ? `Offline: using the org snapshot from ${org.readAt}` : "Offline: no org snapshot yet");
} else {
  org = collectOrg();
  writeFileSync(orgSnapshot, JSON.stringify(org, null, 2) + "\n");
}
// Our reading of each suite run (written by hand, keyed by suite name)
const findingsPath = join(DATA_DIR, "findings.json");
const findings = existsSync(findingsPath) ? JSON.parse(readFileSync(findingsPath, "utf8")) : {};

const data = {
  generatedAt: new Date().toISOString(),
  commit: git("rev-parse", "--short", "HEAD"),
  branch: git("rev-parse", "--abbrev-ref", "HEAD"),
  docsRef: docsRef || "working tree",
  agent: parseAgent(readRepo(AGENT_PATH, "")),
  agentCompare: compareRef ? { ref: compareRef, ...parseAgent(readRepo(AGENT_PATH, compareRef)) } : null,
  docs: parseDocs(),
  org,
  testing: loadTestingCenter().map((run) => ({ ...run, findings: findings[run.suite] || [] })),
  batch: loadBatch(),
};

const template = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "dashboard.template.html"), "utf8");
const json = JSON.stringify(data).replace(/</g, "\\u003c");
writeFileSync(join(OUT_DIR, "index.html"), template.replace("/*__DATA__*/null", json));
writeFileSync(join(DATA_DIR, "metrics.json"), JSON.stringify(data, null, 2) + "\n");
console.log(`Wrote docs/metrics/index.html (${data.testing.length} Testing Center run(s), org: ${org ? "yes" : "no"})`);
