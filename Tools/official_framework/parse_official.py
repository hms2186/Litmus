#!/usr/bin/env python3 -I
"""Extracts chapters, NCERT learning outcomes, content-domain learning outcomes (CLO) and indicators from the
CBSE Learning Framework PDFs (positioned text lines from PDFKit). Output is plain JSON for review."""
import json, re, sys, collections

LABEL_LO = re.compile(r'^LO\s*(\d+)\s*[:.]')
LABEL_CLO = re.compile(r'^CLO\s*(\d+)\s*[:.]')
LABEL_IND = re.compile(r'^C\s*(\d+)\s*[:.]')
SCI_CHAPTER = re.compile(r'^Chapter\s+(\d+)\s*[–\-:.]?\s*(.*)$')
SS_CHAPTER = re.compile(r'^(\d{1,2})\.\s+([A-Z].*)$')
CLASS_RE = re.compile(r'^9\.([12])\s+Class\s+(IX|X)\b')
AREA_RE = re.compile(r'^9\.([12])\.(\d)\s+(Geography|History|Political Science|Economics)\b')
STOP_RE = re.compile(r'^10\.\s*(Sample|[A-Z])')


def clean(t):
    return re.sub(r'\s+', ' ', t.replace(' ', ' ')).strip()


def join(parts):
    text = ' '.join(clean(p) for p in parts if clean(p))
    return re.sub(r'\s+([,.;:?)])', r'\1', text).replace('( ', '(')


def parse(doc_kind, lines_path, first_page, last_page):
    L = json.load(open(lines_path))
    pages = collections.defaultdict(list)
    for l in L:
        l['t'] = l['t'].rstrip('\n')
        pages[l['p']].append(l)
    chapters = []
    cur_ch = None
    cur_cls = None
    cur_area = None
    last_clo = None
    done = False
    parity_cols = {}
    for p in range(first_page, last_page + 1):
        if done:
            break
        lines = pages.get(p, [])
        if not lines:
            continue
        # section headers
        for l in lines:
            t = clean(l['t'])
            m = CLASS_RE.match(t)
            if m and p >= 20:
                cur_cls = m.group(2)
            m = AREA_RE.match(t)
            if m and p >= 20:
                cur_area = m.group(3)
        # column positions: from labels on this page, else from a page of the same parity
        def minx(rx):
            xs = [l['x0'] for l in lines if rx.match(clean(l['t'])) and l['x0'] > 150]
            return min(xs) if xs else None
        lo_x, clo_x, ind_x = minx(LABEL_LO), minx(LABEL_CLO), minx(LABEL_IND)
        key = p % 2
        if lo_x and clo_x and ind_x:
            parity_cols[key] = (lo_x, clo_x, ind_x)
        elif key in parity_cols:
            lo_x, clo_x, ind_x = parity_cols[key]
        else:
            continue
        # tolerate a few points of jitter
        def col(x):
            if x < lo_x - 8:
                return 'ch'
            if x < clo_x - 8:
                return 'lo'
            if x < ind_x - 8:
                return 'clo'
            return 'ind'
        by = collections.defaultdict(list)
        for l in sorted(lines, key=lambda l: (-l['y1'], l['x0'])):
            t = clean(l['t'])
            if not t or re.fullmatch(r'\d{1,3}', t):
                continue
            if STOP_RE.match(t) and p > first_page + 3 and l['x0'] < 120 and not LABEL_IND.match(t):
                done = True
                break
            by[col(l['x0'])].append((l['y1'], t))
        if done:
            break
        # chapters on this page (column 1), top to bottom
        ch_events = []
        c1 = by['ch']
        i = 0
        while i < len(c1):
            y, t = c1[i]
            m = SCI_CHAPTER.match(t) if doc_kind == 'science' else SS_CHAPTER.match(t)
            if m and not t.startswith('•'):
                name = [m.group(2)]
                j = i + 1
                while j < len(c1) and not c1[j][1].startswith(('Key', '•', 'Content')) and not (SS_CHAPTER.match(c1[j][1]) if doc_kind != 'science' else False) \
                        and len(name) < 4 and (c1[j][0] - c1[j - 1][0]) > -20:
                    name.append(c1[j][1]); j += 1
                ch_events.append((y, int(m.group(1)), join(name)))
                i = j
            else:
                i += 1
        # labelled items in the other columns
        def items(column, rx):
            out = []
            rows = by[column]
            for y, t in rows:
                m = rx.match(t)
                if m:
                    out.append({'y': y, 'id': int(m.group(1)), 'parts': [rx.sub('', t, count=1).strip()]})
            for y, t in rows:
                if rx.match(t):
                    continue
                above = [it for it in out if it['y'] >= y - 2]
                if above:
                    min(above, key=lambda it: it['y'] - y)['parts'].append(t)
            return out
        los, clos, inds = items('lo', LABEL_LO), items('clo', LABEL_CLO), items('ind', LABEL_IND)
        # events in reading order
        label_ys = [c['y'] for c in clos] + [o['y'] for o in los]
        def chapter_top(y):
            # the chapter name sits a little below the top of its first row: start the chapter at that row
            cand = [ly for ly in label_ys if y - 4 <= ly <= y + 70]
            return min(cand) + 1 if cand else y
        events = [('ch', chapter_top(y), e) for y, *e in ch_events] + [('clo', c['y'], c) for c in clos] + \
                 [('lo', o['y'], o) for o in los] + [('ind', i['y'], i) for i in inds]
        order = {'ch': 0, 'lo': 1, 'clo': 2, 'ind': 3}
        events.sort(key=lambda e: (-round(e[1] / 3), order[e[0]]))
        last_lo = None
        for kind, y, obj in events:
            if kind == 'ch':
                no, name = obj
                key = (cur_cls, cur_area, no, name.lower())
                existing = next((c for c in chapters if (c['class'], c['area'], c['chapterNo'], c['name'].lower()) == key[:1] + key[1:]), None)
                if existing is not None:
                    cur_ch = existing
                    last_clo = cur_ch['clos'][-1] if cur_ch['clos'] else None
                    continue
                cur_ch = {'doc': doc_kind, 'class': cur_cls, 'area': cur_area, 'chapterNo': no, 'name': name,
                          'page': p, 'clos': [], 'ncertLOs': []}
                chapters.append(cur_ch)
                last_clo = None
            elif kind == 'lo' and cur_ch is not None:
                last_lo = 'LO%d' % obj['id']
                if last_lo not in [x['id'] for x in cur_ch['ncertLOs']]:
                    cur_ch['ncertLOs'].append({'id': last_lo, 'text': join(obj['parts'])})
            elif kind == 'clo' and cur_ch is not None:
                last_clo = {'id': 'CLO%d' % obj['id'], 'text': join(obj['parts']), 'ncertLO': last_lo, 'indicators': [], 'page': p}
                cur_ch['clos'].append(last_clo)
            elif kind == 'ind' and cur_ch is not None:
                target = last_clo
                if target is None and cur_ch['clos']:
                    target = cur_ch['clos'][-1]
                if target is not None:
                    target['indicators'].append({'id': 'C%d' % obj['id'], 'text': join(obj['parts'])})
    return chapters


if __name__ == '__main__':
    kind, lines_path, first, last, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    data = parse(kind, lines_path, first, last)
    json.dump(data, open(out, 'w'), indent=1, ensure_ascii=False)
    n_clo = sum(len(c['clos']) for c in data)
    n_ind = sum(len(x['indicators']) for c in data for x in c['clos'])
    print(kind, 'chapters', len(data), 'CLOs', n_clo, 'indicators', n_ind)
