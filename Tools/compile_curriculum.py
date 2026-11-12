#!/usr/bin/env python3
"""Curriculum compiler for the Litmus NCERT chapters (architecture v4.0, change 4).

Commands
  compile          (default) validate every v4 chapter, verify every quote against its NCERT PDF
                   text, and write Curriculum/compiled/*.compiled.json plus Curriculum/review_report.html.
                   Exits 1 if any error is found.
  compile --release  also fails while any chapter's v4.1 review is not "approved".
  migrate          add the v4.1 fields (schemaRevision, review, keyPoint.role, keyPoint.followUp,
                   check.lexical) to the source chapters as suggestions, after backing them up.
                   Values already present are kept. --mirror also copies the result to JSON NCERT.
  detect-sources   work out which PDF text and page offset each chapter's quotes come from and
                   write Curriculum/pdf_sources.json.

Source chapters live in Litmus/ (the app loads them from there). Run from anywhere:
  python3 -I Tools/compile_curriculum.py [compile|migrate|detect-sources] [--release] [--mirror]
"""
import argparse
import glob
import hashlib
import html
import json
import os
import re
import shutil
import sys
from collections import Counter

COMPILER_VERSION = "1.0.0"
SCHEMA_REVISION = 1  # v4.1

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "Litmus")
# An optional copy of the authored chapter JSON kept outside the repository. Set NCERT_MIRROR_DIR to its path;
# without it, the script looks for a "JSON NCERT" folder next to the repository folder.
MIRROR_DIR = os.environ.get("NCERT_MIRROR_DIR", os.path.join(os.path.dirname(ROOT), "JSON NCERT"))
CURRICULUM_DIR = os.path.join(ROOT, "Curriculum")
PDF_TEXT_DIR = os.path.join(CURRICULUM_DIR, "pdf_text")
# Inside the app folder, so the compiled chapters ship in the app bundle (the folder is synced with
# the app target).
COMPILED_DIR = os.path.join(SOURCE_DIR, "Compiled")
FOLLOWUP_DIR = os.path.join(CURRICULUM_DIR, "followups")
SOURCES_FILE = os.path.join(CURRICULUM_DIR, "pdf_sources.json")
REPORT_FILE = os.path.join(CURRICULUM_DIR, "review_report.html")
BACKUP_DIRS = {
    SOURCE_DIR: os.path.join(ROOT, ".backup-2026-10-22"),
    MIRROR_DIR: os.path.join(MIRROR_DIR, ".backup-2026-10-22"),
}

ROLES = ("core", "supporting", "extra")
LEXICAL = ("evidence", "never")
BATCH_SIZE = 6  # M0 decision D1
CHECK_FIELDS = {"id", "criterion", "isRequired", "lexical", "followUp"}
KEYPOINT_FIELDS = {"id", "weight", "role", "text", "followUp", "followUpAllows", "assessment"}


# ---------------------------------------------------------------- loading

def chapter_files():
    """Every schema-4 chapter in the source folder, in a stable order."""
    files = []
    for path in sorted(glob.glob(os.path.join(SOURCE_DIR, "ncert_*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if data.get("schemaVersion") == 4:
            files.append((path, data))
    return files


def concepts_of(chapter):
    for topic in chapter["topics"]:
        for concept in topic["concepts"]:
            yield topic, concept


def norm_words(text):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", text.lower())).strip()


def contains_phrase(text, phrase):
    """Whole-word, case-insensitive phrase match after normalising punctuation."""
    p = norm_words(phrase)
    pattern = r"(?<![a-z0-9])" + re.escape(p) + r"(?:s|es)?(?![a-z0-9])"  # "system" also matches "systems"
    return bool(p) and re.search(pattern, norm_words(text)) is not None


# ---------------------------------------------------------------- v4.1 suggestions

def suggested_roles(concept):
    """weight >= 2 -> core, else supporting. A concept with no such keyPoint gets its heaviest
    keyPoint(s) promoted to core, so every concept has something that decides mastery."""
    kps = concept["keyPoints"]
    roles = {k["id"]: ("core" if k["weight"] >= 2 else "supporting") for k in kps}
    if "core" not in roles.values():
        top = max(k["weight"] for k in kps)
        for k in kps:
            if k["weight"] == top:
                roles[k["id"]] = "core"
    reasons = {}
    for k in kps:
        if k["weight"] >= 2:
            reasons[k["id"]] = f"weight {k['weight']}"
        elif roles[k["id"]] == "core":
            reasons[k["id"]] = "promoted: no keyPoint of weight 2+ in this concept"
        else:
            reasons[k["id"]] = "weight 1"
    return roles, reasons


SPECIFIC_TOKEN = re.compile(r"\b(?:[A-Z][a-z][A-Za-z'-]*|[A-Z]{2,}|\d[\d,.%]*)\b")


def suggested_lexical(check, keypoint):
    """`evidence` only for identification checks whose evidence is a specific name or number that
    the check itself mentions (v3.2 change 5 migration rule). Everything else stays `never`."""
    criterion = check["criterion"]
    if criterion.startswith("Uses the term"):
        return "evidence", "asks for a named term"
    if not criterion.startswith(("Names", "Mentions", "Gives an example", "Gives a ")):
        return "never", "not an identification check"
    specific = []
    for phrase in keypoint["assessment"]["requiredEvidence"]:
        if SPECIFIC_TOKEN.search(phrase) and contains_phrase(criterion, phrase):
            specific.append(phrase)
    if specific:
        return "evidence", "names " + ", ".join(specific[:3])
    return "never", "identification check, but no specific name or number in it"


def load_followups():
    """keyPointId -> (question, allowed mentions). In the TSV, [[words]] mark a topic word the question
    has to name (a case-study name, a date or a term the student is asked about). It is stored without
    the brackets and listed in keyPoint.followUpAllows so the leak check accepts it."""
    followups = {}
    for path in sorted(glob.glob(os.path.join(FOLLOWUP_DIR, "*.tsv"))):
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 2 or not parts[1].strip():
                    raise SystemExit(f"{os.path.basename(path)}:{n}: expected 'keyPointId<TAB>question'")
                if parts[0] in followups:
                    raise SystemExit(f"{os.path.basename(path)}:{n}: duplicate follow-up for {parts[0]}")
                question = parts[1].strip()
                allows = re.findall(r"\[\[(.+?)\]\]", question)
                followups[parts[0]] = (re.sub(r"\[\[(.+?)\]\]", r"\1", question), allows)
    return followups


# ---------------------------------------------------------------- writing JSON

def dump_chapter(data):
    """Indented JSON, with verify entries kept on one line each as in the hand-written files."""
    def render(value, indent):
        pad = "  " * indent
        if isinstance(value, dict):
            if set(value) == {"page", "quote", "supports"}:
                return json.dumps(value, ensure_ascii=False, separators=(", ", ": ")).replace("{", "{ ", 1)[:-1] + " }"
            if not value:
                return "{}"
            items = [f'{pad}  {json.dumps(k, ensure_ascii=False)}: {render(v, indent + 1)}' for k, v in value.items()]
            return "{\n" + ",\n".join(items) + f"\n{pad}}}"
        if isinstance(value, list):
            if not value:
                return "[]"
            if all(not isinstance(v, (dict, list)) for v in value) and all(isinstance(v, (int, float)) for v in value):
                return "[" + ", ".join(json.dumps(v) for v in value) + "]"
            items = [f"{pad}  {render(v, indent + 1)}" for v in value]
            return "[\n" + ",\n".join(items) + f"\n{pad}]"
        return json.dumps(value, ensure_ascii=False)
    return render(data, 0) + "\n"


def ordered(mapping, order):
    """Copy of `mapping` with keys in `order` first (missing ones skipped), then the rest."""
    out = {k: mapping[k] for k in order if k in mapping}
    out.update({k: v for k, v in mapping.items() if k not in out})
    return out


# ---------------------------------------------------------------- migrate

def write_with_backup(folder, name, text):
    target = os.path.join(folder, name)
    backup = os.path.join(BACKUP_DIRS[folder], name[:-5] + ".before-v41.json")
    os.makedirs(BACKUP_DIRS[folder], exist_ok=True)
    if os.path.exists(target) and not os.path.exists(backup):
        shutil.copy2(target, backup)
    with open(target, "w", encoding="utf-8") as f:
        f.write(text)


def migrate(mirror):
    if mirror and not os.path.isdir(MIRROR_DIR):
        raise SystemExit(f"mirror folder not found: {MIRROR_DIR} (it is never created automatically)")
    followups = load_followups()
    used_followups = set()
    changed = 0
    for path, chapter in chapter_files():
        before = json.dumps(chapter, sort_keys=True)
        chapter.setdefault("schemaRevision", SCHEMA_REVISION)
        chapter.setdefault("review", {
            "status": "pending",
            "reviewedBy": None,
            "reviewedOn": None,
            "note": "v4.1 fields (keyPoint.role, keyPoint.followUp, check.lexical) were filled in as suggestions by "
                    "compile_curriculum.py migrate. Check them in Curriculum/review_report.html, edit this file "
                    "where needed, then set status to \"approved\".",
        })
        for _, concept in concepts_of(chapter):
            roles, _ = suggested_roles(concept)
            new_kps = []
            for kp in concept["keyPoints"]:
                kp.setdefault("role", roles[kp["id"]])
                if kp["id"] in followups:  # the TSV is where follow-ups are written, so it always wins
                    used_followups.add(kp["id"])
                    kp["followUp"], allows = followups[kp["id"]]
                    if allows:
                        kp["followUpAllows"] = allows
                    else:
                        kp.pop("followUpAllows", None)
                for check in kp["assessment"]["checks"]:
                    check.setdefault("lexical", suggested_lexical(check, kp)[0])
                kp["assessment"]["checks"] = [ordered(c, ["id", "criterion", "isRequired", "lexical", "followUp"])
                                              for c in kp["assessment"]["checks"]]
                new_kps.append(ordered(kp, ["id", "weight", "role", "text", "followUp", "followUpAllows", "assessment"]))
            concept["keyPoints"] = new_kps
        chapter = ordered(chapter, ["schemaVersion", "schemaRevision", "framework", "gradeLevel", "subject", "book",
                                    "chapterNumber", "chapterName", "sourceStatus", "pageVerification", "review"])
        name = os.path.basename(path)
        text = dump_chapter(chapter)
        if json.dumps(chapter, sort_keys=True) != before:
            write_with_backup(SOURCE_DIR, name, text)
            changed += 1
            print(f"migrated {name}")
        if mirror:
            mirror_path = os.path.join(MIRROR_DIR, name)
            current = open(mirror_path, encoding="utf-8").read() if os.path.exists(mirror_path) else None
            if current != text:
                write_with_backup(MIRROR_DIR, name, text)
                print(f"mirrored {name} to {MIRROR_DIR}")
    unused = sorted(set(followups) - used_followups)
    if unused:
        print(f"warning: {len(unused)} follow-ups match no keyPoint: {', '.join(unused[:10])}")
    print(f"{changed} chapter(s) changed")


# ---------------------------------------------------------------- PDF quotes

def norm_quote(text):
    text = (text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
                .replace("–", "-").replace("—", "-").replace("`", "Rs "))
    text = re.sub(r"\s+", " ", text).lower()
    return re.sub(r"(\w)- (\w)", r"\1-\2", text)


def load_pdf_pages():
    pdfs = {}
    for path in glob.glob(os.path.join(PDF_TEXT_DIR, "*.txt")):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        pages = {m.group(1): norm_quote(m.group(2)) for m in re.finditer(
            r"===== PDF_PAGE \d+ LABEL (\S+) =====\n(.*?)(?=\n\n===== PDF_PAGE|\Z)", text, re.S)}
        pdfs[os.path.basename(path)[:-4]] = pages
    return pdfs


def verify_entries(chapter):
    return [(c["conceptId"], v) for _, c in concepts_of(chapter) for v in c["verify"]]


def detect_sources():
    pdfs = load_pdf_pages()
    out = {}
    for path, chapter in chapter_files():
        entries = verify_entries(chapter)
        best = (-1, None, 0)
        for name, pages in pdfs.items():
            for offset in range(-5, 150):
                hits = sum(norm_quote(v["quote"]).strip(" .") in pages.get(str(v["page"] - offset), "") for _, v in entries)
                if hits > best[0]:
                    best = (hits, name, offset)
        out[os.path.basename(path)] = {"pdf": best[1], "pageOffset": best[2]}
        print(f"{os.path.basename(path)}: {best[1]} offset {best[2]} ({best[0]}/{len(entries)} quotes)")
    with open(SOURCES_FILE, "w", encoding="utf-8") as f:
        json.dump({"note": "Which extracted NCERT PDF text each chapter's verify quotes come from. "
                           "pageOffset = printed page - PDF page label. Written by compile_curriculum.py "
                           "detect-sources; review before changing.", "chapters": out}, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------- validation

class Findings:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, where, message):
        self.errors.append((where, message))

    def warn(self, where, message):
        self.warnings.append((where, message))


def parse_pass_rule(rule):
    if rule in ("allRequired", "anyOf"):
        return {"kind": rule}
    match = re.fullmatch(r"minCount:(\d+)", rule)
    return {"kind": "minCount", "n": int(match.group(1))} if match else None


def answer_phrases(keypoint, concept):
    """requiredEvidence phrases the student must supply: anything not already shown to them in
    the concept's label or probe. A follow-up containing one of these gives the answer away."""
    shown = " ".join([concept["label"], concept["probe"]] + keypoint.get("followUpAllows", []))
    return [p for p in keypoint["assessment"]["requiredEvidence"] if not contains_phrase(shown, p)]


def validate_chapter(name, chapter, pdfs, sources, findings):
    stats = Counter()
    ids = Counter()
    if chapter.get("schemaRevision") != SCHEMA_REVISION:
        findings.error(name, f"schemaRevision is {chapter.get('schemaRevision')!r}; run migrate first")
    review = chapter.get("review", {})
    if review.get("status") not in ("pending", "approved"):
        findings.error(name, "review.status must be 'pending' or 'approved'")
    for check in chapter["articulationChecks"]:
        ids[check["id"]] += 1

    for topic, concept in concepts_of(chapter):
        cid = concept["conceptId"]
        ids[cid] += 1
        stats["concepts"] += 1
        for field in ("sourcePages", "verify", "cardText", "hint", "probe", "causeChain", "keyPoints"):
            if not concept.get(field):
                findings.error(cid, f"empty {field}")
        kp_ids = {k["id"] for k in concept["keyPoints"]}
        local_checks = set()
        misc_defined = {m["id"] for m in concept["misconceptions"]}
        misc_used = set()
        for m in misc_defined:
            ids[m] += 1
        core_weight = scored_weight = 0
        for kp in concept["keyPoints"]:
            kid = kp["id"]
            ids[kid] += 1
            stats["keyPoints"] += 1
            extra_fields = set(kp) - KEYPOINT_FIELDS
            if extra_fields:
                findings.error(kid, f"unknown keyPoint fields {sorted(extra_fields)}")
            role = kp.get("role")
            if role not in ROLES:
                findings.error(kid, f"role must be one of {ROLES}, found {role!r}")
            if role == "core":
                core_weight += kp["weight"]
                stats["core"] += 1
            if role in ("core", "supporting"):
                scored_weight += kp["weight"]
            if not isinstance(kp["weight"], int) or kp["weight"] < 1:
                findings.error(kid, "weight must be a positive whole number")
            assessment = kp["assessment"]
            if not assessment["requiredEvidence"]:
                findings.error(kid, "empty requiredEvidence")
            rule = parse_pass_rule(assessment["passRule"])
            checks = assessment["checks"]
            if rule is None:
                findings.error(kid, f"bad passRule {assessment['passRule']}")
            elif rule["kind"] == "allRequired" and not any(c["isRequired"] for c in checks):
                findings.error(kid, "allRequired with no required check")
            elif rule["kind"] == "minCount" and rule["n"] > len(checks):
                findings.error(kid, "minCount is larger than the number of checks")
            for check in checks:
                ids[check["id"]] += 1
                local_checks.add(check["id"])
                stats["checks"] += 1
                if set(check) - CHECK_FIELDS:
                    findings.error(check["id"], f"unknown check fields {sorted(set(check) - CHECK_FIELDS)}")
                if check.get("lexical") not in LEXICAL:
                    findings.error(check["id"], f"lexical must be one of {LEXICAL}")
                elif check["lexical"] == "evidence":
                    stats["lexicalEvidence"] += 1
                for leak in [p for p in answer_phrases(kp, concept) if contains_phrase(check.get("followUp", ""), p)]:
                    findings.error(check["id"], f"followUp gives away the answer ({leak!r})")
            for allowed in kp.get("followUpAllows", []):
                if not contains_phrase(kp.get("followUp", ""), allowed):
                    findings.error(kid, f"followUpAllows lists {allowed!r} but the follow-up does not use it")
            follow_up = kp.get("followUp")
            if follow_up:
                stats["followUps"] += 1
                for leak in [p for p in answer_phrases(kp, concept) if contains_phrase(follow_up, p)]:
                    findings.error(kid, f"followUp gives away the answer ({leak!r}): {follow_up}")
            elif role == "core":
                findings.warn(kid, "core keyPoint has no followUp; the concept hint will be used")
            for mid in assessment.get("misconceptionIds") or []:
                misc_used.add(mid)
                if mid not in misc_defined:
                    findings.error(kid, f"misconception {mid} is not defined in this concept")
        if core_weight == 0:
            findings.error(cid, "no core keyPoint (or core weight is 0)")
        if scored_weight == 0:
            findings.error(cid, "scored weight is 0")
        for mid in misc_defined - misc_used:
            findings.error(cid, f"misconception {mid} is not linked to any keyPoint")
        for link in concept["causeLinks"]:
            ids[link["id"]] += 1
            for linked in link["linksChecks"]:
                if linked not in local_checks:
                    findings.error(link["id"], f"links unknown check {linked}")
        covered = set()
        for entry in concept["verify"]:
            if entry["page"] not in range(1, 400) or not entry["quote"]:
                findings.error(cid, f"bad verify entry {entry}")
            for supported in entry["supports"]:
                covered.add(supported)
                if supported not in kp_ids:
                    findings.error(cid, f"verify supports unknown keyPoint {supported}")
        for kid in kp_ids - covered:
            findings.error(kid, "no verify entry supports this keyPoint")

    for item, count in ids.items():
        if count > 1:
            findings.error(name, f"duplicate id {item}")

    source = sources.get(name)
    if not source or source["pdf"] not in pdfs:
        findings.error(name, "no PDF source in Curriculum/pdf_sources.json; run detect-sources")
    else:
        pages = pdfs[source["pdf"]]
        for cid, entry in verify_entries(chapter):
            stats["quotes"] += 1
            if norm_quote(entry["quote"]).strip(" .") in pages.get(str(entry["page"] - source["pageOffset"]), ""):
                stats["quotesVerified"] += 1
            else:
                findings.error(cid, f"quote not found on printed page {entry['page']}: {entry['quote'][:80]}")
    return stats, ids


# ---------------------------------------------------------------- compile

def compile_concept(topic, concept):
    rules = {}
    keypoints = []
    for kp in concept["keyPoints"]:
        rule = parse_pass_rule(kp["assessment"]["passRule"])
        rules[kp["id"]] = rule
        keypoints.append({
            "id": kp["id"],
            "role": kp["role"],
            "weight": kp["weight"],
            "scored": kp["role"] != "extra",
            "passRule": rule,
            "followUp": kp.get("followUp"),
            "requiredEvidence": kp["assessment"]["requiredEvidence"],
            "checks": [{
                "id": c["id"],
                "criterion": c["criterion"],
                "isRequired": c["isRequired"],
                "lexical": c["lexical"],
                "followUp": c.get("followUp") or kp.get("followUp") or concept["hint"],
            } for c in kp["assessment"]["checks"]],
            "misconceptionIds": kp["assessment"].get("misconceptionIds") or [],
        })
    misconceptions = []
    for m in concept["misconceptions"]:
        linked = [k["id"] for k in concept["keyPoints"] if m["id"] in (k["assessment"].get("misconceptionIds") or [])]
        misconceptions.append({
            "id": m["id"],
            "wrong": m["wrong"],
            "fix": m["fix"],
            "checkId": "mchk_" + m["id"],
            "checkCriterion": f"The answer states or implies this wrong idea: {m['wrong']}",
            "fixCheckId": "mfix_" + m["id"],
            "fixCheckCriterion": f"Answer 2 states the correct idea: {m['fix']}",
            "keyPointIds": linked,
            "isRequired": any(k["role"] == "core" for k in concept["keyPoints"] if k["id"] in linked),
        })
    relevance = {
        "id": "chk_relevance",
        "criterion": f"The answer attempts to explain {concept['label']}, even if it uses everyday words instead of textbook terms.",
    }

    def chunks(ids):
        return [ids[i:i + BATCH_SIZE] for i in range(0, len(ids), BATCH_SIZE)]

    def keypoint_batches(kps):
        batches, current = [], []
        for kp in kps:
            ids = [c["id"] for c in kp["checks"]]
            if current and len(current) + len(ids) > BATCH_SIZE:
                batches.append(current)
                current = []
            current += ids
            while len(current) > BATCH_SIZE:
                batches.append(current[:BATCH_SIZE])
                current = current[BATCH_SIZE:]
        if current:
            batches.append(current)
        return batches

    core = [k for k in keypoints if k["role"] == "core"]
    other = [k for k in keypoints if k["role"] != "core"]
    b_batches = keypoint_batches(other)
    links = [l["id"] for l in concept["causeLinks"]]
    if links:
        if b_batches and len(b_batches[-1]) + len(links) <= BATCH_SIZE:
            b_batches[-1] += links
        else:
            b_batches += chunks(links)
    batches = {
        "topic": chunks([relevance["id"]] + [m["checkId"] for m in misconceptions]),
        "a": keypoint_batches(core),
        "b": b_batches,
    }

    grading = {
        "keyPoints": [{k: kp[k] for k in ("id", "role", "weight", "passRule", "misconceptionIds")}
                      | {"checks": [{k: c[k] for k in ("id", "criterion", "isRequired", "lexical")} for c in kp["checks"]]}
                      for kp in keypoints],
        "causeLinks": concept["causeLinks"],
        "misconceptions": [{k: m[k] for k in ("id", "wrong", "fix", "keyPointIds", "isRequired")} for m in misconceptions],
        "relevance": relevance,
    }
    concept_hash = hashlib.sha256(json.dumps(grading, sort_keys=True, ensure_ascii=False,
                                             separators=(",", ":")).encode("utf-8")).hexdigest()
    return {
        "conceptId": concept["conceptId"],
        "topicId": topic["topicId"],
        "topicTitle": topic["title"],
        "label": concept["label"],
        "headingType": concept.get("headingType"),
        "sourcePages": concept["sourcePages"],
        "conceptHash": concept_hash,
        "cardText": concept["cardText"],
        "hint": concept["hint"],
        "probe": concept["probe"],
        "relevanceCheck": relevance,
        "keyPoints": keypoints,
        "causeLinks": concept["causeLinks"],
        "misconceptions": misconceptions,
        "weights": {
            "core": sum(k["weight"] for k in keypoints if k["role"] == "core"),
            "scored": sum(k["weight"] for k in keypoints if k["scored"]),
        },
        "batches": batches,
    }


def compile_chapter(path, chapter):
    with open(path, "rb") as f:
        source_hash = hashlib.sha256(f.read()).hexdigest()
    return {
        "compilerVersion": COMPILER_VERSION,
        "schemaVersion": chapter["schemaVersion"],
        "schemaRevision": chapter["schemaRevision"],
        "sourceFile": os.path.basename(path),
        "sourceSha256": source_hash,
        "reviewStatus": chapter["review"]["status"],
        "framework": chapter["framework"],
        "gradeLevel": chapter["gradeLevel"],
        "subject": chapter["subject"],
        "book": chapter.get("book"),
        "chapterNumber": chapter.get("chapterNumber"),
        "chapterName": chapter["chapterName"],
        "articulationChecks": [dict(c, gradedBy="code") for c in chapter["articulationChecks"]],
        "chapterVocabulary": chapter["chapterVocabulary"],
        "concepts": [compile_concept(topic, concept) for topic, concept in concepts_of(chapter)],
    }


def compile_all(release):
    pdfs = load_pdf_pages()
    with open(SOURCES_FILE, encoding="utf-8") as f:
        sources = json.load(f)["chapters"]
    findings = Findings()
    all_ids = Counter()
    labels = Counter()
    summaries = []
    compiled = []
    files = chapter_files()
    if not files:
        raise SystemExit("no schema-4 chapters found in " + SOURCE_DIR)
    for path, chapter in files:
        name = os.path.basename(path)
        stats, ids = validate_chapter(name, chapter, pdfs, sources, findings)
        all_ids.update({i: 1 for i in ids})
        for _, concept in concepts_of(chapter):
            labels[concept["label"]] += 1
        status = chapter.get("review", {}).get("status")
        if status != "approved":
            (findings.error if release else findings.warn)(name, f"v4.1 review is {status!r}, not 'approved'")
        summaries.append((name, chapter, stats))
        if chapter.get("schemaRevision") == SCHEMA_REVISION:
            compiled.append((name, chapter, compile_chapter(path, chapter)))
    for item, count in all_ids.items():
        if count > 1:
            findings.error("all chapters", f"id {item} is used in more than one chapter")
    for label, count in labels.items():
        if count > 1:
            findings.error("all chapters", f"concept label {label!r} is used {count} times (the registry is keyed by label)")

    if not findings.errors:
        os.makedirs(COMPILED_DIR, exist_ok=True)
        for name, _, output in compiled:
            target = os.path.join(COMPILED_DIR, name[:-5] + ".compiled.json")
            with open(target, "w", encoding="utf-8") as f:
                json.dump(output, f, ensure_ascii=False, indent=2)
                f.write("\n")
    write_report(summaries, compiled, findings)

    total = Counter()
    for _, _, stats in summaries:
        total.update(stats)
    print(f"{len(summaries)} chapters · {total['concepts']} concepts · {total['keyPoints']} keyPoints "
          f"({total['core']} core) · {total['checks']} checks ({total['lexicalEvidence']} keyword-gradable) · "
          f"{total['followUps']} follow-ups · {total['quotesVerified']}/{total['quotes']} quotes verified")
    for where, message in findings.warnings[:15]:
        print(f"warning: {where}: {message}")
    if len(findings.warnings) > 15:
        print(f"warning: … {len(findings.warnings) - 15} more in the review report")
    for where, message in findings.errors:
        print(f"ERROR: {where}: {message}")
    if findings.errors:
        print(f"{len(findings.errors)} error(s); compiled files were not written. Report: {REPORT_FILE}")
        sys.exit(1)
    print(f"Compiled to {COMPILED_DIR}\nReport: {REPORT_FILE}")


# ---------------------------------------------------------------- review report

REPORT_CSS = """
:root { --bg:#fbfaf7; --panel:#ffffff; --ink:#1d1d1b; --muted:#6b6862; --line:#e4e0d8; --accent:#2f5d8a;
        --ok:#2e7d4f; --warn:#9a6a00; --err:#b3261e; --chip:#f1eee7; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg:#161615; --panel:#1f1f1d; --ink:#ecebe7; --muted:#a29f98; --line:#34332f; --accent:#8ab4e0;
  --ok:#7cc79a; --warn:#e2b54f; --err:#f08a80; --chip:#2a2926; } }
:root[data-theme="dark"] { --bg:#161615; --panel:#1f1f1d; --ink:#ecebe7; --muted:#a29f98; --line:#34332f;
  --accent:#8ab4e0; --ok:#7cc79a; --warn:#e2b54f; --err:#f08a80; --chip:#2a2926; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 24px; margin: 0 0 4px; } h2 { font-size: 19px; margin: 32px 0 8px; } h3 { font-size: 16px; margin: 20px 0 6px; }
.muted { color: var(--muted); }
.cards { display:grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin: 16px 0; }
.card { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:10px 12px; }
.card b { display:block; font-size: 20px; }
.chip { display:inline-block; padding:1px 8px; border-radius:999px; background:var(--chip); font-size:12px; }
.ok { color:var(--ok); } .warn { color:var(--warn); } .err { color:var(--err); }
details { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:8px 12px; margin:8px 0; }
summary { cursor:pointer; font-weight:600; }
.table-wrap { overflow-x:auto; }
table { width:100%; border-collapse:collapse; margin:8px 0; font-size:14px; }
th, td { text-align:left; vertical-align:top; padding:6px 8px; border-bottom:1px solid var(--line); }
th { color:var(--muted); font-weight:600; }
code { font-size: 12.5px; }
ul.issues { padding-left: 18px; }
"""


def esc(value):
    return html.escape(str(value))


def write_report(summaries, compiled, findings):
    total = Counter()
    for _, _, stats in summaries:
        total.update(stats)
    approved = sum(1 for _, chapter, _ in summaries if chapter.get("review", {}).get("status") == "approved")
    out = [f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
           f"<title>Curriculum Review Report</title><style>{REPORT_CSS}</style></head><body><main>",
           "<h1>Curriculum review report</h1>",
           f"<p class='muted'>compile_curriculum.py {COMPILER_VERSION} · schema v4.{SCHEMA_REVISION}. Every value marked "
           "<span class='chip'>suggested</span> was filled in by the migration and needs a person to check it. Edit the "
           "chapter JSON where a value is wrong, then set its <code>review.status</code> to <code>\"approved\"</code>.</p>",
           "<div class='cards'>",
           f"<div class='card'><b>{len(summaries)}</b>chapters ({approved} approved)</div>",
           f"<div class='card'><b>{total['concepts']}</b>concepts</div>",
           f"<div class='card'><b>{total['core']}/{total['keyPoints']}</b>core keyPoints</div>",
           f"<div class='card'><b>{total['lexicalEvidence']}/{total['checks']}</b>keyword-gradable checks</div>",
           f"<div class='card'><b>{total['followUps']}</b>follow-up questions</div>",
           f"<div class='card'><b>{total['quotesVerified']}/{total['quotes']}</b>quotes verified</div>",
           "</div>"]
    if findings.errors:
        out.append(f"<h2 class='err'>{len(findings.errors)} errors</h2><ul class='issues'>")
        out += [f"<li><code>{esc(w)}</code>: {esc(m)}</li>" for w, m in findings.errors]
        out.append("</ul>")
    else:
        out.append("<p class='ok'><b>No errors.</b></p>")
    if findings.warnings:
        out.append(f"<details><summary class='warn'>{len(findings.warnings)} warnings</summary><ul class='issues'>")
        out += [f"<li><code>{esc(w)}</code>: {esc(m)}</li>" for w, m in findings.warnings]
        out.append("</ul></details>")

    out.append("<h2>How the suggestions were made</h2><ul class='issues'>"
               "<li><b>Role:</b> keyPoints of weight 2 or more are <i>core</i> (scored, required for mastery); weight 1 is "
               "<i>supporting</i> (scored, never blocks mastery on its own). A concept with no weight-2 keyPoint has its "
               "heaviest keyPoint promoted to core. No keyPoint is suggested as <i>extra</i>.</li>"
               "<li><b>Keyword grading</b> (<code>lexical: evidence</code>): only checks that start with Names, Mentions, "
               "Gives an example or Uses the term, and whose evidence is a specific name or number that the check itself "
               "mentions. Everything else is <code>never</code>, so the keyword fallback returns uncertain for it.</li>"
               "<li><b>Follow-ups</b> were written per core keyPoint by Claude at authoring time. A follow-up may name the "
               "topic but must not contain an answer word: a <code>requiredEvidence</code> phrase that is not already in "
               "the concept's label or probe. The compiler rejects any that do.</li></ul>")

    for name, chapter, compiled_chapter in compiled:
        status = chapter["review"]["status"]
        out.append(f"<h2>{esc(chapter['subject'])} ch{esc(chapter.get('chapterNumber', '?'))}: {esc(chapter['chapterName'])} "
                   f"<span class='chip {'ok' if status == 'approved' else 'warn'}'>{esc(status)}</span></h2>"
                   f"<p class='muted'><code>{esc(name)}</code></p>")
        sources = {c["conceptId"]: c for _, c in concepts_of(chapter)}
        for concept in compiled_chapter["concepts"]:
            source = sources[concept["conceptId"]]
            _, role_reasons = suggested_roles(source)
            kp_allows = {k["id"]: k.get("followUpAllows", []) for k in source["keyPoints"]}
            out.append(f"<details><summary>{esc(concept['label'])} <span class='muted'>· core weight "
                       f"{concept['weights']['core']} of {concept['weights']['scored']}</span></summary>")
            out.append("<div class='table-wrap'><table><tr><th>keyPoint</th><th>Weight</th><th>Role</th><th>Follow-up question</th></tr>")
            for kp in concept["keyPoints"]:
                text = next(k["text"] for k in source["keyPoints"] if k["id"] == kp["id"])
                out.append(f"<tr><td><code>{esc(kp['id'])}</code><br><span class='muted'>{esc(text[:160])}"
                           f"{'…' if len(text) > 160 else ''}</span></td><td>{kp['weight']}</td>"
                           f"<td>{esc(kp['role'])}<br><span class='muted'>{esc(role_reasons[kp['id']])}</span></td>"
                           f"<td>{esc(kp['followUp'] or '— uses the concept hint')}"
                           + (f"<br><span class='muted'>names on purpose: {esc(', '.join(kp_allows[kp['id']]))}</span>"
                              if kp_allows.get(kp["id"]) else "") + "</td></tr>")
            out.append("</table></div>")
            evidence_rows = []
            for kp_source in source["keyPoints"]:
                for check in kp_source["assessment"]["checks"]:
                    if check["lexical"] == "evidence":
                        _, reason = suggested_lexical(check, kp_source)
                        evidence_rows.append(f"<tr><td><code>{esc(check['id'])}</code></td><td>{esc(check['criterion'])}</td>"
                                             f"<td class='muted'>{esc(reason)}</td></tr>")
            if evidence_rows:
                out.append("<h3>Checks the keyword fallback may pass</h3><div class='table-wrap'><table>"
                           "<tr><th>Check</th><th>Criterion</th><th>Why</th></tr>" + "".join(evidence_rows) + "</table></div>")
            out.append(f"<p class='muted'>Model batches: topic {len(concept['batches']['topic'])} · "
                       f"A {len(concept['batches']['a'])} · B {len(concept['batches']['b'])} · hash "
                       f"<code>{concept['conceptHash'][:12]}</code></p></details>")
    out.append("</main></body></html>")
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description="Compile and migrate NCERT curriculum chapters.")
    parser.add_argument("command", nargs="?", default="compile", choices=["compile", "migrate", "detect-sources"])
    parser.add_argument("--release", action="store_true", help="fail unless every chapter's review is approved")
    parser.add_argument("--mirror", action="store_true", help="migrate: also write the result to JSON NCERT")
    args = parser.parse_args()
    if args.command == "migrate":
        migrate(args.mirror)
    elif args.command == "detect-sources":
        detect_sources()
    else:
        compile_all(args.release)


if __name__ == "__main__":
    main()
