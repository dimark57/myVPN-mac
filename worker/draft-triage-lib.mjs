/**
 * Draft triage (doc-32 waves A+B+C) — pure helpers for autoscan.
 * Runtime copy: worker/draft-triage-lib.mjs (sync-autoscan).
 * Promote is never an outcome. Client questions only after keep|need_info.
 * Complete ticket: drop now; absorb when surviving Done; keep when house task Done.
 */

export const TRIAGE_OUTCOMES = Object.freeze([
  "keep",
  "absorb",
  "drop",
  "reroute",
  "escalate",
  "need_info",
]);

export const UUID_RE =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

const CLASSIFIER = "Классификатор";
const CEO = "Регистратор CEO";
const CLIENT = "Регистратор Client";

export function parseSourceTodoId({
  frontmatter = "",
  description = "",
  references = [],
} = {}) {
  const fm = String(frontmatter || "");
  const mFm = fm.match(/^source_todo_id:\s*['"]?([0-9a-f-]{36})/im);
  if (mFm) return mFm[1].toLowerCase();
  for (const raw of references || []) {
    const s = String(raw || "").trim();
    const named = s.match(
      /(?:source_todo_id|mythings|myThings)\s*[:/]\s*([0-9a-f-]{36})/i
    );
    if (named) return named[1].toLowerCase();
    const only = s.match(new RegExp(`^${UUID_RE.source}$`, "i"));
    if (only) return only[0].toLowerCase();
  }
  const mDesc = String(description || "").match(
    /source_todo_id\s*[:/]\s*['"]?([0-9a-f-]{36})/i
  );
  return mDesc ? mDesc[1].toLowerCase() : null;
}

export function extractCoversId(text) {
  const m = String(text || "").match(
    /закрывает\s+([A-Z]{2,10}-\d+(?:\.\d+)*)/i
  );
  return m ? m[1].toUpperCase() : null;
}

export function extractRepoHint(text) {
  const m = String(text || "").match(/\brepo:\s*['"]?([a-z0-9_-]+)/i);
  return m ? m[1].toLowerCase() : null;
}

export function normalizeTitle(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

export function looksLikeSecret(text) {
  const s = String(text || "");
  if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(s)) return true;
  if (/\b(sk-|ghp_|github_pat_|xox[baprs]-)[A-Za-z0-9/_+=-]{16,}/.test(s)) {
    return true;
  }
  if (/https?:\/\/[^\s]+\/rest\/\d+\/[A-Za-z0-9]{16,}/.test(s)) return true;
  if (
    /\b(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['"]?[^\s'"]{12,}/i.test(
      s
    )
  ) {
    return true;
  }
  return false;
}

export function isTooRaw(card = {}) {
  const title = String(card.title || "").trim();
  const desc = String(card.description || "").trim();
  if (!title) return true;
  if (!desc || desc.length < 24) return true;
  if (/^(уточнить|todo|tbd|n\/a)\b/i.test(desc)) return true;
  return false;
}

export function looksLikeSpam(card = {}) {
  const title = String(card.title || "").trim();
  const desc = String(card.description || "").trim();
  if (!title && !desc) return true;
  if (/^(test|тест|asdf|xxx|foo|bar)$/i.test(title)) return true;
  return false;
}

export function xrefNeedsSlug(ref, houseSlug) {
  const s = String(ref || "").trim();
  if (!s) return false;
  if (/^[a-z0-9_-]+:[A-Z]{2,10}-\d+/i.test(s)) return false;
  if (/^https?:\/\//i.test(s) || s.startsWith("/")) return false;
  if (/^(doc|decision)-\d+/i.test(s)) return false;
  if (/^[A-Z]{2,10}-\d+(?:\.\d+)*$/i.test(s) && houseSlug) return true;
  return false;
}

export function fixXref(ref, houseSlug) {
  const s = String(ref || "").trim();
  if (xrefNeedsSlug(s, houseSlug) && houseSlug) {
    return `${houseSlug}:${s.toUpperCase()}`;
  }
  return s;
}

export function parseTriageMarker({ labels = [], comments = "" } = {}) {
  const labs = (labels || []).map((x) => String(x).trim().toLowerCase());
  for (const outcome of TRIAGE_OUTCOMES) {
    if (labs.includes(`triage:${outcome}`)) return outcome;
  }
  const m = String(comments || "").match(
    /autoscan:\s*triage:\s*(keep|absorb|drop|reroute|escalate|need_info)\b/i
  );
  return m ? m[1].toLowerCase() : null;
}

export function allowsRewrite(outcome) {
  return outcome === "keep";
}

export function sentComment(kind, preview) {
  const k = kind === "Client" ? "Client" : "CEO";
  const p = String(preview || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
  return `autoscan: Регистратор → myThings: sent ${k} preview ${p}`;
}

export function replyComment(kind, preview) {
  const k = kind === "Client" ? "Client" : "CEO";
  const p = String(preview || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
  return `autoscan: Регистратор ← myThings: reply ${k} preview ${p}`;
}

export function splitMarkdownSections(md) {
  const text = String(md || "").replace(/\r\n/g, "\n");
  const re = /^##[ \t]+(.+?)[ \t]*$/gm;
  const idxs = [];
  let match;
  while ((match = re.exec(text))) {
    idxs.push({
      title: match[1].trim(),
      start: match.index,
      headerEnd: match.index + match[0].length,
    });
  }
  if (!idxs.length) {
    return { preamble: text.trim(), sections: new Map() };
  }
  const preamble = text.slice(0, idxs[0].start).trim();
  const sections = new Map();
  for (let i = 0; i < idxs.length; i++) {
    const end = i + 1 < idxs.length ? idxs[i + 1].start : text.length;
    sections.set(idxs[i].title, text.slice(idxs[i].headerEnd, end).trim());
  }
  return { preamble, sections };
}

function formatCeoBody(prev, patch = {}) {
  const question =
    patch.ceoQuestion != null
      ? String(patch.ceoQuestion).trim()
      : extractNamedBlock(prev, "Вопрос") || "";
  const answer =
    patch.ceoAnswer != null
      ? String(patch.ceoAnswer).trim()
      : extractNamedBlock(prev, "Ответ") || "*(ждёт ответа)*";
  const triage = patch.triage || extractTriageLine(prev);
  const covers = patch.covers || extractCoversLine(prev);
  const status = patch.status != null ? String(patch.status).trim() : extractStatusLine(prev);
  const lines = ["### Вопрос", question || "—", "", "### Ответ", answer];
  const meta = [];
  if (triage) meta.push(`triage: ${triage}`);
  if (covers) meta.push(`covers: ${covers}`);
  if (status) meta.push(`status: ${status}`);
  if (meta.length) lines.push("", meta.join("\n"));
  return lines.join("\n").trim();
}

function formatClientBody(prev, patch = {}) {
  const prevQ = extractNamedBlock(prev, "Вопрос");
  if (patch.clientQuestion == null && patch.clientAnswer == null) return null;
  const question =
    patch.clientQuestion != null
      ? String(patch.clientQuestion).trim()
      : prevQ || "";
  const answer =
    patch.clientAnswer != null
      ? String(patch.clientAnswer).trim()
      : extractNamedBlock(prev, "Ответ") || "*(ждёт ответа)*";
  if (!question) return null;
  return ["### Вопрос", question, "", "### Ответ", answer].join("\n").trim();
}

function extractNamedBlock(body, name) {
  const m = String(body || "").match(
    new RegExp(
      `###\\s*${name}\\s*\\n([\\s\\S]*?)(?=\\n###\\s*|$)`,
      "i"
    )
  );
  return m ? m[1].trim() : "";
}

function extractTriageLine(body) {
  const m = String(body || "").match(
    /\btriage:\s*(keep|absorb|drop|reroute|escalate|need_info)\b/i
  );
  return m ? m[1].toLowerCase() : null;
}

function extractCoversLine(body) {
  const m = String(body || "").match(/\bcovers:\s*([A-Z]{2,10}-\d+(?:\.\d+)*)/i);
  return m ? m[1].toUpperCase() : null;
}

function extractStatusLine(body) {
  const m = String(body || "").match(/\bstatus:\s*(.+)$/im);
  return m ? m[1].trim() : "";
}

export function ticketStatusLine(outcome, { covers = null, reason = "" } = {}) {
  if (outcome === "drop") {
    const why = String(reason || "drop").replace(/\s+/g, " ").trim().slice(0, 120);
    return `не берём: ${why}`;
  }
  if (outcome === "absorb") {
    return `будет в рамках ${covers || ""}`.trim();
  }
  if (outcome === "keep") return "в очереди";
  return "";
}

export function allowsImmediateComplete(outcome) {
  return outcome === "drop";
}

export function allowsCompleteOnDone(outcome) {
  return outcome === "keep" || outcome === "absorb";
}

export function completeComment(todoId, reason) {
  const r = String(reason || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
  return `autoscan: Регистратор → myThings: complete ${String(todoId || "").toLowerCase()} ${r}`.trim();
}

export function alreadyCompletedComment(comments, todoId) {
  const id = String(todoId || "").toLowerCase();
  if (!id) return false;
  return new RegExp(
    `Регистратор → myThings: complete ${id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
    "i"
  ).test(String(comments || ""));
}

export function completeOnDoneMarker(todoId) {
  return `autoscan: complete-on-done source_todo_id:${String(todoId || "").toLowerCase()}`;
}

export function parseCompleteOnDoneIds(comments) {
  const out = [];
  const re =
    /complete-on-done source_todo_id:\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/gi;
  let m;
  const text = String(comments || "");
  while ((m = re.exec(text))) out.push(m[1].toLowerCase());
  return [...new Set(out)];
}

export function isTodoClosed(todo = {}) {
  return Boolean(todo.completed_at || todo.canceled_at || todo.trashed_at);
}

/**
 * Upsert CEO/Client; never rewrite Classifier body.
 * Wave A: Client placeholder unless a Client question already exists.
 * Wave B: clientQuestion after keep|need_info. No markdown checkboxes.
 */
export function mergeResultMarkdown(existing, patch = {}) {
  const { preamble, sections } = splitMarkdownSections(existing);
  const order = [];
  if (sections.has(CLASSIFIER)) order.push(CLASSIFIER);
  if (!order.includes(CEO)) order.push(CEO);
  if (!order.includes(CLIENT)) order.push(CLIENT);
  for (const key of sections.keys()) {
    if (!order.includes(key)) order.push(key);
  }

  const prevCeo = sections.get(CEO) || "";
  const touchCeo =
    patch.ceoQuestion != null ||
    patch.ceoAnswer != null ||
    patch.triage != null ||
    patch.covers != null ||
    patch.status != null ||
    /###\s*Вопрос/i.test(prevCeo);
  const ceoBody = touchCeo ? formatCeoBody(prevCeo, patch) : prevCeo;
  const prevClient = sections.get(CLIENT) || "";
  const formattedClient = formatClientBody(prevClient, patch);
  let clientBody;
  if (formattedClient) {
    clientBody = formattedClient;
  } else if (/###\s*Вопрос/i.test(prevClient)) {
    clientBody = prevClient;
  } else if (patch.clientBody != null) {
    clientBody = String(patch.clientBody).trim();
  } else {
    clientBody = "*ожидает решение CEO*";
  }

  const chunks = [];
  if (preamble) chunks.push(preamble);
  for (const name of order) {
    if (name === CLASSIFIER) {
      chunks.push(`## ${CLASSIFIER}\n${sections.get(CLASSIFIER) || ""}`.trimEnd());
    } else if (name === CEO) {
      chunks.push(`## ${CEO}\n${ceoBody}`.trimEnd());
    } else if (name === CLIENT) {
      chunks.push(`## ${CLIENT}\n${clientBody}`.trimEnd());
    } else {
      chunks.push(`## ${name}\n${sections.get(name) || ""}`.trimEnd());
    }
  }
  return stripResultCheckboxes(`${chunks.join("\n\n")}\n`);
}

export function stripResultCheckboxes(md) {
  return String(md || "").replace(/^(\s*[-*]\s+)\[[ xX]\]\s+/gm, "$1");
}

export function parseCeoReply(resultMd) {
  const { sections } = splitMarkdownSections(resultMd);
  const ceo = sections.get(CEO) || "";
  const answer = extractNamedBlock(ceo, "Ответ");
  const waiting =
    !answer ||
    /^\*?\(ждёт|\*ожидает|^—*$/i.test(answer) ||
    /^\*\(ждёт ответа\)\*$/i.test(answer);
  if (waiting) {
    return { answered: false, answer: "", triage: null, covers: null };
  }
  const tm =
    answer.match(/\btriage:\s*(keep|absorb|drop|reroute)\b/i) ||
    answer.match(/\b(keep|absorb|drop|reroute)\b/i);
  const cm =
    answer.match(/\bcovers:\s*([A-Z]{2,10}-\d+(?:\.\d+)*)/i) ||
    answer.match(/→\s*([A-Z]{2,10}-\d+(?:\.\d+)*)/);
  return {
    answered: true,
    answer,
    triage: tm ? tm[1].toLowerCase() : null,
    covers: cm ? cm[1].toUpperCase() : null,
  };
}

export function clientBlockIsEmpty(resultMd) {
  const { sections } = splitMarkdownSections(resultMd);
  const client = sections.get(CLIENT) || "";
  if (!client.trim()) return true;
  if (/ожидает решение CEO/i.test(client) && !/###\s*Вопрос/i.test(client)) {
    return true;
  }
  return !/###\s*Вопрос/i.test(client);
}

export function parseClientReply(resultMd) {
  const { sections } = splitMarkdownSections(resultMd);
  const client = sections.get(CLIENT) || "";
  const answer = extractNamedBlock(client, "Ответ");
  const waiting =
    !answer ||
    /^\*?\(ждёт|\*ожидает|^—*$/i.test(answer) ||
    /^\*\(ждёт ответа\)\*$/i.test(answer);
  if (waiting) {
    return { answered: false, answer: "" };
  }
  return { answered: true, answer };
}

export function waitingCeo(resultMd) {
  const { sections } = splitMarkdownSections(resultMd);
  const ceo = sections.get(CEO) || "";
  if (!/###\s*Вопрос/i.test(ceo)) return false;
  return !parseCeoReply(resultMd).answered;
}

export function waitingClient(resultMd) {
  const { sections } = splitMarkdownSections(resultMd);
  const client = sections.get(CLIENT) || "";
  if (!/###\s*Вопрос/i.test(client)) return false;
  return !parseClientReply(resultMd).answered;
}

export function allowsClientQuestion(outcome) {
  return outcome === "keep" || outcome === "need_info";
}

export function missingTicketFacts(card = {}) {
  const blob = [card.title, card.description, card.notes]
    .filter(Boolean)
    .join("\n");
  const missing = [];
  if (!/https?:\/\//i.test(blob)) missing.push("URL страницы");
  if (!/(шаг|воспроизвед|как повтор)/i.test(blob)) {
    missing.push("шаги воспроизведения");
  }
  if (!/(ожида|должно|фактическ)/i.test(blob)) {
    missing.push("ожидаемое поведение");
  }
  return missing;
}

export function clientFactQuestion(card = {}) {
  const missing = missingTicketFacts(card);
  if (!missing.length && !isTooRaw(card)) return null;
  const list = missing.length
    ? missing.join(", ")
    : "краткое as-is / to-be и как проверить";
  return `Нужны факты по тикету: ${list}. На какой странице это видно, какие шаги и что ожидали?`;
}

function draftNum(id) {
  const m = String(id || "").match(/(\d+(?:\.\d+)*)/);
  return m ? m[1] : String(id || "");
}

/**
 * Auto rules T01–T17 (wave A). Escalate checks do not archive.
 */
export function decideAuto(ctx = {}) {
  const card = ctx.card || {};
  const id = String(card.id || "");
  const blob = [card.title, card.description, card.notes, ...(card.references || [])]
    .filter(Boolean)
    .join("\n");
  const sourceTodoId = parseSourceTodoId({
    frontmatter: ctx.frontmatter || "",
    description: card.description || "",
    references: card.references || [],
  });
  const checks = [];

  if (looksLikeSecret(blob)) {
    checks.push("T12");
    return {
      outcome: "escalate",
      reason: "T12 secrets — стоп к CEO, не публиковать",
      covers: null,
      sourceTodoId,
      question:
        "В тексте наряда похожи на секреты/токены. Подтвердите redact и исход triage (keep / drop).",
      checks,
      fixPrimary: false,
      fixXrefs: [],
    };
  }

  const live = ctx.liveDrafts || [];
  if (sourceTodoId) {
    const dups = live.filter((d) => d.sourceTodoId === sourceTodoId && d.id !== id);
    if (dups.length) {
      const keeper = [ { id, sourceTodoId, created: ctx.created }, ...dups ].sort((a, b) =>
        draftNum(a.id).localeCompare(draftNum(b.id), undefined, { numeric: true })
      )[0];
      if (keeper.id !== id) {
        checks.push("T02");
        return {
          outcome: "absorb",
          reason: `T02 точный дубль source_todo_id → covers ${keeper.id}`,
          covers: keeper.id,
          sourceTodoId,
          question: null,
          checks,
          fixPrimary: false,
          fixXrefs: [],
        };
      }
    }
  }

  const covers = extractCoversId(card.description || "");
  if (covers && covers.toUpperCase() !== id.toUpperCase()) {
    checks.push("T04");
    return {
      outcome: "absorb",
      reason: `T04 явное «закрывает ${covers}»`,
      covers,
      sourceTodoId,
      question: null,
      checks,
      fixPrimary: false,
      fixXrefs: [],
    };
  }

  const repoHint = extractRepoHint(blob);
  const houseId = String(ctx.houseId || "").toLowerCase();
  if (repoHint && houseId && repoHint !== houseId && repoHint !== String(ctx.houseName || "").toLowerCase()) {
    checks.push("T01");
    return {
      outcome: "escalate",
      reason: `T01 зона: repo ${repoHint} ≠ дом ${houseId}`,
      covers: null,
      sourceTodoId,
      question: `Наряд в ${houseId}, классификатор указал repo: ${repoHint}. reroute в другой дом или keep здесь?`,
      checks,
      fixPrimary: false,
      fixXrefs: [],
      suggested: "reroute",
    };
  }

  const assignees = (card.assignees || []).map((a) => String(a).trim());
  const houseAssignee = ctx.houseAssignee || "";
  let fixPrimary = false;
  if (
    assignees.length === 1 &&
    /^@CEO$/i.test(assignees[0]) &&
    houseAssignee &&
    !/^@CEO$/i.test(houseAssignee)
  ) {
    checks.push("T08");
    fixPrimary = true;
  }

  const houseSlug = ctx.houseSlug || houseId;
  const fixXrefs = [];
  for (const ref of card.references || []) {
    if (xrefNeedsSlug(ref, houseSlug)) {
      checks.push("T09");
      fixXrefs.push({ from: ref, to: fixXref(ref, houseSlug) });
    }
  }

  if (isTooRaw(card)) {
    checks.push("T06");
    return {
      outcome: "need_info",
      reason: "T06 сырость — need_info, не drop",
      covers: null,
      sourceTodoId,
      question: null,
      checks,
      fixPrimary,
      fixXrefs,
    };
  }

  if (looksLikeSpam(card)) {
    checks.push("T11");
    return {
      outcome: "escalate",
      reason: "T11 похоже на spam/мусор",
      covers: null,
      sourceTodoId,
      question: `Похоже на мусор («${card.title}»). drop с причиной или keep?`,
      checks,
      fixPrimary,
      fixXrefs,
    };
  }

  const myTitle = normalizeTitle(card.title);
  if (myTitle) {
    const same = live.find(
      (d) => d.id !== id && normalizeTitle(d.title) === myTitle
    );
    if (same) {
      checks.push("T03");
      return {
        outcome: "escalate",
        reason: `T03 смысловой дубль с ${same.id}`,
        covers: same.id,
        sourceTodoId,
        question: `Покрыть **${same.id}** или оставить **${id}** отдельной нитью?`,
        checks,
        fixPrimary,
        fixXrefs,
      };
    }
  }

  const doneHits = ctx.doneHits || [];
  if (doneHits.length) {
    checks.push("T05");
    return {
      outcome: "escalate",
      reason: `T05 похоже уже Done (${doneHits[0].id})`,
      covers: doneHits[0].id,
      sourceTodoId,
      question: `Похоже уже сделано в **${doneHits[0].id}**. drop или keep?`,
      checks,
      fixPrimary,
      fixXrefs,
    };
  }

  if (ctx.configWarn) checks.push("T16");
  checks.push("T17");
  return {
    outcome: "keep",
    reason: "auto keep — дальше rewrite-on-draft",
    covers: null,
    sourceTodoId,
    question: null,
    checks,
    fixPrimary,
    fixXrefs,
  };
}

export function configDraftFirstWarn(configText) {
  const t = String(configText || "");
  const issues = [];
  if (/Approve/i.test(t) && /statuses:/i.test(t)) issues.push("Approve in statuses");
  if (/\bRewrite\b/.test(t) && /statuses:/i.test(t)) issues.push("Rewrite column");
  return issues;
}
