#!/usr/bin/env python3
"""Веб-версия книги для чтения в браузере (одна страница).

Читает book/model.json (его делает tools/build.py) и пишет:
  <out>       — самостоятельный HTML-файл, открывается в любом браузере
  [fragment]  — то же содержимое без <html>/<head>/<body> (для публикации как Artifact);
                по умолчанию <out без .html>.fragment.html

Запуск:  python3 tools/build_web.py book/model.json book/stirner-edinstvennyi.html [fragment.html]
"""
import html
import json
import re
import sys
from pathlib import Path

STYLE = r"""
<style>
/* Макет: одна колонка книжного набора ~66 знаков, тонкая шапка с прогрессом, оглавление выезжает слева */
:root {
  --paper: #fbfaf7;
  --ink: #1f1b16;
  --ink-soft: #5c5348;
  --brass: #86672f;
  --rule: #ddd5c6;
  --panel: #f2eee6;
  --veil: rgba(20, 17, 14, .38);
  --f-text: "Literata", "PT Serif", Georgia, "Times New Roman", serif;
  --f-display: "Cormorant Garamond", "Cormorant", Georgia, serif;
  --f-ui: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --fs: 1.125rem;
  --measure: 34em;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --paper: #171513; --ink: #e8dfcf; --ink-soft: #a89d8b; --brass: #c9a463;
    --rule: #3a342c; --panel: #211e1a; --veil: rgba(0, 0, 0, .55); color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --paper: #171513; --ink: #e8dfcf; --ink-soft: #a89d8b; --brass: #c9a463;
  --rule: #3a342c; --panel: #211e1a; --veil: rgba(0, 0, 0, .55); color-scheme: dark;
}
html { scroll-padding-top: calc(4rem + env(safe-area-inset-top, 0px)); }
body { background: var(--paper); color: var(--ink); font-family: var(--f-text); }
body::before { content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px); z-index: 10; background: var(--paper); }

.bar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; background: var(--paper);
  border-bottom: 1px solid var(--rule); font-family: var(--f-ui); font-size: .86rem; }
.bar-in { display: flex; align-items: center; gap: .5rem; min-height: 3rem;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.bar .where { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: var(--ink-soft); }
.bar .where b { color: var(--ink); font-weight: 500; }
.bar .pct { font-variant-numeric: tabular-nums; color: var(--ink-soft); min-width: 3.2em; text-align: right; }
.btn { font: inherit; color: var(--ink); background: transparent; border: 1px solid var(--rule); border-radius: 6px;
  padding: .32rem .62rem; cursor: pointer; line-height: 1.2; }
.btn:hover { border-color: var(--brass); color: var(--brass); }
.btn:focus-visible, a:focus-visible { outline: 2px solid var(--brass); outline-offset: 2px; }
.btn.icon { padding: .32rem .5rem; min-width: 2.1rem; }
.progress { height: 2px; background: transparent; }
.progress i { display: block; height: 100%; width: 0; background: var(--brass); }

.wrap { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.book { max-width: var(--measure); margin: 0 auto; font-size: var(--fs); line-height: 1.62; padding-block: 0 6rem; }
.book p { margin: 0; text-indent: 1.6em; text-align: justify; -webkit-hyphens: auto; hyphens: auto; }
.book p.coda { text-indent: 0; text-align: center; font-style: italic; margin: 1.8em 0; }

.title { text-align: center; padding-block: 4.5rem 3.5rem; border-bottom: 1px solid var(--rule); margin-bottom: 1rem; }
.title .author { font-family: var(--f-display); font-weight: 500; font-size: 1.15rem; letter-spacing: .3em; text-transform: uppercase; color: var(--brass); }
.title h1 { font-family: var(--f-display); font-weight: 600; font-size: clamp(2.6rem, 9vw, 4.2rem); line-height: 1.02; margin: 1.6rem 0 1.4rem; text-wrap: balance; }
.title h1 small { display: block; font-size: .5em; font-style: italic; font-weight: 400; color: var(--brass); margin: .25em 0; }
.title .meta { font-size: .92rem; color: var(--ink-soft); display: grid; gap: .25rem; }
.title .meta em { font-size: .88rem; }
.title .resume { margin-top: 1.8rem; display: flex; justify-content: center; }
.title .resume .btn { border-color: var(--brass); color: var(--brass); font-family: var(--f-ui); font-size: .9rem; padding: .5rem 1rem; }

.book h2, .book h3, .book h4, .book h5 { font-weight: 400; text-align: center; text-wrap: balance; line-height: 1.2; -webkit-hyphens: none; hyphens: none; }
.book h2 { font-family: var(--f-display); font-weight: 600; font-size: 2.05em; margin: 4.5rem 0 2rem; }
.book h3 { font-family: var(--f-display); font-weight: 600; font-size: 1.55em; margin: 3.5rem 0 1.4rem; }
.book h4 { font-size: 1.12em; font-style: italic; margin: 2.8rem 0 1.1rem; }
.book h5 { font-size: 1em; font-style: italic; color: var(--ink-soft); margin: 2.2rem 0 .9rem; }
.book h2 + p, .book h3 + p, .book h4 + p, .book h5 + p, .verse + p, .part + p { text-indent: 0; }
.book h2::after, .book h3::after { content: ""; display: block; width: 3rem; height: 1px; background: var(--brass); margin: 1.1rem auto 0; }
.part { text-align: center; margin: 6rem 0 2.5rem; padding-top: 3rem; border-top: 1px solid var(--rule); }
.part .label { font-family: var(--f-ui); font-size: .78rem; letter-spacing: .32em; text-transform: uppercase; color: var(--brass); }
.part h2 { margin: .8rem 0 0; font-size: 3em; }
.part h2::after { display: none; }

.verse { margin: 1.1em 0 1.1em 2.5em; font-style: italic; }
.verse p { text-indent: 0; text-align: left; }

a.nref { color: var(--brass); text-decoration: none; font-family: var(--f-ui); font-size: .68em; vertical-align: super;
  line-height: 0; padding: 0 .12em; font-variant-numeric: tabular-nums; }
a.nref:hover { text-decoration: underline; }
.notes { margin-top: 3rem; padding-top: .8rem; border-top: 1px solid var(--rule); font-size: .86em; line-height: 1.5; color: var(--ink-soft); }
.notes h6 { font-family: var(--f-ui); font-size: .72rem; letter-spacing: .2em; text-transform: uppercase; font-weight: 500; margin: 0 0 .6rem; color: var(--ink-soft); }
.notes ol { margin: 0; padding-left: 2.1em; display: grid; gap: .35rem; }
.notes li { padding-left: .2em; }
.notes li::marker { font-family: var(--f-ui); font-variant-numeric: tabular-nums; color: var(--brass); font-size: .9em; }
.notes a.back { font-family: var(--f-ui); text-decoration: none; color: var(--brass); margin-left: .3em; }
.notes li:target { color: var(--ink); }

.pop { position: absolute; z-index: 8; max-width: min(26rem, calc(100vw - 32px)); background: var(--panel); color: var(--ink);
  border: 1px solid var(--rule); border-radius: 8px; padding: .75rem .9rem; font-size: .92rem; line-height: 1.5;
  box-shadow: 0 10px 30px rgba(0,0,0,.18); }
.pop .n { font-family: var(--f-ui); color: var(--brass); margin-right: .35em; }

.drawer { position: fixed; z-index: 20; inset: 0 auto 0 0; width: min(23rem, 88vw); background: var(--panel);
  border-right: 1px solid var(--rule); transform: translateX(-102%); transition: transform .22s ease;
  display: flex; flex-direction: column; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px);
  padding-left: env(safe-area-inset-left, 0px); }
.drawer.open { transform: none; }
.drawer header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1rem .6rem 1.2rem; font-family: var(--f-ui); }
.drawer header b { font-weight: 500; letter-spacing: .14em; text-transform: uppercase; font-size: .78rem; color: var(--brass); }
.drawer .list { overflow-y: auto; padding: 0 .6rem 2rem; font-family: var(--f-text); font-size: .95rem; }
.drawer ol { list-style: none; margin: 0; padding: 0; }
.drawer ol ol { padding-left: 1rem; }
.drawer a { display: block; padding: .32rem .6rem; border-radius: 5px; color: var(--ink); text-decoration: none; line-height: 1.3; }
.drawer a:hover { background: var(--paper); }
.drawer a.cur { color: var(--brass); background: var(--paper); }
.drawer .lv0 > a { font-family: var(--f-ui); font-size: .76rem; letter-spacing: .16em; text-transform: uppercase; color: var(--brass); margin-top: .9rem; }
.drawer .lv3 > a, .drawer .lv4 > a { font-size: .9rem; color: var(--ink-soft); }
.veil { position: fixed; inset: 0; z-index: 19; background: var(--veil); }

.foot { max-width: var(--measure); margin: 0 auto; padding-block: 2rem 4rem; border-top: 1px solid var(--rule);
  font-family: var(--f-ui); font-size: .8rem; color: var(--ink-soft); display: grid; gap: .3rem; text-align: center; }
.foot a { color: var(--brass); }

@media (max-width: 520px) {
  :root { --fs: 1.04rem; }
  .book p { text-indent: 1.2em; }
  .bar .pct { display: none; }
  .verse { margin-left: 1.2em; }
}
@media (prefers-reduced-motion: reduce) { .drawer { transition: none; } html { scroll-behavior: auto; } }
</style>
"""

SCRIPT = r"""
<script>
(function () {
  var KEY = "stirner-reader-v1";
  var store = {};
  try { store = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { store = {}; }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(store)); } catch (e) {} }

  var root = document.documentElement;
  var sizes = [0.94, 1.0, 1.06, 1.125, 1.2, 1.3, 1.42];
  var base = window.matchMedia("(max-width: 520px)").matches ? 2 : 3;
  var si = typeof store.size === "number" ? store.size : base;
  function applySize() { root.style.setProperty("--fs", sizes[si] + "rem"); }
  if (typeof store.size === "number") applySize();

  var paras = Array.prototype.slice.call(document.querySelectorAll(".book p, .book .verse"));
  var heads = Array.prototype.slice.call(document.querySelectorAll(".book [data-toc]"));
  var whereEl = document.getElementById("where");
  var pctEl = document.getElementById("pct");
  var barEl = document.getElementById("progress-fill");
  var tocLinks = {};
  Array.prototype.forEach.call(document.querySelectorAll("#toc a"), function (a) { tocLinks[a.getAttribute("href").slice(1)] = a; });

  function topOf(el) { return el.getBoundingClientRect().top + window.scrollY; }
  var offsets = [];
  function measure() { offsets = heads.map(topOf); }

  var current = null;
  function update() {
    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    var f = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
    barEl.style.width = (f * 100).toFixed(2) + "%";
    pctEl.textContent = Math.round(f * 100) + "%";
    var y = window.scrollY + 90, idx = -1, lo = 0, hi = offsets.length - 1;
    while (lo <= hi) { var mid = (lo + hi) >> 1; if (offsets[mid] <= y) { idx = mid; lo = mid + 1; } else hi = mid - 1; }
    var h = idx >= 0 ? heads[idx] : null;
    if (h !== current) {
      current = h;
      whereEl.innerHTML = h ? h.getAttribute("data-trail") : "<b>Единственный и его собственность</b>";
      Object.keys(tocLinks).forEach(function (k) { tocLinks[k].classList.remove("cur"); });
      if (h && tocLinks[h.id]) tocLinks[h.id].classList.add("cur");
    }
  }

  // где остановился читатель: индекс первого абзаца в окне
  function firstVisible() {
    var lo = 0, hi = paras.length - 1, ans = 0, y = 70;
    while (lo <= hi) { var mid = (lo + hi) >> 1; if (paras[mid].getBoundingClientRect().bottom < y) lo = mid + 1; else { ans = mid; hi = mid - 1; } }
    return ans;
  }
  var saveTimer = null;
  function remember() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      if (window.scrollY < 300) return;
      var i = firstVisible();
      store.para = i;
      store.label = current ? current.getAttribute("data-label") : "";
      save();
    }, 800);
  }

  var ticking = false;
  window.addEventListener("scroll", function () {
    if (!ticking) { ticking = true; requestAnimationFrame(function () { ticking = false; update(); }); }
    remember();
  }, { passive: true });
  window.addEventListener("resize", function () { measure(); update(); });

  function keepPlace(fn) {
    var i = firstVisible(), el = paras[i], before = el.getBoundingClientRect().top;
    fn(); measure();
    window.scrollBy(0, el.getBoundingClientRect().top - before);
    update();
  }
  document.getElementById("smaller").addEventListener("click", function () {
    if (si > 0) { si--; store.size = si; save(); keepPlace(applySize); }
  });
  document.getElementById("bigger").addEventListener("click", function () {
    if (si < sizes.length - 1) { si++; store.size = si; save(); keepPlace(applySize); }
  });

  // продолжить чтение
  var resume = document.getElementById("resume");
  if (typeof store.para === "number" && store.para > 2 && paras[store.para] && !location.hash) {
    resume.hidden = false;
    var lab = resume.querySelector("span");
    lab.textContent = store.label ? "Продолжить: " + store.label : "Продолжить чтение";
    resume.querySelector("button").addEventListener("click", function () {
      paras[store.para].scrollIntoView({ block: "start" });
      update();
    });
  }

  // оглавление
  var drawer = document.getElementById("toc"), veil = document.getElementById("veil"), opener = document.getElementById("open-toc");
  drawer.inert = true;
  function openToc() {
    drawer.inert = false;
    drawer.classList.add("open"); veil.hidden = false; drawer.setAttribute("aria-hidden", "false");
    var c = drawer.querySelector("a.cur") || drawer.querySelector("a");
    if (c) { c.scrollIntoView({ block: "center" }); c.focus({ preventScroll: true }); }
  }
  function closeToc() { drawer.inert = true; drawer.classList.remove("open"); veil.hidden = true; drawer.setAttribute("aria-hidden", "true"); }
  opener.addEventListener("click", openToc);
  document.getElementById("close-toc").addEventListener("click", function () { closeToc(); opener.focus(); });
  veil.addEventListener("click", closeToc);
  drawer.addEventListener("click", function (e) { if (e.target.closest("a")) closeToc(); });

  // сноски: всплывающее окно
  var pop = null;
  function closePop() { if (pop) { pop.remove(); pop = null; } }
  document.addEventListener("click", function (e) {
    var a = e.target.closest("a.nref");
    if (!a) { if (pop && !e.target.closest(".pop")) closePop(); return; }
    e.preventDefault();
    var id = a.getAttribute("href").slice(1), li = document.getElementById(id);
    if (!li) return;
    closePop();
    pop = document.createElement("div");
    pop.className = "pop"; pop.setAttribute("role", "note");
    var n = document.createElement("span"); n.className = "n"; n.textContent = a.textContent + ".";
    pop.appendChild(n);
    var body = document.createElement("span"); body.innerHTML = li.querySelector(".nt").innerHTML;
    pop.appendChild(body);
    document.body.appendChild(pop);
    var r = a.getBoundingClientRect(), w = pop.offsetWidth;
    var left = Math.min(Math.max(16, r.left + window.scrollX - w / 2), window.scrollX + document.documentElement.clientWidth - w - 16);
    var top = r.bottom + window.scrollY + 8;
    if (r.bottom + pop.offsetHeight + 16 > window.innerHeight) top = r.top + window.scrollY - pop.offsetHeight - 8;
    pop.style.left = left + "px"; pop.style.top = top + "px";
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { closePop(); if (drawer.classList.contains("open")) { closeToc(); opener.focus(); } }
  });

  measure(); update();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { measure(); update(); });
  window.addEventListener("load", function () { measure(); update(); });
})();
</script>
"""


def esc(s):
    return html.escape(s, quote=False)


def attr(s):
    return html.escape(s, quote=True)


def note_ref(n):
    return f'<a class="nref" href="#n{n}" id="r{n}" aria-label="Примечание {n}">{n}</a>'


def render(model):
    front, blocks, notes = model["front"], model["blocks"], model["notes"]
    out, toc = [], []
    chapter_notes = []
    open_chapter = False
    trail = {}  # уровень -> название, для строки «где я» в шапке

    def close_chapter():
        nonlocal chapter_notes, open_chapter
        if not open_chapter:
            return
        if chapter_notes:
            out.append('<aside class="notes"><h6>Примечания</h6><ol>')
            for n in chapter_notes:
                out.append(f'<li id="n{n}" value="{n}"><span class="nt">{notes[n - 1]}</span>'
                           f'<a class="back" href="#r{n}" aria-label="Назад к тексту">↩</a></li>')
            out.append("</ol></aside>")
        out.append("</section>")
        chapter_notes, open_chapter = [], False

    def open_ch():
        nonlocal open_chapter
        out.append('<section class="chapter">')
        open_chapter = True

    for b in blocks:
        t = b["t"]
        if t == "part":
            close_chapter()
            open_ch()
            label = f'{b["label"]}. {b["title"]}'
            trail.clear()
            trail[0] = label
            tr = f'<b>{esc(b["label"])}. {esc(b["title"])}</b>'
            out.append(f'<div class="part"><div class="label">{esc(b["label"])}</div>'
                       f'<h2 id="{b["id"]}" data-toc data-label="{attr(label)}" data-trail="{attr(tr)}">{esc(b["title"])}</h2></div>')
            toc.append((0, label, b["id"]))
        elif t == "h":
            lvl = b["lvl"]
            text = html.unescape(b["text"])
            if lvl == 1:
                close_chapter()
                open_ch()
            for k in [k for k in trail if k >= lvl]:
                del trail[k]
            trail[lvl] = text
            parts = [trail[k] for k in sorted(trail)]
            tr = " · ".join(esc(p) for p in parts[:-1])
            tr = (tr + " · " if tr else "") + f"<b>{esc(parts[-1])}</b>"
            tag = f"h{lvl + 1}"
            out.append(f'<{tag} id="{b["id"]}" data-toc data-label="{attr(text)}" data-trail="{attr(tr)}">{b["text"]}</{tag}>')
            toc.append((lvl, text, b["id"]))
        elif t == "verse":
            out.append('<div class="verse">' + "".join(f"<p>{l}</p>" for l in b["lines"]) + "</div>")
        else:
            h = b["html"]
            for m in re.finditer(r"\{\{NOTE:(\d+)\}\}", h):
                chapter_notes.append(int(m.group(1)))
            h = re.sub(r"\{\{NOTE:(\d+)\}\}", lambda m: note_ref(int(m.group(1))), h)
            cls = ' class="coda"' if b.get("cls") == "coda" else ""
            out.append(f"<p{cls}>{h}</p>")
    close_chapter()

    # оглавление
    def toc_html():
        rootn = {"children": []}
        stack = [(-1, rootn)]
        for lvl, txt, hid in toc:
            node = {"lvl": lvl, "txt": txt, "id": hid, "children": []}
            while stack[-1][0] >= lvl:
                stack.pop()
            stack[-1][1]["children"].append(node)
            stack.append((lvl, node))

        def r(nodes):
            s = ["<ol>"]
            for n in nodes:
                s.append(f'<li class="lv{n["lvl"]}"><a href="#{n["id"]}">{esc(n["txt"])}</a>')
                if n["children"]:
                    s.append(r(n["children"]))
                s.append("</li>")
            s.append("</ol>")
            return "".join(s)

        return r(rootn["children"])

    title = front["title"]
    head = (
        "<title>Единственный и его собственность</title>\n"
        '<meta name="claude:viewport-fit-sides" content="cover">\n'
        '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
        '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,400'
        '&family=IBM+Plex+Sans:wght@400;500&family=Literata:ital,opsz,wght@0,7..72,400;0,7..72,500;1,7..72,400&display=swap">\n'
    )
    bar = (
        '<div class="bar" role="banner"><div class="bar-in">'
        '<button class="btn" id="open-toc" type="button" aria-controls="toc">Оглавление</button>'
        '<div class="where" id="where" aria-live="off"><b>Единственный и его собственность</b></div>'
        '<span class="pct" id="pct">0%</span>'
        '<button class="btn icon" id="smaller" type="button" aria-label="Мельче шрифт">A−</button>'
        '<button class="btn icon" id="bigger" type="button" aria-label="Крупнее шрифт">A+</button>'
        '</div><div class="progress"><i id="progress-fill"></i></div></div>'
    )
    drawer = (
        '<nav class="drawer" id="toc" aria-label="Оглавление" aria-hidden="true">'
        '<header><b>Оглавление</b><button class="btn icon" id="close-toc" type="button" aria-label="Закрыть оглавление">✕</button></header>'
        f'<div class="list">{toc_html()}</div></nav><div class="veil" id="veil" hidden></div>'
    )
    title_block = (
        '<header class="title">'
        f'<div class="author">{esc(front["author"])}</div>'
        '<h1>Единственный<small>и его</small>собственность</h1>'
        '<div class="meta">'
        f'<span>{esc(front["translator"])}</span>'
        + "".join(f"<em>{esc(x)}</em>" for x in front["edition"])
        + "</div>"
        '<div class="resume" id="resume" hidden><button class="btn" type="button"><span>Продолжить чтение</span></button></div>'
        "</header>"
    )
    foot = (
        '<footer class="foot">'
        f'<span>{esc(front["author"])}. {esc(title)}. {esc(front["translator"])}.</span>'
        '<span>Текст: Lib.ru/Классика, az.lib.ru. Типографика, разбивка на главы и сноски восстановлены.</span>'
        "</footer>"
    )
    body = (
        head + STYLE + bar + drawer
        + '<div class="wrap"><main class="book" lang="ru">' + title_block + "".join(out) + "</main>"
        + foot + "</div>" + SCRIPT
    )
    return body


SKELETON = """<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
{body}
</body>
</html>
"""


def main():
    model = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    frag = render(model)
    frag_path = Path(sys.argv[3]) if len(sys.argv) > 3 else out.with_suffix(".fragment.html")
    frag_path.write_text(frag, encoding="utf-8")
    out.write_text(SKELETON.replace("{body}", frag), encoding="utf-8")
    print("HTML:", out, out.stat().st_size, "байт")


if __name__ == "__main__":
    main()
