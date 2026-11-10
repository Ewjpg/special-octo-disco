#!/usr/bin/env python3
"""Сборка книги М. Штирнера «Единственный и его собственность».

Исходник — сплошной текст со страницы Lib.ru/Классика (source/lib.ru-original.txt).
Скрипт восстанавливает структуру (части, главы, разделы), правит типографику
(тире, «ёлочки», многоточия), исправляет явные ошибки распознавания, переносит
примечания из [квадратных скобок] в сноски и собирает:

  book/stirner-edinstvennyi.epub   — электронная книга (EPUB 3, совместима с EPUB 2)
  book/model.json                  — размеченный текст для веб-версии

Запуск:  python3 tools/build.py source/lib.ru-original.txt book [book/cover.png]
"""
import html
import json
import re
import sys
import uuid
import zipfile
from pathlib import Path

# --- Исправления явных ошибок распознавания и кодировки в исходнике -------------
# (что было, на что заменить, сколько раз должно встретиться)
FIXES = [
    ("кtre suprкme", "Être suprême", 3),
    ("an und fЭr sich", "an und für sich", 1),
    ("an und fur sich). He я", "an und für sich). Не я", 1),
    ("тe6e", "тебе", 1),
    ("осо6ь", "особь", 1),
    ("нечто woe,", "нечто мое,", 1),
    ("но это w эгоистическое", "но это не эгоистическое", 1),
    ("повязок c ошейников", "повязок и ошейников", 1),
    ("вошедших g обычай", "вошедших в обычай", 1),
    ("поддерживать g себе", "поддерживать в себе", 1),
    ("образом v широком", "образом в широком", 1),
    ("ведущим R победе", "ведущим к победе", 1),
    ("для него s том", "для него в том", 1),
    ("(Sail)", "(Saal)", 1),
    ("La prorpiete c'est le vol", "La propriété c'est le vol", 1),
    ("Creation de l'ordre", "Création de l'ordre", 1),
    ("Une societe, pour ainsi dire acephale", "Une société, pour ainsi dire acéphale", 1),
    ("proprietaire", "propriétaire", 2),
    ("egalite", "égalité", 2),
    ("в verite", "в vérité", 1),
    ("qloriam", "gloriam", 1),
    ("finis bouorum", "finis bonorum", 1),
    ('как "Дога"', 'как "Бога"', 1),
    ('братство. Н" всякий', 'братство. На всякий', 1),
    ('Шиллера: " Уже', 'Шиллера: "Уже', 1),
    ("носом дл; обоняния", "носом для обоняния", 1),
    ('единственный пусть спасения', 'единственный путь спасения', 1),
    ('ко " всем "', 'ко "всем"', 1),
    ('сильны, " что', 'сильны, что', 1),
    ('о " свободной науке "', 'о "свободной науке"', 1),
    ('наш"ел', 'нашел', 1),
    ('не признаю " милостыни "', 'не признаю "милостыни"', 1),
    ("вышесказанное, Устранив", "вышесказанное, устранив", 1),
    ('в себя, и" ты', 'в себя, и ты', 1),
    ("\xad", "", 3),
    (" |", " ", 2),
]

# Заголовки исходника и их уровень вложенности (1 — глава, 4 — подраздел)
HEADINGS = {
    "Ничто -- вот на чем я построил свое дело": 1,
    "1. Человеческая жизнь": 1,
    "2. Люди древнего и нового миров": 1,
    "Древние": 2, "Новые": 2, "Свободные": 2,
    "Дух": 3, "Одержимые": 3, "Иерархия": 3,
    "Призрак": 4, "Помешательство": 4,
    "Политический либерализм": 3, "Социальный либерализм": 3,
    "Гуманитарный либерализм": 3, "Примечание": 3,
    "1. Принадлежность себе (своеобразие)": 1,
    "2. Собственник": 1,
    "Моя мощь": 2, "Мое общение": 2, "Мое самонаслаждение": 2,
    "3. Единственный": 1,
}

VERSE_START = "Я пою, как птица,"
VERSE_LEN = 4

NBSP = " "
NOTE_OPEN, NOTE_CLOSE = "", ""


def apply_fixes(text):
    for old, new, n in FIXES:
        found = text.count(old)
        if found != n:
            raise SystemExit(f"Исправление {old!r}: ожидалось {n}, найдено {found}")
        text = text.replace(old, new)
    text = re.sub(r"\bNo (?=\d)", "№" + NBSP, text)
    return text


OPEN_CTX = set(" \t" + NBSP + "([{—–-/«„“" + NOTE_CLOSE)
CLOSE_CTX = set(" \t" + NBSP + ".,;:!?)]}…—–-»“" + NOTE_OPEN)


def _quotes(s, nested):
    """Прямые кавычки -> «ёлочки» (во вложенном режиме внутренние -> „лапки“)."""
    out, depth, bad = [], 0, False
    for i, ch in enumerate(s):
        if ch != '"':
            out.append(ch)
            continue
        prev = out[-1] if out else " "
        nxt = s[i + 1] if i + 1 < len(s) else " "
        can_open = prev in OPEN_CTX
        can_close = nxt in CLOSE_CTX or nxt == '"'
        if can_open and not can_close:
            opening = True
        elif can_close and not can_open:
            opening = False
        else:
            opening = depth == 0
        if not nested:
            out.append("«" if opening else "»")
            depth = 1 if opening else 0
            continue
        if opening:
            out.append("«" if depth == 0 else "„")
            depth += 1
        elif depth == 0:
            bad = True
            out.append("»")
        else:
            depth -= 1
            out.append("»" if depth == 0 else "\u201c")
    return "".join(out), bad or depth != 0


def russian_quotes(s, problems, where):
    """Если кавычки в абзаце сбалансированы — честная вложенность «„“».
    Иначе (цитата на несколько абзацев, огрехи исходника) — простые «ёлочки»
    по контексту, чтобы не перекосить весь абзац."""
    res, bad = _quotes(s, nested=True)
    if bad:
        problems.append(("кавычки не сбалансированы, простой режим", where, s[:70]))
        res, _ = _quotes(s, nested=False)
    return res


def typo(s, problems, where):
    s = s.replace("...", "…")
    s = re.sub(r"(?<=\S) -{1,2} ", NBSP + "— ", s)
    s = re.sub(r"^-{1,2} ", "— ", s)
    s = s.replace("--", "—")
    s = re.sub(r" +", " ", s).strip()
    s = russian_quotes(s, problems, where)
    # неразрывные пробелы в сокращениях и инициалах
    s = re.sub(r"\b(т\.) (д\.|е\.|п\.)", r"\1" + NBSP + r"\2", s)
    s = re.sub(r"\b(с\.) (?=\d)", r"\1" + NBSP, s)
    s = re.sub(r"\b([А-ЯЁA-Z]\.) (?=[А-ЯЁA-Z])", r"\1" + NBSP, s)
    return s


def esc(s):
    return html.escape(s, quote=False)


def parse(text):
    problems = []
    lines = text.split("\n")
    front = {
        "author": lines[0].strip(),
        "title": lines[2].strip(),
        "translator": lines[4].strip(),
        "edition": [lines[6].strip(), lines[7].strip()],
    }
    blocks, notes = [], []
    i = 8
    hid = 0

    def para_html(raw, where):
        local = []

        def grab(m):
            local.append(m.group(1).strip())
            return NOTE_OPEN + str(len(local) - 1) + NOTE_CLOSE

        body = re.sub(r"\s*\[([^\[\]]+)\]", grab, raw)
        body = esc(typo(body, problems, where))
        refs = []
        for k, note in enumerate(local):
            notes.append(esc(typo(note, problems, where + " (сноска)")))
            refs.append(len(notes))  # номер сноски, с 1
        body = re.sub(NOTE_OPEN + r"(\d+)" + NOTE_CLOSE,
                      lambda m: "{{NOTE:%d}}" % refs[int(m.group(1))], body)
        return body

    while i < len(lines):
        raw = lines[i]
        line = raw.strip()
        if not line:
            i += 1
            continue
        where = f"строка {i + 1}"
        if raw.startswith("   "):
            if line == VERSE_START:
                verse = [esc(typo(lines[i + k].strip(), problems, where)) for k in range(VERSE_LEN)]
                blocks.append({"t": "verse", "lines": verse})
                i += VERSE_LEN
                continue
            blocks.append({"t": "p", "html": para_html(line, where)})
        elif line.startswith("Часть "):
            j = i + 1
            while not lines[j].strip():
                j += 1
            hid += 1
            blocks.append({"t": "part", "label": line.rstrip("."),
                           "title": lines[j].strip(), "id": f"h{hid}"})
            i = j
        elif line in HEADINGS:
            hid += 1
            blocks.append({"t": "h", "lvl": HEADINGS[line],
                           "text": esc(typo(line, problems, where)), "id": f"h{hid}"})
        else:
            # выделенные строки без отступа: концовки вступления и книги
            blocks.append({"t": "p", "html": para_html(line, where), "cls": "coda"})
        i += 1
    used = {b["text"] for b in blocks if b["t"] == "h"}
    if len(used) != len(HEADINGS):
        raise SystemExit("Найдены не все заголовки")
    return front, blocks, notes, problems


# --- EPUB ------------------------------------------------------------------------

CSS = """\
@charset "utf-8";
html { -webkit-hyphens: auto; hyphens: auto; }
body { margin: 0 4%; font-family: serif; line-height: 1.45; }
p { margin: 0; text-indent: 1.5em; text-align: justify; orphans: 2; widows: 2; }
h1, h2, h3, h4 { font-weight: normal; text-align: center; -webkit-hyphens: none; hyphens: none;
  page-break-after: avoid; break-after: avoid; line-height: 1.25; }
h1 { font-size: 1.55em; margin: 2.5em 0 1.6em; }
h2 { font-size: 1.3em; margin: 2.2em 0 1.2em; letter-spacing: .02em; }
h3 { font-size: 1.12em; margin: 2em 0 1em; font-style: italic; }
h4 { font-size: 1em; margin: 1.6em 0 .8em; font-style: italic; }
h1 + p, h2 + p, h3 + p, h4 + p, .verse + p { text-indent: 0; }
.part { text-align: center; margin-top: 30%; }
.part .label { font-size: .95em; letter-spacing: .25em; text-transform: uppercase; margin: 0 0 .8em; text-indent: 0; text-align: center; }
.part h1 { font-size: 2.2em; margin: 0 0 2em; }
.coda { text-indent: 0; text-align: center; font-style: italic; margin: 1.6em 0; }
.verse { margin: 1em 0 1em 3em; font-style: italic; }
.verse p { text-indent: 0; text-align: left; }
a.nref { text-decoration: none; }
sup { font-size: .7em; line-height: 0; vertical-align: super; }
.notes { margin-top: 2.5em; border-top: 1px solid #999; padding-top: .6em; font-size: .85em; }
.notes h4 { margin: .4em 0 .6em; text-align: left; font-style: normal; font-size: 1em; }
aside.fn p { text-indent: 0; text-align: left; margin: 0 0 .4em; }
aside.fn a { text-decoration: none; }
.title { text-align: center; margin-top: 18%; }
.title p { text-indent: 0; text-align: center; }
.title .author { font-size: 1.25em; letter-spacing: .12em; margin-bottom: 2.5em; }
.title h1 { font-size: 2.1em; margin: 0 0 2.2em; }
.title .tr { margin-bottom: 4em; }
.title .ed { font-size: .85em; font-style: italic; }
.title .src { font-size: .75em; margin-top: 3em; }
.cover { margin: 0; padding: 0; text-align: center; }
.cover img { height: 100%; max-width: 100%; }
nav ol { list-style: none; padding-left: 1.2em; }
nav > ol { padding-left: 0; }
nav li { margin: .3em 0; }
nav a { text-decoration: none; }
"""

XHTML_HEAD = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ru" lang="ru">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body{bodyattr}>
"""
XHTML_TAIL = "</body>\n</html>\n"

SPLIT_LIMIT = 110_000   # символов на файл: крупные главы режутся по абзацам
SMALL_FILE = 20_000     # раздел 2-го уровня не выносится в отдельный файл после короткого вступления


def heading_plain(b):
    if b["t"] == "part":
        return f'{b["label"]}. {b["title"]}'
    return html.unescape(b["text"])


def split_files(blocks):
    files, cur, size = [], [], 0

    def flush():
        nonlocal cur, size
        if cur:
            files.append(cur)
        cur, size = [], 0

    for b in blocks:
        new = False
        if b["t"] == "part" or (b["t"] == "h" and b["lvl"] == 1):
            new = True
        elif b["t"] == "h" and b["lvl"] == 2 and size > SMALL_FILE:
            new = True
        elif b["t"] == "p" and size > SPLIT_LIMIT:
            new = True
        if new:
            flush()
        cur.append(b)
        size += len(b.get("html", b.get("text", ""))) + sum(len(x) for x in b.get("lines", []))
    flush()
    return files


def render_note_refs(s):
    return re.sub(r"\{\{NOTE:(\d+)\}\}",
                  lambda m: f'<a class="nref" epub:type="noteref" href="#fn{m.group(1)}" id="r{m.group(1)}"><sup>{m.group(1)}</sup></a>',
                  s)


def render_block(b):
    t = b["t"]
    if t == "part":
        return (f'<section class="part" epub:type="part">\n<p class="label">{esc(b["label"])}</p>\n'
                f'<h1 id="{b["id"]}">{esc(b["title"])}</h1>\n</section>\n')
    if t == "h":
        tag = f'h{b["lvl"]}'
        return f'<{tag} id="{b["id"]}">{b["text"]}</{tag}>\n'
    if t == "verse":
        return '<div class="verse">\n' + "".join(f"<p>{l}</p>\n" for l in b["lines"]) + "</div>\n"
    cls = b.get("cls")
    attr = f' class="{cls}"' if cls else ""
    return f"<p{attr}>{render_note_refs(b['html'])}</p>\n"


def build_epub(front, blocks, notes, outdir, cover=None):
    outdir = Path(outdir)
    files = split_files(blocks)
    book_id = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "stirner-edinstvennyi-gimmelfarb-1907"))
    title = front["title"]
    author = front["author"]
    items = []  # (filename, content, title)

    # титульная страница
    t_html = (XHTML_HEAD.format(title=esc(title), bodyattr="")
              + '<section class="title" epub:type="titlepage">\n'
              + f'<p class="author">{esc(author)}</p>\n<h1>{esc(title)}</h1>\n'
              + f'<p class="tr">{esc(front["translator"])}</p>\n'
              + "".join(f'<p class="ed">{esc(x)}</p>\n' for x in front["edition"])
              + '<p class="src">Текст: Lib.ru/Классика (az.lib.ru)</p>\n</section>\n' + XHTML_TAIL)
    items.append(("title.xhtml", t_html, "Титул"))

    toc = []  # (level, title, href)
    for n, fb in enumerate(files, 1):
        name = f"part{n:02d}.xhtml"
        first_h = next((b for b in fb if b["t"] in ("part", "h")), None)
        ftitle = heading_plain(first_h) if first_h else title
        body = []
        fnotes = []
        for b in fb:
            if b["t"] == "part":
                toc.append((0, heading_plain(b), f"text/{name}#{b['id']}"))
            elif b["t"] == "h":
                toc.append((b["lvl"], heading_plain(b), f"text/{name}#{b['id']}"))
            body.append(render_block(b))
            for m in re.finditer(r"\{\{NOTE:(\d+)\}\}", b.get("html", "")):
                fnotes.append(int(m.group(1)))
        if fnotes:
            body.append('<section class="notes" epub:type="footnotes">\n<h4>Примечания</h4>\n')
            for k in fnotes:
                body.append(f'<aside class="fn" epub:type="footnote" id="fn{k}"><p>'
                            f'<a href="#r{k}">{k}.</a> {notes[k - 1]}</p></aside>\n')
            body.append("</section>\n")
        x = XHTML_HEAD.format(title=esc(ftitle), bodyattr="") + "".join(body) + XHTML_TAIL
        items.append((name, x, ftitle))

    # оглавление EPUB 3 (nav) — вложенный список
    nav_html = render_nav(toc)
    nav = (XHTML_HEAD.format(title="Оглавление", bodyattr="")
           + '<nav epub:type="toc" id="toc">\n<h2>Оглавление</h2>\n' + nav_html + "</nav>\n"
           + '<nav epub:type="landmarks" hidden="">\n<ol>\n'
           + '<li><a epub:type="titlepage" href="title.xhtml">Титул</a></li>\n'
           + '<li><a epub:type="toc" href="nav.xhtml">Оглавление</a></li>\n'
           + f'<li><a epub:type="bodymatter" href="{items[1][0]}">Начало книги</a></li>\n'
           + "</ol>\n</nav>\n" + XHTML_TAIL)

    ncx = render_ncx(toc, book_id, title)

    manifest, spine = [], []
    if cover:
        manifest.append('<item id="cover-img" href="images/cover.png" media-type="image/png" properties="cover-image"/>')
        manifest.append('<item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml" properties="svg"/>')
        spine.append('<itemref idref="cover" linear="yes"/>')
    manifest.append('<item id="nav" href="text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')
    manifest.append('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')
    manifest.append('<item id="css" href="text/style.css" media-type="text/css"/>')
    for k, (name, _, _) in enumerate(items):
        iid = name.split(".")[0]
        manifest.append(f'<item id="{iid}" href="text/{name}" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="{iid}"/>')
        if k == 0:
            spine.append('<itemref idref="nav"/>')

    opf = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="ru">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
<dc:identifier id="bookid">{book_id}</dc:identifier>
<dc:title>{esc(title)}</dc:title>
<dc:creator id="author">{esc(author)}</dc:creator>
<meta refines="#author" property="role" scheme="marc:relators">aut</meta>
<meta refines="#author" property="file-as">Штирнер, Макс</meta>
<dc:contributor id="tr1">Б. В. Гиммельфарб</dc:contributor>
<meta refines="#tr1" property="role" scheme="marc:relators">trl</meta>
<dc:contributor id="tr2">М. Л. Гохшиллер</dc:contributor>
<meta refines="#tr2" property="role" scheme="marc:relators">trl</meta>
<dc:language>ru</dc:language>
<dc:date>1845</dc:date>
<dc:subject>Философия</dc:subject>
<dc:source>http://az.lib.ru/s/shtirner_m/text_1845_der_einzige_und_sein_eigenthum.shtml</dc:source>
<dc:description>Der Einzige und sein Eigenthum (Leipzig, 1845). Перевод Б. В. Гиммельфарба и М. Л. Гохшиллера.</dc:description>
<meta property="dcterms:modified">2026-11-09T00:00:00Z</meta>
{('<meta name="cover" content="cover-img"/>' if cover else '')}
</metadata>
<manifest>
{chr(10).join(manifest)}
</manifest>
<spine toc="ncx">
{chr(10).join(spine)}
</spine>
<guide>
<reference type="title-page" title="Титул" href="text/title.xhtml"/>
<reference type="toc" title="Оглавление" href="text/nav.xhtml"/>
<reference type="text" title="Начало книги" href="text/{items[1][0]}"/>
</guide>
</package>
"""
    container = """<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""
    out = outdir / "stirner-edinstvennyi.epub"
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zc = dict(compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        z.writestr("META-INF/container.xml", container, **zc)
        z.writestr("OEBPS/content.opf", opf, **zc)
        z.writestr("OEBPS/toc.ncx", ncx, **zc)
        z.writestr("OEBPS/text/style.css", CSS, **zc)
        z.writestr("OEBPS/text/nav.xhtml", nav, **zc)
        if cover:
            z.write(cover, "OEBPS/images/cover.png", compress_type=zipfile.ZIP_STORED)
            cov = ("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ru" lang="ru">
<head><meta charset="utf-8"/><title>Обложка</title>
<style>html,body{margin:0;padding:0;height:100%;} svg{display:block;width:100%;height:100%;}</style></head>
<body epub:type="cover">
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" viewBox="0 0 1600 2560" preserveAspectRatio="xMidYMid meet">
<image width="1600" height="2560" xlink:href="../images/cover.png"/>
</svg>
</body>
</html>
""")
            z.writestr("OEBPS/text/cover.xhtml", cov, **zc)
        for name, content, _ in items:
            z.writestr(f"OEBPS/text/{name}", content, **zc)
    return out, files, toc


def render_nav(toc):
    root = {"children": []}
    stack = [(-1, root)]
    for lvl, txt, href in toc:
        node = {"txt": txt, "href": href.replace("text/", ""), "children": []}
        while stack[-1][0] >= lvl:
            stack.pop()
        stack[-1][1]["children"].append(node)
        stack.append((lvl, node))

    def render(nodes):
        parts = ["<ol>\n"]
        for n in nodes:
            parts.append(f'<li><a href="{n["href"]}">{esc(n["txt"])}</a>')
            if n["children"]:
                parts.append("\n" + render(n["children"]))
            parts.append("</li>\n")
        parts.append("</ol>\n")
        return "".join(parts)

    return render(root["children"])


def render_ncx(toc, book_id, title):
    out, levels, n = [], [], 0
    for lvl, txt, href in toc:
        while levels and levels[-1] >= lvl:
            out.append("</navPoint>\n")
            levels.pop()
        n += 1
        out.append(f'<navPoint id="np{n}" playOrder="{n}"><navLabel><text>{esc(txt)}</text></navLabel>'
                   f'<content src="{href}"/>\n')
        levels.append(lvl)
    out.extend("</navPoint>\n" for _ in levels)
    depth = len({l for l, _, _ in toc})
    return f"""<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="ru">
<head>
<meta name="dtb:uid" content="{book_id}"/>
<meta name="dtb:depth" content="{depth}"/>
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>{esc(title)}</text></docTitle>
<navMap>
{''.join(out)}</navMap>
</ncx>
"""


def main():
    src, outdir = sys.argv[1], sys.argv[2]
    cover = sys.argv[3] if len(sys.argv) > 3 and Path(sys.argv[3]).exists() else None
    text = apply_fixes(Path(src).read_text(encoding="utf-8"))
    front, blocks, notes, problems = parse(text)
    for p in problems:
        print("ВНИМАНИЕ:", *p, sep=" | ")
    Path(outdir).mkdir(parents=True, exist_ok=True)
    out, files, toc = build_epub(front, blocks, notes, outdir, cover)
    model = {"front": front, "blocks": blocks, "notes": notes}
    (Path(outdir) / "model.json").write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")
    nparas = sum(1 for b in blocks if b["t"] == "p")
    print(f"Абзацев: {nparas}, заголовков: {len(toc)}, сносок: {len(notes)}, файлов: {len(files)}")
    print("EPUB:", out, out.stat().st_size, "байт")


if __name__ == "__main__":
    main()
