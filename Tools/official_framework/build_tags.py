#!/usr/bin/env python3 -I
"""Builds the official-framework data and the concept tags.

Input : official_science.json and official_ss.json (from parse_official.py) and Litmus/Compiled/*.compiled.json
Output: Curriculum/official/cbse_learning_framework.json  (chapters, learning outcomes, indicators, cognitive levels)
        Curriculum/official/cognitive_level_rules.json    (the verb rules used for the levels, for review)
        Curriculum/official/concept_tags.json             (one entry per compiled concept)

The compiled chapters themselves are not changed: their hashes are frozen by the release gate and conceptHash covers
everything that affects grading. Tags are keyed by conceptId and can be embedded at the next freeze.

Matching: Class 10 chapters are matched by name (the books did not change). Everything else, and the learning
outcomes inside a chapter, is matched by TF-IDF similarity; Class 10 gives a measured accuracy for that method.
Every tag is `reviewed: false` until a teacher confirms it.
"""
import collections, datetime, glob, hashlib, json, math, os, re, sys

WORK, ROOT = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "Curriculum", "official")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ cognitive levels (CBSE Learning Framework taxonomy)
# Dispositions = values and attitudes outcomes (exhibits, takes initiative...) which the taxonomy does not rank.
# Science taxonomy (section 7): Knowing = Recall/Recognise, Describe, Provide Examples; Applying = Compare/Contrast/Classify,
# Relate, Use Models, Interpret Information, Explain; Reasoning = Analyse, Synthesise, Formulate/Hypothesise/Predict,
# Design Investigations, Evaluate, Draw Conclusions, Generalise, Justify.
VERBS = {
    "Knowing": ["recalls", "recognises", "recognizes", "identifies", "states", "mentions", "lists", "names", "defines",
                "describes", "locates", "labels", "retrieves", "narrates", "gives", "provides", "writes", "recites", "traces",
                "outlines", "reads", "knows", "enumerates"],
    "Applying": ["differentiates", "distinguishes", "compares", "contrasts", "classifies", "categorises", "categorizes",
                 "sorts", "relates", "links", "connects", "explains", "illustrates", "interprets", "calculates", "applies",
                 "uses", "demonstrates", "draws", "measures", "solves", "represents", "verifies", "conducts", "performs",
                 "observes", "determines", "expresses", "estimates", "constructs", "demonstrate", "separates", "balances",
                 "relate", "shows", "examines", "extracts", "prepares", "tests", "experiments", "collects", "records",
                 "writes balanced", "derives", "presents", "explores", "summarises", "discusses", "determine"],
    "Dispositions": ["exhibits", "takes", "propagates", "communicates", "shares", "appreciates", "respects", "values",
                     "empathises", "motivates", "advocates for"],
    "Reasoning": ["analyses", "analyzes", "synthesises", "predicts", "hypothesises", "formulates", "plans", "designs",
                  "evaluates", "justifies", "infers", "deduces", "concludes", "generalises", "investigates", "assesses",
                  "argues", "critiques", "appraises", "advocates", "proposes", "extrapolates", "debates", "judges",
                  "reflects", "suggests", "recommends", "decides", "weighs", "validates", "discovers", "creates", "rationalises"],
}
LOOKUP = {}
for level, words in VERBS.items():
    for w in words:
        LOOKUP.setdefault(w, level)
SPECIAL = [(r"^draws (a )?(conclusion|inference)", "Reasoning"), (r"^deduces", "Reasoning"), (r"^infers", "Reasoning")]


def level_of(text):
    t = text.strip().lower()
    for rx, lv in SPECIAL:
        if re.match(rx, t):
            return lv, "verb-rule"
    first = re.split(r"[\s/,:;.]+", t)[0] if t else ""
    if first in LOOKUP:
        return LOOKUP[first], "verb-rule"
    return None, "unclassified"


# ------------------------------------------------------------------ similarity helpers
STOP = set("the a an and or of in on to for with by from as at is are was were be been it its this that these those their there "
           "which who whom what when where how why not no can may also into than then such any all each other more most some own "
           "use used using state states stated describes describe explain explains identifies identify differentiates differentiate "
           "between about based student answer answers includes include including given give gives".split())


def stem(w):
    for suf in ("ations", "ation", "ings", "ing", "ies", "ied", "ed", "es", "s", "ly"):
        if w.endswith(suf) and len(w) - len(suf) >= 4:
            return w[: -len(suf)] + ("y" if suf in ("ies", "ied") else "")
    return w


def toks(text):
    return [stem(w) for w in re.findall(r"[a-z]{3,}", text.lower()) if w not in STOP]


def vec_of(doc, idf):
    tf = collections.Counter(doc)
    v = {w: (1 + math.log(c)) * idf.get(w, 1.0) for w, c in tf.items()}
    norm = math.sqrt(sum(x * x for x in v.values())) or 1
    return {w: x / norm for w, x in v.items()}


def cos(a, b):
    if len(a) > len(b):
        a, b = b, a
    return sum(x * b.get(w, 0) for w, x in a.items())


# ------------------------------------------------------------------ load
official = json.load(open(f"{WORK}/official_science.json")) + json.load(open(f"{WORK}/official_ss.json"))
for c in official:
    c["area"] = "Science" if c["doc"] == "science" else c["area"]
    c["cls"] = "Class 9" if c["class"] == "IX" else "Class 10"
    for clo in c["clos"]:
        clo["level"], clo["levelSource"] = level_of(clo["text"])
        for ind in clo["indicators"]:
            ind["level"], ind["levelSource"] = level_of(ind["text"])
            if ind["level"] is None and clo["level"]:
                ind["level"], ind["levelSource"] = clo["level"], "from-outcome"

compiled = []
for f in sorted(glob.glob(f"{ROOT}/Litmus/Compiled/*.compiled.json")):
    d = json.load(open(f))
    area = {"Civics": "Political Science", "Political Science": "Political Science"}.get(d["subject"], d["subject"])
    compiled.append({"file": os.path.basename(f), "cls": d["gradeLevel"], "area": area, "subject": d["subject"],
                     "no": d["chapterNumber"], "name": d["chapterName"], "concepts": d["concepts"]})


def concept_text(c):
    parts = [c["label"], c["label"], c["hint"], c["probe"], c["cardText"], c["relevanceCheck"]["criterion"]]
    for kp in c["keyPoints"]:
        parts += kp["requiredEvidence"] + [x["criterion"] for x in kp["checks"]]
    parts += [x["criterion"] for x in c["causeLinks"]] + [m["wrong"] for m in c["misconceptions"]]
    return " ".join(parts)


def clo_text(clo):
    return " ".join([clo["text"]] + [i["text"] for i in clo["indicators"]])


docs = [toks(clo_text(clo)) for c in official for clo in c["clos"]] + [toks(concept_text(x)) for ch in compiled for x in ch["concepts"]]
df = collections.Counter()
for d in docs:
    df.update(set(d))
IDF = {w: math.log((len(docs) + 1) / (n + 1)) + 1 for w, n in df.items()}
for c in official:
    for clo in c["clos"]:
        clo["_v"] = vec_of(toks(clo_text(clo)), IDF)
        for ind in clo["indicators"]:
            ind["_v"] = vec_of(toks(ind["text"]), IDF)
    c["_v"] = vec_of(toks(" ".join(clo_text(x) for x in c["clos"])), IDF)


def jaccard(a, b):
    sa, sb = set(toks(a)), set(toks(b))
    return len(sa & sb) / len(sa | sb) if sa | sb else 0


def name_match(ch):
    pool = [o for o in official if o["cls"] == ch["cls"] and o["area"] == ch["area"]]
    best = max(pool, key=lambda o: jaccard(o["name"], ch["name"]), default=None)
    return best if best and jaccard(best["name"], ch["name"]) >= 0.5 else None


# ------------------------------------------------------------------ calibration on Class 10 (chapter known by name)
calib = []
for ch in compiled:
    truth = name_match(ch) if ch["cls"] == "Class 10" else None
    if truth is None:
        continue
    pool = [o for o in official if o["cls"] == ch["cls"] and o["area"] == ch["area"]]
    for c in ch["concepts"]:
        cv = vec_of(toks(concept_text(c)), IDF)
        ranked = sorted(((cos(cv, o["_v"]), o) for o in pool), key=lambda t: -t[0])
        calib.append((ranked[0][0], ranked[0][1] is truth))
calibration = {"concepts": len(calib), "chapterFoundBySimilarity": round(sum(ok for _, ok in calib) / len(calib), 3)}
for t in (0.10, 0.15, 0.20):
    sel = [ok for s, ok in calib if s >= t]
    calibration[f"score>={t}"] = {"coverage": round(len(sel) / len(calib), 3), "precision": round(sum(sel) / max(1, len(sel)), 3)}

# ------------------------------------------------------------------ tag every concept
PROPOSED, WEAK = 0.15, 0.10     # Class 9 chapter similarity thresholds (precision on Class 10: ~93% / ~90%)
tags, stats = {}, collections.Counter()
for ch in compiled:
    truth = name_match(ch) if ch["cls"] == "Class 10" else None
    pool = [o for o in official if o["cls"] == ch["cls"] and o["area"] == ch["area"]] if ch["area"] != "Social Science" else []
    for c in ch["concepts"]:
        cv = vec_of(toks(concept_text(c)), IDF)
        if truth is not None:
            chosen, chap_score, method, status = truth, cos(cv, truth["_v"]), "chapter-name", "chapter-confirmed"
        else:
            ranked = sorted(((cos(cv, o["_v"]), o) for o in pool), key=lambda t: -t[0])
            if not ranked or ranked[0][0] < WEAK:
                tags[c["conceptId"]] = {"status": "unmapped", "reviewed": False,
                                        "reason": "no official chapter covers this topic (new 2025-26 book content)"
                                        if ch["cls"] == "Class 9" else "no official chapter for this book"}
                stats["unmapped"] += 1
                continue
            chap_score, chosen = ranked[0]
            method, status = "similarity", ("proposed" if chap_score >= PROPOSED else "weak")
        clo_scores = sorted(((cos(cv, clo["_v"]), clo) for clo in chosen["clos"]), key=lambda t: -t[0])
        outcomes = [{"clo": clo["id"], "score": round(s, 3), "text": clo["text"], "ncertLO": clo.get("ncertLO"),
                     "level": clo["level"], "indicators": [i["id"] for i in clo["indicators"]]}
                    for s, clo in clo_scores[:3] if s > 0.05]
        ind_scores = sorted(((cos(cv, i["_v"]), i) for clo in chosen["clos"] for i in clo["indicators"]), key=lambda t: -t[0])
        indicators = [{"id": i["id"], "score": round(s, 3), "level": i["level"], "text": i["text"]}
                      for s, i in ind_scores[:3] if s > 0.06]
        levels = sorted({o["level"] for o in outcomes if o["level"]} | {i["level"] for i in indicators if i["level"]},
                        key=["Knowing", "Applying", "Reasoning", "Dispositions"].index)
        tags[c["conceptId"]] = {
            "status": status, "reviewed": False, "method": method,
            "officialClass": chosen["class"], "officialArea": chosen["area"], "officialChapter": chosen["name"],
            "chapterScore": round(chap_score, 3), "cognitiveLevels": levels,
            "outcomes": outcomes, "indicators": indicators,
        }
        stats[status] += 1

# ------------------------------------------------------------------ write
def strip(o):
    return {k: v for k, v in o.items() if not k.startswith("_")}


framework = {
    "meta": {
        "title": "CBSE Learning Framework (Classes IX and X): content-domain learning outcomes and indicators",
        "extractedOn": datetime.date.today().isoformat(),
        "sources": [
            {"name": "Learning_Standards_Science.pdf", "url": "https://cbseacademic.nic.in/cbe/documents/Learning_Standards_Science.pdf"},
            {"name": "Learning_Standards_SocialScience.pdf", "url": "https://cbseacademic.nic.in/cbe/documents/Learning_Standards_SocialScience.pdf"},
        ],
        "publisher": "Central Board of Secondary Education, with Azim Premji University; aligned to NCERT secondary-stage learning outcomes",
        "method": "positioned text lines (PDFKit) -> parse_official.py; indicator numbering verified contiguous",
        "levels": "Knowing / Applying / Reasoning from the framework's own taxonomy; assigned by the leading verb (see cognitive_level_rules.json), not stated in the source per indicator",
        "note": "Class IX chapters follow the previous NCERT books; the app's Class 9 books are the 2025-26 editions.",
    },
    "chapters": [strip({**c, "clos": [strip({**clo, "indicators": [strip(i) for i in clo["indicators"]]}) for clo in c["clos"]]}) for c in official],
}
json.dump(framework, open(f"{OUT}/cbse_learning_framework.json", "w"), indent=1, ensure_ascii=False)
json.dump({"note": "First word of an outcome or indicator decides its level. Reviewable and editable.", "rules": VERBS,
           "special": [r for r, _ in SPECIAL]}, open(f"{OUT}/cognitive_level_rules.json", "w"), indent=1)
json.dump({"meta": {"generatedBy": "Tools/official_framework/build_tags.py", "reviewedAll": False,
                    "statuses": {"chapter-confirmed": "Class 10: official chapter matched by name; outcomes and indicators proposed by similarity",
                                 "proposed": "Class 9: chapter proposed by similarity (>=0.15)",
                                 "weak": "Class 9: chapter proposed by similarity (0.10-0.15), check first",
                                 "unmapped": "no official source covers this topic"},
                    "calibration": calibration},
           "tags": tags}, open(f"{OUT}/concept_tags.json", "w"), indent=1, ensure_ascii=False)
print("tags", dict(stats), "of", sum(stats.values()))
print("calibration", json.dumps(calibration))
n_ind = sum(len(clo["indicators"]) for c in official for clo in c["clos"])
unclassified = sum(1 for c in official for clo in c["clos"] for i in clo["indicators"] if i["level"] is None)
by_level = collections.Counter(i["level"] for c in official for clo in c["clos"] for i in clo["indicators"])
print("indicators", n_ind, "unclassified", unclassified, dict(by_level))
