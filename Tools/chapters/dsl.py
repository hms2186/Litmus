"""Builds a v4 chapter JSON from a compact description, checking it as it goes.

Every quote is verified against the extracted NCERT PDF text at the printed page it cites, so a chapter
that is written cannot contain a quote that is not in the book. IDs are generated, so they follow the
naming used by the earlier chapters (chk_geo4_*, lnk_geo4_*, misc_geo4_*, geo10_ch4_t1_c1, ...).

A chapter is a dict `meta` and a list of topics: (title, [concept, ...]). See geo4.py for an example.
Run a chapter file directly: python3 -I Tools/chapters/geo4.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PDF_TEXT = os.path.join(ROOT, "Curriculum", "pdf_text")
OUT_DIR = os.path.join(ROOT, "Litmus")


def norm(s):
    s = s.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    s = s.replace("–", "-").replace("—", "-").replace("`", "Rs ")
    s = re.sub(r"\s+", " ", s).lower()
    return re.sub(r"(\w)- (\w)", r"\1-\2", s)


def load_pages(pdf):
    with open(os.path.join(PDF_TEXT, pdf + ".txt"), encoding="utf-8") as f:
        text = f.read()
    pages = {}
    for m in re.finditer(r"===== PDF_PAGE \d+ LABEL (\S+) =====\n(.*?)(?=\n\n===== PDF_PAGE|\Z)", text, re.S):
        pages[m.group(1)] = norm(m.group(2))
    return pages


class Problems(Exception):
    pass


def build(meta, topics, write=True):
    prefix = meta["prefix"]
    pages = load_pages(meta["pdf"])
    offset = meta["offset"]
    problems = []
    all_check_keys = set()
    followups = []  # (keyPointId, question) written to Curriculum/followups/ for the keyPoints that give one (fu=...)
    out_topics = []
    n_quotes = 0

    for t, (title, concepts) in enumerate(topics, 1):
        out_concepts = []
        for c, con in enumerate(concepts, 1):
            cid = f"{meta['conceptPrefix']}10_ch{meta['chapterNumber']}_t{t}_c{c}"
            if meta.get("conceptPrefix") == "sci9":
                cid = f"sci9_ch{meta['chapterNumber']}_t{t}_c{c}"
            if meta.get("cidPrefix"):
                cid = f"{meta['cidPrefix']}_ch{meta['chapterNumber']}_t{t}_c{c}"
            where = f"{cid} {con['label']}"
            misc_defs = con.get("misc", {})
            kps = []
            local_check_keys = []
            used_misc = set()
            for k, kp in enumerate(con["kps"], 1):
                checks = []
                for key, criterion, required in kp["checks"]:
                    if key in all_check_keys:
                        problems.append(f"{where}: duplicate check key {key}")
                    all_check_keys.add(key)
                    local_check_keys.append(key)
                    checks.append({"id": f"chk_{prefix}_{key}", "criterion": criterion, "isRequired": required})
                mids = []
                for mk in kp.get("misc", []):
                    if mk not in misc_defs:
                        problems.append(f"{where}: kp{k} refers to undefined misconception {mk}")
                    used_misc.add(mk)
                    mids.append(f"misc_{prefix}_{mk}")
                if kp.get("fu"):
                    followups.append((f"{prefix}_t{t}c{c}_kp{k}", kp["fu"]))
                kps.append({
                    "id": f"{prefix}_t{t}c{c}_kp{k}", "weight": kp["w"], "text": kp["text"],
                    "assessment": {"requiredEvidence": kp["ev"], "passRule": kp.get("rule", "allRequired"),
                                   "checks": checks, "misconceptionIds": mids},
                })
            for mk in set(misc_defs) - used_misc:
                problems.append(f"{where}: misconception {mk} is not used by any keyPoint")
            links = []
            for key, criterion, check_keys, required in con.get("links", []):
                for ck in check_keys:
                    if ck not in local_check_keys:
                        problems.append(f"{where}: link {key} refers to unknown check {ck}")
                links.append({"id": f"lnk_{prefix}_{key}", "linksChecks": [f"chk_{prefix}_{ck}" for ck in check_keys],
                              "criterion": criterion, "isRequired": required})
            verify = []
            covered = set()
            for page, quote, supports in con["verify"]:
                n_quotes += 1
                label = str(page - offset)
                q = norm(quote).strip(" .")
                if q not in pages.get(label, ""):
                    found = [str(int(p) + offset) for p, body in pages.items() if q in body]
                    problems.append(f"{where}: quote not on printed page {page} "
                                    f"({'found on p' + ','.join(found) if found else 'not found anywhere'}): {quote[:90]}")
                for s in supports:
                    if not 1 <= s <= len(kps):
                        problems.append(f"{where}: verify supports kp{s}, which does not exist")
                    covered.add(s)
                verify.append({"page": page, "quote": quote, "supports": [f"{prefix}_t{t}c{c}_kp{s}" for s in supports]})
            for k in range(1, len(kps) + 1):
                if k not in covered:
                    problems.append(f"{where}: kp{k} has no verify quote")
            out_concepts.append({
                "conceptId": cid, "label": con["label"], "headingType": con.get("type", "heading"),
                "sourcePages": con["pages"], "cardText": con["card"], "hint": con["hint"], "probe": con["probe"],
                "causeChain": con["chain"], "causeLinks": links, "keyPoints": kps,
                "acceptedExamples": con.get("accepted", []), "extraExamplesOk": con.get("extra", []),
                "misconceptions": [{"id": f"misc_{prefix}_{mk}", "wrong": w, "fix": f} for mk, (w, f) in misc_defs.items()],
                "verify": verify,
            })
        out_topics.append({"topicId": f"{meta['topicPrefix']}_t{t}", "title": title, "concepts": out_concepts})

    if problems:
        raise Problems("\n".join(problems))

    vocab = meta["vocab"]
    chapter = {
        "schemaVersion": 4, "framework": "NCERT", "gradeLevel": meta["gradeLevel"], "subject": meta["subject"],
        "book": meta["book"], "chapterNumber": meta["chapterNumber"], "chapterName": meta["chapterName"],
        "sourceStatus": f"Built from the NCERT PDF {meta['pdf']} ({meta['edition']}). Every verify quote was matched against "
                        "the extracted text of the printed page it cites.",
        "pageVerification": {"status": "confirmed", "edition": f"{meta['bookTitle']}, {meta['edition']}, chapter {meta['pageRange']}",
                             "note": meta["note"]},
        "articulationChecks": [
            {"id": f"chk_{prefix}_art_complete_sentences", "criterion": "The answer is written in complete sentences, not a list of fragments.", "isRequired": True},
            {"id": f"chk_{prefix}_art_chapter_terms",
             "criterion": "The answer correctly uses at least one term from this chapter, for example " + ", ".join(vocab[:8]) + ".",
             "isRequired": True},
        ],
        "chapterVocabulary": vocab,
        "topics": out_topics,
    }
    if write:
        path = os.path.join(OUT_DIR, meta["file"])
        with open(path, "w", encoding="utf-8") as f:
            json.dump(chapter, f, ensure_ascii=False, indent=2)
            f.write("\n")
    if write and followups:
        fu_dir = os.path.join(ROOT, "Curriculum", "followups")
        name = "chapter_" + meta["file"].replace("ncert_", "").replace(".json", "") + ".tsv"
        with open(os.path.join(fu_dir, name), "w", encoding="utf-8") as f:
            f.write("# keyPointId\tfollow-up question (asked when this keyPoint is uncertain; must not contain the answer)\n")
            for kid, q in followups:
                f.write(f"{kid}\t{q}\n")
    n_concepts = sum(len(t["concepts"]) for t in out_topics)
    n_kps = sum(len(c["keyPoints"]) for t in out_topics for c in t["concepts"])
    print(f"{meta['file']}: {n_concepts} concepts, {n_kps} keyPoints, {n_quotes} quotes verified")
    return chapter


def run(meta, topics):
    try:
        build(meta, topics)
    except Problems as e:
        print(f"{meta['file']}: NOT WRITTEN, {len(str(e).splitlines())} problem(s):\n{e}")
        sys.exit(1)
