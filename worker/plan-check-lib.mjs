/**
 * Plan hard gates + attestation/lease/claim helpers (doc-33).
 * Runtime copy: worker/plan-check-lib.mjs (sync-autoscan).
 */

import { createHash } from "node:crypto";

export const ATTESTATION_SCHEMA = "plan-attestation/v1";
export const SOFT_THRESHOLD = 90;
export const DEFAULT_LEASE_SEC = 900;

const FUZZY_RE =
  /продумать|убедиться|при необходимости|и т\.?д\.?|\bTODO\b/i;
const TEST_CMD_RE =
  /pytest|npm test|cargo test|go test|scripts\/|make test|тесты не требуются\s*:/i;
const OOS_RE = /вне зоны|out of scope|не входит/i;
const RISK_RE = /риск|зависимост|deps|рисков нет/i;
const CIRCULAR_RE =
  /закрыть шаги плана|AC\s*=\s*Plan|Done\s*=\s*план/i;
const SKIP_LINE_RE = /^plan:skip:\s*(.+)$/im;
const INJECTION_RE =
  /ignore\s+(the\s+)?rubric|score\s+100|принять\s+план|auto-?accept|ignore previous/i;

/** Normalize Plan text for hashing (trim, LF). */
export function normalizePlan(text) {
  return String(text || "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

export function planHash(text) {
  const n = normalizePlan(text);
  const h = createHash("sha256").update(n, "utf8").digest("hex");
  return `sha256:${h}`;
}

export function countPlanSteps(plan) {
  const lines = normalizePlan(plan).split("\n");
  let n = 0;
  for (const line of lines) {
    const t = line.trim();
    if (/^\d+[\.\)]\s+\S/.test(t)) n += 1;
    else if (/^-\s+\[[ xX]?\]\s+\S/.test(t)) n += 1;
    else if (/^##\s+Шаги плана/i.test(t)) n += 0; // header only
  }
  // Also count bare "- step" under plan if numbered/checkbox missing but 3–7 bullets
  if (n === 0) {
    for (const line of lines) {
      const t = line.trim();
      if (/^[-*]\s+\S/.test(t) && !/^[-*]\s+\[/.test(t)) n += 1;
    }
  }
  return n;
}

export function parseSkipLine(plan) {
  const m = normalizePlan(plan).match(SKIP_LINE_RE);
  if (!m) return null;
  const reason = String(m[1] || "").trim();
  return { reason, ok: reason.length >= 15 };
}

export function extractDocRefs(refs = [], text = "") {
  const out = new Set();
  const blob = `${(refs || []).join("\n")}\n${text || ""}`;
  for (const m of blob.matchAll(/\bdoc-(\d+)\b/gi)) {
    out.add(`doc-${m[1]}`);
  }
  return [...out];
}

/**
 * Hard gates H1–H10. Returns { result, failed[], checks{}, plan_hash, mode }.
 */
export function runHardGates({
  plan = "",
  status = "To Do",
  labels = [],
  refs = [],
  description = "",
  notes = "",
  isEpic = false,
  hotfix = false,
  docSigned = null, // Map or object doc-N -> boolean; null = skip signed check detail
} = {}) {
  const failed = [];
  const checks = {};
  const text = normalizePlan(plan);
  const labs = (labels || []).map((x) => String(x).trim().toLowerCase());
  const hash = planHash(text);

  const skip = parseSkipLine(text);
  if (skip) {
    // S1–S3
    checks.S1 = skip.ok;
    if (!skip.ok) failed.push({ id: "S1", rec: "plan:skip: причина ≥15 символов" });

    const pathHits = (text.match(/\/[\w./-]+|\b[\w-]+\.(mjs|js|ts|py|md)\b/g) || [])
      .length;
    checks.S2 = !isEpic && pathHits <= 2;
    if (isEpic) failed.push({ id: "S2", rec: "skip не для epic" });
    else if (pathHits > 2) failed.push({ id: "S2", rec: "skip: ≤2 пути в Plan" });

    const docs = extractDocRefs(refs, `${description}\n${notes}\n${text}`);
    const hasDoc = docs.length > 0;
    const labelHotfix = labs.includes("hotfix") || hotfix;
    let s3 = true;
    if (hasDoc) {
      const allSigned =
        docSigned == null
          ? labelHotfix // without verify map, require hotfix label
          : docs.every((d) => docSigned[d] === true);
      s3 = allSigned && labelHotfix;
    }
    checks.S3 = s3;
    if (!s3) {
      failed.push({
        id: "S3",
        rec: "skip с doc-N только если signed + hotfix",
      });
    }

    const pass = failed.length === 0;
    return {
      result: pass ? "pass" : "fail",
      mode: "skip",
      failed,
      checks,
      plan_hash: hash,
      soft_required: true, // v0: soft always after hard-skip-pass
    };
  }

  // H1
  const lines = text ? text.split("\n").filter((l) => l.trim()) : [];
  checks.H1 = text.length >= 80 || lines.length >= 3;
  if (!checks.H1) failed.push({ id: "H1", rec: "Напиши Plan" });

  // H2
  const steps = countPlanSteps(text);
  checks.H2 = steps >= 3 && steps <= 7;
  if (!checks.H2) failed.push({ id: "H2", rec: "3–7 бинарных шагов" });

  // H3
  checks.H3 = !FUZZY_RE.test(text);
  if (!checks.H3) failed.push({ id: "H3", rec: "убрать размытые формулировки" });

  // H4
  checks.H4 = TEST_CMD_RE.test(text);
  if (checks.H4 && /тесты не требуются\s*:/i.test(text)) {
    const m = text.match(/тесты не требуются\s*:\s*(.+)/i);
    const reason = (m?.[1] || "").trim();
    if (reason.length < 10) {
      checks.H4 = false;
      failed.push({ id: "H4", rec: "тесты не требуются: причина ≥10" });
    }
  } else if (!checks.H4) {
    failed.push({ id: "H4", rec: "назвать проверку (тест-команда)" });
  }

  // H5
  const docsInRefs = extractDocRefs(refs, `${description}\n${notes}`);
  if (docsInRefs.length === 0) {
    checks.H5 = true;
  } else {
    checks.H5 = docsInRefs.every((d) => new RegExp(d, "i").test(text));
    if (!checks.H5) {
      failed.push({ id: "H5", rec: "привязать Plan к doc-N / пути" });
    }
  }

  // H6
  checks.H6 = OOS_RE.test(text);
  if (!checks.H6) failed.push({ id: "H6", rec: "дописать out-of-scope" });

  // H7
  checks.H7 = RISK_RE.test(text);
  if (!checks.H7) failed.push({ id: "H7", rec: "дописать риски/deps или «рисков нет»" });

  // H8 warn only
  checks.H8 = String(status || "").toLowerCase() === "to do";
  // no fail

  // H9 xor accepted/rework
  const hasAcc = labs.includes("plan:accepted");
  const hasRew = labs.includes("plan:rework");
  checks.H9 = !(hasAcc && hasRew);
  if (!checks.H9) failed.push({ id: "H9", rec: "снять оба labels accepted/rework" });

  // H10
  checks.H10 = !CIRCULAR_RE.test(text);
  if (!checks.H10) {
    failed.push({ id: "H10", rec: "критерии только в Notes/doc, не круговой Plan" });
  }

  const pass = failed.length === 0;
  return {
    result: pass ? "pass" : "fail",
    mode: "normal",
    failed,
    checks,
    plan_hash: hash,
    soft_required: true,
  };
}

export function buildAttestationStub({
  taskId,
  hard,
  soft = null,
  attempt = 1,
  author = "plan-hard",
  runId = null,
} = {}) {
  const at = new Date().toISOString();
  const rid = runId || `run_${Date.now()}`;
  return {
    schema: ATTESTATION_SCHEMA,
    task_id: taskId || "",
    plan_hash: hard?.plan_hash || "",
    hard: {
      result: hard?.result || "fail",
      failed: (hard?.failed || []).map((f) => f.id || f),
      at,
      run_id: rid,
      mode: hard?.mode || "normal",
    },
    soft: soft || null,
    attempt,
    author,
  };
}

export function parseAttestationJson(text) {
  const s = String(text || "");
  const fence = s.match(
    /```json\s*plan-attestation\s*\n([\s\S]*?)```/i
  );
  const raw = fence ? fence[1] : null;
  if (raw) {
    try {
      return JSON.parse(raw.trim());
    } catch {
      return null;
    }
  }
  // bare object with schema
  const bare = s.match(
    /\{[\s\S]*"schema"\s*:\s*"plan-attestation\/v1"[\s\S]*\}/
  );
  if (bare) {
    try {
      return JSON.parse(bare[0]);
    } catch {
      return null;
    }
  }
  return null;
}

/**
 * Outcome after plan-score finished (comments or assistant text).
 * Pure — autoscan applies labels / CEO / lease clear.
 */
export function resolvePlanScoreOutcome({
  attestation = null,
  attempt = 0,
  requireAuthor = "plan-score",
} = {}) {
  const att = attestation;
  if (!att || att.schema !== ATTESTATION_SCHEMA) {
    return {
      kind: "pending",
      accepted: false,
      label: null,
      attempt,
      needCeo: false,
      clearLease: false,
    };
  }
  if (requireAuthor && String(att.author || "") !== requireAuthor) {
    return {
      kind: "ignore-author",
      accepted: false,
      label: null,
      attempt,
      needCeo: false,
      clearLease: false,
      attestation: att,
    };
  }
  const soft = att.soft?.result;
  if (soft === "accepted") {
    return {
      kind: "accepted",
      accepted: true,
      label: "plan:accepted",
      attempt: 0,
      needCeo: false,
      clearLease: true,
      attestation: att,
    };
  }
  if (soft === "rework") {
    const next = (Number(attempt) || 0) + 1;
    return {
      kind: "rework",
      accepted: false,
      label: "plan:rework",
      attempt: next,
      needCeo: next >= 3,
      clearLease: true,
      attestation: att,
    };
  }
  return {
    kind: "pending",
    accepted: false,
    label: null,
    attempt,
    needCeo: false,
    clearLease: false,
    attestation: att,
  };
}

/** Dead plan-score session without usable soft → count as soft-fail. */
export function resolveMissingScoreOnDeadSession({ attempt = 0 } = {}) {
  const next = (Number(attempt) || 0) + 1;
  return {
    kind: "rework",
    accepted: false,
    label: "plan:rework",
    attempt: next,
    needCeo: next >= 3,
    clearLease: true,
    reason: "score-session-dead-no-attestation",
  };
}

export function detectInjection(plan) {
  return INJECTION_RE.test(normalizePlan(plan));
}

/**
 * Soft score from findings map { R1: 0|50|100, ... }. Weights doc-33 §11.
 */
export function computeSoftScore(findings = {}) {
  const weights = { R1: 25, R2: 25, R3: 20, R4: 15, R5: 15 };
  let sum = 0;
  let wsum = 0;
  for (const [k, w] of Object.entries(weights)) {
    const v = Number(findings[k]);
    if (!Number.isFinite(v)) continue;
    sum += (v / 100) * w;
    wsum += w;
  }
  if (wsum === 0) return 0;
  return Math.round(sum);
}

export function applySoftResult({
  findings,
  hard,
  plan,
  attempt = 1,
  model = "test/model",
  session = "ses_test",
  author = "plan-score",
  taskId = "",
  runId = null,
} = {}) {
  if (detectInjection(plan)) {
    const att = buildAttestationStub({
      taskId,
      hard,
      attempt: attempt + 1,
      author,
      runId,
      soft: {
        result: "rework",
        score: 0,
        threshold: SOFT_THRESHOLD,
        rubric_semver: "1.0",
        model,
        session,
        at: new Date().toISOString(),
        run_id: runId || `run_${Date.now()}`,
        findings: { ...(findings || {}), "R-inj": 0 },
      },
    });
    return {
      accepted: false,
      injection: true,
      label: "plan:rework",
      attempt: attempt + 1,
      needCeo: attempt + 1 >= 3,
      attestation: att,
    };
  }

  if (!hard || hard.result !== "pass") {
    return {
      accepted: false,
      injection: false,
      label: "plan:rework",
      attempt,
      needCeo: false,
      reason: "hard:fail",
      attestation: buildAttestationStub({
        taskId,
        hard,
        attempt,
        author: "plan-hard",
      }),
    };
  }

  const score = computeSoftScore(findings);
  const pass = score >= SOFT_THRESHOLD;
  const nextAttempt = pass ? attempt : attempt + 1;
  const soft = {
    result: pass ? "accepted" : "rework",
    score,
    threshold: SOFT_THRESHOLD,
    rubric_semver: "1.0",
    model,
    session,
    at: new Date().toISOString(),
    run_id: runId || `run_${Date.now()}`,
    findings: findings || {},
  };
  return {
    accepted: pass,
    injection: false,
    label: pass ? "plan:accepted" : "plan:rework",
    attempt: nextAttempt,
    needCeo: !pass && nextAttempt >= 3,
    attestation: buildAttestationStub({
      taskId,
      hard,
      soft,
      attempt: nextAttempt,
      author,
      runId,
    }),
  };
}

/** Lease single-flight helpers */
export function leaseTtlSec(env = process.env) {
  const n = Number(env.AUTOSCAN_PLAN_LEASE_SEC || DEFAULT_LEASE_SEC);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_LEASE_SEC;
}

export function getPlanLease(state, taskId) {
  return state?.planLease?.[taskId] || null;
}

export function isLeaseActive(lease, now = Date.now()) {
  if (!lease?.until) return false;
  const until = Date.parse(lease.until);
  return Number.isFinite(until) && until > now;
}

export function acquirePlanLease(state, taskId, kind, { session = null, now = Date.now(), ttlSec = null } = {}) {
  const cur = getPlanLease(state, taskId);
  if (isLeaseActive(cur, now) && cur.kind === kind) {
    return { ok: false, reason: "lease-held", lease: cur };
  }
  if (isLeaseActive(cur, now) && cur.kind !== kind) {
    return { ok: false, reason: "other-kind-lease", lease: cur };
  }
  const sec = ttlSec ?? DEFAULT_LEASE_SEC;
  const lease = {
    kind,
    session,
    until: new Date(now + sec * 1000).toISOString(),
  };
  if (!state.planLease) state.planLease = {};
  state.planLease[taskId] = lease;
  return { ok: true, lease };
}

export function clearPlanLease(state, taskId) {
  if (state?.planLease?.[taskId]) delete state.planLease[taskId];
}

export function shouldRescoreNoop(attestation, planText) {
  if (!attestation?.plan_hash) return false;
  if (attestation.soft?.result !== "accepted" && attestation.soft?.result !== "rework") {
    return false;
  }
  return attestation.plan_hash === planHash(planText);
}

/**
 * Claim gate (wave E). Returns { ok, reason }.
 */
export function canClaimWithPlan({
  status = "To Do",
  plan = "",
  labels = [],
  attestation = null,
  solePrimary = true,
  blockingCo = false,
  leaseActive = false,
  planGateEnabled = true,
} = {}) {
  if (!planGateEnabled) return { ok: true, reason: "gate-off" };
  if (String(status).toLowerCase() !== "to do") {
    return { ok: false, reason: "not-todo" };
  }
  if (!solePrimary) return { ok: false, reason: "not-sole-primary" };
  if (blockingCo) return { ok: false, reason: "blocking-co" };
  if (leaseActive) return { ok: false, reason: "lease-active" };

  const labs = (labels || []).map((x) => String(x).trim().toLowerCase());
  if (labs.includes("plan:rework")) return { ok: false, reason: "plan:rework" };

  if (!attestation || attestation.schema !== ATTESTATION_SCHEMA) {
    return { ok: false, reason: "no-attestation" };
  }
  if (attestation.hard?.result !== "pass") {
    return { ok: false, reason: "hard-fail" };
  }
  if (attestation.soft?.result !== "accepted") {
    return { ok: false, reason: "soft-not-accepted" };
  }
  if (String(attestation.author || "") !== "plan-score") {
    return { ok: false, reason: "wrong-author" };
  }
  const live = planHash(plan);
  if (live !== attestation.plan_hash) {
    return { ok: false, reason: "hash-mismatch" };
  }
  // bare label from build is ignored — attestation author is SoT
  return { ok: true, reason: "ok" };
}

export function humanHardComment(hard) {
  if (!hard) return "plan-hard: no result";
  if (hard.result === "pass") {
    return `plan-hard: pass (${hard.mode || "normal"}) hash=${hard.plan_hash}`;
  }
  const bits = (hard.failed || [])
    .map((f) => `${f.id}: ${f.rec || ""}`)
    .join("; ");
  return `plan-hard: fail — ${bits}`;
}
