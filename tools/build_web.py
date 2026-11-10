#!/usr/bin/env python3
"""Веб-версия книги для чтения в браузере.

Два режима: по страницам (перелистывание, на широком экране — разворот) и лентой.
Закладки и место чтения: в аккаунте Claude, если страница открыта как Artifact
(синхронизируются между устройствами), иначе — в браузере.

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

SMALL_CHUNK = 20_000  # раздел 2-го уровня начинает новый фрагмент, только если текущий уже не короткий

STYLE = r"""
<style>
/* Макет: книжная колонка ~66 знаков; по страницам — колонки CSS со сдвигом, на широком экране разворот из двух страниц */
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
  --col-w: 34em;
  --gap: 48px;
  --spread-w: 34em;
  --page-h: 600px;
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

/* шапка */
.bar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; background: var(--paper);
  border-bottom: 1px solid var(--rule); font-family: var(--f-ui); font-size: .86rem; }
.bar-in { display: flex; align-items: center; gap: .45rem; min-height: 3rem;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.bar .where { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: var(--ink-soft); }
.bar .where b { color: var(--ink); font-weight: 500; }
.bar .pct { font-variant-numeric: tabular-nums; color: var(--ink-soft); min-width: 3.2em; text-align: right; }
.paged .bar .pct { display: none; }
.btn { font: inherit; color: var(--ink); background: transparent; border: 1px solid var(--rule); border-radius: 6px;
  padding: .32rem .62rem; cursor: pointer; line-height: 1.2; }
.btn:hover { border-color: var(--brass); color: var(--brass); }
.btn:focus-visible, a:focus-visible, input:focus-visible { outline: 2px solid var(--brass); outline-offset: 2px; }
.btn.icon { padding: .32rem .45rem; min-width: 2.1rem; display: inline-flex; align-items: center; justify-content: center; }
.btn svg { width: 1.05rem; height: 1.05rem; display: block; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linejoin: round; }
.btn.on { color: var(--brass); border-color: var(--brass); }
.btn.on svg { fill: currentColor; }
.btn[aria-pressed="true"] { color: var(--brass); border-color: var(--brass); }
.progress { height: 2px; }
.progress i { display: block; height: 100%; width: 0; background: var(--brass); }
.paged .progress { display: none; }

/* текст */
.stage { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.book { max-width: var(--measure); margin: 0 auto; font-size: var(--fs); line-height: 1.62; padding-block: 0 4rem; }
.book p { margin: 0; text-indent: 1.6em; text-align: justify; -webkit-hyphens: auto; hyphens: auto; orphans: 2; widows: 2; }
.book p.coda { text-indent: 0; text-align: center; font-style: italic; margin: 1.8em 0; }

.title { text-align: center; padding-block: 4.5rem 3.5rem; border-bottom: 1px solid var(--rule); margin-bottom: 1rem; }
.title .author { font-family: var(--f-display); font-weight: 500; font-size: 1.15rem; letter-spacing: .3em; text-transform: uppercase; color: var(--brass); }
.title h1 { font-family: var(--f-display); font-weight: 600; font-size: clamp(2.6rem, 9vw, 4.2rem); line-height: 1.02; margin: 1.6rem 0 1.4rem; text-wrap: balance; }
.title h1 small { display: block; font-size: .5em; font-style: italic; font-weight: 400; color: var(--brass); margin: .25em 0; }
.title .meta { font-size: .92rem; color: var(--ink-soft); display: grid; gap: .25rem; }
.title .meta em { font-size: .88rem; }
.title .hint { margin-top: 2.6rem; font-family: var(--f-ui); font-size: .8rem; color: var(--ink-soft); text-align: center; text-indent: 0; -webkit-hyphens: none; hyphens: none; }
.title .hint[hidden] { display: none; }

.book h2, .book h3, .book h4, .book h5 { font-weight: 400; text-align: center; text-wrap: balance; line-height: 1.2;
  -webkit-hyphens: none; hyphens: none; break-after: avoid; page-break-after: avoid; }
.book h2 { font-family: var(--f-display); font-weight: 600; font-size: 2.05em; margin: 4.5rem 0 2rem; }
.book h3 { font-family: var(--f-display); font-weight: 600; font-size: 1.55em; margin: 3.5rem 0 1.4rem; }
.book h4 { font-size: 1.12em; font-style: italic; margin: 2.8rem 0 1.1rem; }
.book h5 { font-size: 1em; font-style: italic; color: var(--ink-soft); margin: 2.2rem 0 .9rem; }
.book h2 + p, .book h3 + p, .book h4 + p, .book h5 + p, .verse + p, .part + p { text-indent: 0; }
.book h2::after, .book h3::after { content: ""; display: block; width: 3rem; height: 1px; background: var(--brass); margin: 1.1rem auto 0; }
.part { text-align: center; margin: 6rem 0 2.5rem; padding-top: 3rem; border-top: 1px solid var(--rule); break-after: avoid; }
.part .label { font-family: var(--f-ui); font-size: .78rem; letter-spacing: .32em; text-transform: uppercase; color: var(--brass); }
.part h2 { margin: .8rem 0 0; font-size: 3em; }
.part h2::after { display: none; }

.verse { margin: 1.1em 0 1.1em 2.5em; font-style: italic; break-inside: avoid; }
.verse p { text-indent: 0; text-align: left; }

a.nref { color: var(--brass); text-decoration: none; font-family: var(--f-ui); font-size: .68em; vertical-align: super;
  line-height: 0; padding: 0 .12em; font-variant-numeric: tabular-nums; }
a.nref:hover { text-decoration: underline; }
.notes { margin-top: 3rem; padding-top: .8rem; border-top: 1px solid var(--rule); font-size: .86em; line-height: 1.5; color: var(--ink-soft); }
.notes h6 { font-family: var(--f-ui); font-size: .72rem; letter-spacing: .2em; text-transform: uppercase; font-weight: 500; margin: 0 0 .6rem; color: var(--ink-soft); }
.notes ol { margin: 0; padding-left: 2.1em; }
.notes li { padding-left: .2em; margin-bottom: .35rem; }
.notes li::marker { font-family: var(--f-ui); font-variant-numeric: tabular-nums; color: var(--brass); font-size: .9em; }
.notes a.back { font-family: var(--f-ui); text-decoration: none; color: var(--brass); margin-left: .3em; }

.foot { margin-top: 4rem; padding-top: 1.4rem; border-top: 1px solid var(--rule);
  font-family: var(--f-ui); font-size: .8rem; color: var(--ink-soft); display: grid; gap: .3rem; text-align: center; }

/* режим «по страницам» */
html.paged { height: 100%; box-sizing: border-box; overflow: hidden; scroll-padding-top: 0; }
html.paged body { height: 100%; overflow: hidden; }
.paged .app { height: 100%; display: flex; flex-direction: column; }
.paged .bar { position: relative; top: 0; }
.paged .stage { flex: 1; min-height: 0; position: relative; padding-block: 1.6rem 1rem; touch-action: pan-y pinch-zoom; }
.paged .book { position: relative; max-width: none; width: var(--spread-w); height: var(--page-h); overflow: hidden; padding: 0; margin: 0 auto; }
.paged .chunk { display: none; }
.paged .chunk.cur, .paged .chunk.measuring { display: block; width: var(--spread-w); height: var(--page-h);
  column-width: var(--col-w); column-gap: var(--gap); column-fill: auto; }
.paged .chunk.measuring { position: absolute; top: 0; left: 0; visibility: hidden; }
.paged .chunk.anim { transition: transform .26s ease; will-change: transform; }
.paged .title { border-bottom: 0; padding-top: 14%; margin: 0; }
.paged .part { border-top: 0; padding-top: 0; margin-top: 22%; }
.paged .book > .chunk > h2:first-child { margin-top: 2.5rem; }
.paged .notes { break-before: column; margin-top: 0; }

.ribbon { display: none; }
.paged .ribbon:not([hidden]) { display: block; position: absolute; top: 0; z-index: 2; width: 14px; height: 30px;
  right: max(4px, calc(50% - var(--spread-w) / 2)); background: var(--brass);
  clip-path: polygon(0 0, 100% 0, 100% 100%, 50% 72%, 0 100%); }

.pager { display: none; }
.paged .pager { display: flex; align-items: center; gap: .6rem; border-top: 1px solid var(--rule); font-family: var(--f-ui); font-size: .82rem;
  min-height: 3rem; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.pager input { flex: 1; min-width: 0; accent-color: var(--brass); }
.pager .pg { font-variant-numeric: tabular-nums; color: var(--ink-soft); white-space: nowrap; min-width: 6.5em; text-align: center; }
.pager .peek { position: absolute; bottom: 3.6rem; left: 50%; transform: translateX(-50%); max-width: calc(100% - 32px);
  background: var(--ink); color: var(--paper); border-radius: 6px; padding: .35rem .7rem; font-size: .8rem; white-space: nowrap;
  overflow: hidden; text-overflow: ellipsis; z-index: 6; pointer-events: none; }

/* всплывающая сноска */
.pop { position: fixed; z-index: 30; max-width: min(26rem, calc(100vw - 32px)); background: var(--panel); color: var(--ink);
  border: 1px solid var(--rule); border-radius: 8px; padding: .75rem .9rem; font-size: .92rem; line-height: 1.5;
  box-shadow: 0 10px 30px rgba(0,0,0,.18); }
.pop .n { font-family: var(--f-ui); color: var(--brass); margin-right: .35em; }

/* настройки */
.menu { position: fixed; z-index: 15; top: calc(env(safe-area-inset-top, 0px) + 3.4rem); right: max(16px, env(safe-area-inset-right, 0px));
  background: var(--panel); border: 1px solid var(--rule); border-radius: 8px; padding: .9rem 1rem; font-family: var(--f-ui);
  font-size: .85rem; display: grid; gap: .7rem; box-shadow: 0 10px 30px rgba(0,0,0,.14); }
.menu .row { display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
.menu .row > span { color: var(--ink-soft); }
.menu .seg { display: flex; gap: .3rem; }

/* оглавление и закладки */
.drawer { position: fixed; z-index: 20; inset: 0 auto 0 0; width: min(23rem, 88vw); background: var(--panel);
  border-right: 1px solid var(--rule); transform: translateX(-102%); transition: transform .22s ease;
  display: flex; flex-direction: column; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px);
  padding-left: env(safe-area-inset-left, 0px); }
.drawer.open { transform: none; }
.drawer header { display: flex; align-items: center; gap: .4rem; padding: .9rem .8rem .6rem 1rem; font-family: var(--f-ui); }
.drawer .tabs { display: flex; gap: .3rem; flex: 1; }
.drawer .tab { font: inherit; font-size: .76rem; letter-spacing: .12em; text-transform: uppercase; background: none; border: 0;
  border-bottom: 2px solid transparent; color: var(--ink-soft); padding: .4rem .3rem; cursor: pointer; }
.drawer .tab[aria-selected="true"] { color: var(--brass); border-bottom-color: var(--brass); }
.drawer .list { overflow-y: auto; padding: 0 .6rem 2rem; font-family: var(--f-text); font-size: .95rem; flex: 1; }
.drawer .list[hidden] { display: none; }
.drawer ol { list-style: none; margin: 0; padding: 0; }
.drawer ol ol { padding-left: 1rem; }
.drawer .toc a { display: block; padding: .32rem .6rem; border-radius: 5px; color: var(--ink); text-decoration: none; line-height: 1.3; }
.drawer .toc a:hover { background: var(--paper); }
.drawer .toc a.cur { color: var(--brass); background: var(--paper); }
.drawer .lv0 > a { font-family: var(--f-ui); font-size: .76rem; letter-spacing: .16em; text-transform: uppercase; color: var(--brass); margin-top: .9rem; }
.drawer .lv3 > a, .drawer .lv4 > a { font-size: .9rem; color: var(--ink-soft); }
.bms { display: grid; gap: .5rem; padding-top: .4rem; }
.bm { display: flex; gap: .4rem; align-items: flex-start; background: var(--paper); border: 1px solid var(--rule); border-radius: 6px; }
.bm-go { flex: 1; min-width: 0; text-align: left; background: none; border: 0; color: var(--ink); font: inherit; padding: .6rem .7rem; cursor: pointer; display: grid; gap: .2rem; }
.bm-go:hover .bm-l { color: var(--brass); }
.bm-l { font-family: var(--f-ui); font-size: .8rem; font-weight: 500; }
.bm-s { font-style: italic; font-size: .88rem; color: var(--ink-soft); overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.bm-d { font-family: var(--f-ui); font-size: .72rem; color: var(--ink-soft); }
.bm .btn { margin: .45rem .45rem 0 0; border-color: transparent; }
.bm-empty, .sync { font-family: var(--f-ui); font-size: .82rem; color: var(--ink-soft); line-height: 1.45; padding: .4rem .4rem; }
.sync { border-top: 1px solid var(--rule); margin-top: .8rem; padding-top: .8rem; }
.veil { position: fixed; inset: 0; z-index: 19; background: var(--veil); }

.toast { position: fixed; z-index: 25; left: 50%; transform: translateX(-50%); bottom: calc(env(safe-area-inset-bottom, 0px) + 4rem);
  width: max-content; max-width: calc(100vw - 32px); background: var(--ink); color: var(--paper); border-radius: 8px;
  padding: .6rem .7rem .6rem 1rem; font-family: var(--f-ui); font-size: .85rem; display: flex; gap: .6rem; align-items: center;
  box-shadow: 0 10px 30px rgba(0,0,0,.2); }
.toast span { min-width: 0; }
.toast .btn { color: var(--paper); border-color: var(--ink-soft); white-space: nowrap; }

@media (max-width: 520px) {
  :root { --fs: 1.04rem; }
  .book p { text-indent: 1.2em; }
  .bar .pct { display: none; }
  .verse { margin-left: 1.2em; }
  .paged .stage { padding-block: 1.1rem .8rem; }
}
@media (prefers-reduced-motion: reduce) { .drawer, .paged .chunk.anim { transition: none; } }
</style>
"""

ICON_TOC = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3 5h14M3 10h14M3 15h9"/></svg>'
ICON_BM = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5.5 2.8h9v14.4L10 13.6l-4.5 3.6z"/></svg>'
ICON_PREV = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12.5 4 6.5 10l6 6"/></svg>'
ICON_NEXT = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7.5 4l6 6-6 6"/></svg>'

SCRIPT = r"""
<script>
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var root = document.documentElement;

  // ---------- локальное хранилище (удобства этого браузера + копия закладок) ----------
  var LS = "stirner-reader-v2";
  var local = {};
  try { local = JSON.parse(localStorage.getItem(LS) || "{}") || {}; } catch (e) { local = {}; }
  if (!Array.isArray(local.bms)) local.bms = [];
  if (!local.dev) local.dev = Math.random().toString(36).slice(2, 10);
  function saveLocal() { try { localStorage.setItem(LS, JSON.stringify(local)); } catch (e) {} }

  // ---------- структура книги ----------
  var book = $("book"), stage = $("stage");
  var chunks = Array.prototype.slice.call(book.querySelectorAll(".chunk"));
  var anchors = [];
  chunks.forEach(function (c, ci) {
    c._ci = ci; c._a0 = anchors.length;
    Array.prototype.forEach.call(c.children, function (el) {
      if (el.classList.contains("notes") || el.classList.contains("foot")) return;
      el._ai = anchors.length; el._ci = ci; anchors.push(el);
    });
    c._a1 = anchors.length;
  });
  var heads = Array.prototype.slice.call(book.querySelectorAll("[data-toc]"));
  heads.forEach(function (h, i) { h._hi = i; h._ci = h.closest(".chunk")._ci; });
  chunks.forEach(function (c) {
    c._heads = heads.filter(function (h) { return h._ci === c._ci; });
    var before = heads.filter(function (h) { return h._ci < c._ci; });
    c._inherit = before.length ? before[before.length - 1] : null;
  });
  var tocLinks = {};
  Array.prototype.forEach.call(document.querySelectorAll("#toc-list a"), function (a) { tocLinks[a.getAttribute("href").slice(1)] = a; });

  // ---------- настройки ----------
  var sizes = [0.94, 1.0, 1.06, 1.125, 1.2, 1.3, 1.42];
  var si = typeof local.size === "number" ? local.size : (window.matchMedia("(max-width: 520px)").matches ? 2 : 3);
  function applySize() { root.style.setProperty("--fs", sizes[si] + "rem"); }
  if (typeof local.size === "number") applySize();
  var mode = local.mode === "scroll" ? "scroll" : "paged";

  // ---------- постраничная раскладка ----------
  var L = null, cur = { ci: 0, page: 0, pages: 1 }, pagesBy = [], layoutGen = 0;
  function computeLayout() {
    var cs = getComputedStyle(stage);
    var w = stage.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
    var h = stage.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
    var fs = parseFloat(getComputedStyle(book).fontSize) || 18;
    var gap = Math.round(Math.max(32, 2.6 * fs));
    var measure = 33 * fs;
    var n = (w >= 2 * 28 * fs + gap && w >= 900) ? 2 : 1;
    var colW = Math.floor(Math.min(measure, (w - (n - 1) * gap) / n));
    var spreadW = n * colW + (n - 1) * gap;
    L = { n: n, colW: colW, gap: gap, spreadW: spreadW, pageH: Math.max(200, Math.floor(h)), step: spreadW + gap };
    book.style.setProperty("--col-w", colW + "px");
    book.style.setProperty("--gap", gap + "px");
    book.style.setProperty("--page-h", L.pageH + "px");
    root.style.setProperty("--spread-w", spreadW + "px");
    pagesBy = chunks.map(function () { return null; });
    layoutGen++;
  }
  function countPages(c) {
    var cols = Math.round((c.scrollWidth + L.gap) / (L.colW + L.gap));
    return Math.max(1, Math.ceil(cols / L.n));
  }
  function showChunk(ci) {
    var c = chunks[ci];
    if (cur.el && cur.el !== c) { cur.el.classList.remove("cur", "anim"); cur.el.style.transform = ""; }
    c.classList.add("cur");
    cur.el = c; cur.ci = ci;
    cur.pages = countPages(c);
    pagesBy[ci] = cur.pages;
  }
  function pageOfEl(el) {
    var cr = cur.el.getBoundingClientRect();
    var rs = el.getClientRects(), r = rs.length ? rs[0] : el.getBoundingClientRect();
    return Math.max(0, Math.min(cur.pages - 1, Math.floor((r.left - cr.left + 2) / L.step)));
  }
  function setPage(p, animate) {
    cur.page = Math.max(0, Math.min(cur.pages - 1, p));
    var c = cur.el;
    if (animate) { c.classList.add("anim"); clearTimeout(c._t); c._t = setTimeout(function () { c.classList.remove("anim"); }, 320); }
    c.style.transform = "translateX(" + (-cur.page * L.step) + "px)";
    closePop();
    update();
  }

  // где мы: глобальный индекс блока + смещение в страницах
  function locatorNow() {
    if (mode === "paged") {
      var c = cur.el, lo = c._a0, hi = c._a1 - 1, ans = c._a0;
      while (lo <= hi) { var mid = (lo + hi) >> 1; if (pageOfEl(anchors[mid]) <= cur.page) { ans = mid; lo = mid + 1; } else hi = mid - 1; }
      return { pi: ans, k: cur.page - pageOfEl(anchors[ans]) };
    }
    var top = 70, l = 0, r = anchors.length - 1, a = 0;
    while (l <= r) { var m = (l + r) >> 1; if (anchors[m].getBoundingClientRect().bottom < top) l = m + 1; else { a = m; r = m - 1; } }
    return { pi: a, k: 0 };
  }
  var quietScroll = 0;
  function goToLocator(loc) {
    var a = anchors[Math.max(0, Math.min(anchors.length - 1, loc.pi | 0))];
    if (mode === "paged") {
      showChunk(a._ci);
      setPage(pageOfEl(a) + (loc.k | 0), false);
    } else {
      quietScroll = Date.now();
      a.scrollIntoView({ block: "start" });
      update();
    }
  }
  function goToEl(el, byUser) {
    if (mode === "paged") {
      showChunk(el.closest(".chunk")._ci);
      setPage(pageOfEl(el), false);
    } else {
      el.scrollIntoView({ block: "start" });
    }
    if (byUser) moved();
  }
  function next() {
    if (cur.page < cur.pages - 1) setPage(cur.page + 1, true);
    else if (cur.ci < chunks.length - 1) { showChunk(cur.ci + 1); setPage(0, false); }
    else return;
    moved();
  }
  function prev() {
    if (cur.page > 0) setPage(cur.page - 1, true);
    else if (cur.ci > 0) { showChunk(cur.ci - 1); setPage(cur.pages - 1, false); }
    else return;
    moved();
  }

  // номера страниц по всей книге: считаем фрагменты в простое
  var lastInput = 0;
  function measureAll() {
    var gen = layoutGen;
    function step() {
      if (gen !== layoutGen || mode !== "paged") return;
      if (Date.now() - lastInput < 900) { setTimeout(step, 600); return; }
      var i = pagesBy.indexOf(null);
      if (i < 0) { update(); return; }
      var c = chunks[i];
      c.classList.add("measuring");
      pagesBy[i] = countPages(c);
      c.classList.remove("measuring");
      setTimeout(step, 40);
    }
    setTimeout(step, 300);
  }
  function totals() {
    if (pagesBy.indexOf(null) >= 0) return null;
    var start = [], s = 0;
    pagesBy.forEach(function (n) { start.push(s); s += n; });
    return { start: start, total: s };
  }

  // ---------- шапка, прогресс, текущая глава ----------
  var whereEl = $("where"), pctEl = $("pct"), barEl = $("progress-fill"), pgEl = $("pg"), slider = $("slider");
  var bmBtn = $("bm-btn"), ribbon = $("ribbon");
  var curHead = undefined;
  function currentHead() {
    if (mode === "paged") {
      var hs = cur.el._heads, h = cur.el._inherit;
      for (var i = 0; i < hs.length; i++) { if (pageOfEl(hs[i]) <= cur.page) h = hs[i]; else break; }
      return h;
    }
    var y = 90, best = null;
    for (var j = 0; j < heads.length; j++) { if (heads[j].getBoundingClientRect().top <= y) best = heads[j]; else break; }
    return best;
  }
  function update() {
    var h = currentHead();
    if (h !== curHead) {
      curHead = h;
      whereEl.innerHTML = h ? h.getAttribute("data-trail") : "<b>Единственный и его собственность</b>";
      Object.keys(tocLinks).forEach(function (k) { tocLinks[k].classList.remove("cur"); });
      if (h && tocLinks[h.id]) tocLinks[h.id].classList.add("cur");
    }
    if (mode === "paged") {
      var t = totals();
      if (t) {
        var g = t.start[cur.ci] + cur.page + 1;
        pgEl.textContent = g + " из " + t.total;
        slider.disabled = false; slider.max = t.total; slider.value = g;
      } else {
        pgEl.textContent = (cur.page + 1) + " из " + cur.pages + " в главе";
        slider.disabled = true;
      }
    } else {
      var max = root.scrollHeight - window.innerHeight;
      var f = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      barEl.style.width = (f * 100).toFixed(2) + "%";
      pctEl.textContent = Math.round(f * 100) + "%";
    }
    var on = !!currentBm();
    bmBtn.classList.toggle("on", on);
    bmBtn.setAttribute("aria-pressed", on ? "true" : "false");
    bmBtn.setAttribute("aria-label", on ? "Убрать закладку" : "Добавить закладку");
    ribbon.hidden = !(on && mode === "paged");
  }
  function labelNow() { var h = currentHead(); return h ? h.getAttribute("data-label") : "Титул"; }

  // ---------- закладки и место чтения ----------
  var bms = local.bms.slice();
  function bmHits(b) {
    var a = anchors[b.pi];
    if (!a) return false;
    if (mode === "paged") {
      if (a._ci !== cur.ci) return false;
      return Math.min(cur.pages - 1, pageOfEl(a) + (b.k | 0)) === cur.page;
    }
    return locatorNow().pi === b.pi;
  }
  function currentBm() { for (var i = 0; i < bms.length; i++) if (bmHits(bms[i])) return bms[i]; return null; }
  function snippetNow(loc) {
    var a = anchors[loc.pi];
    if (mode === "paged" && loc.k > 0) {
      var nx = anchors[loc.pi + 1];
      if (nx && nx._ci === cur.ci && pageOfEl(nx) === cur.page) a = nx;
    }
    var s = (a.textContent || "").replace(/\s+/g, " ").trim();
    return s.length > 120 ? s.slice(0, 118) + "…" : s;
  }
  function toggleBm() {
    var hit = currentBm();
    if (hit) { removeBm(hit.id); return; }
    var loc = locatorNow();
    var b = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), pi: loc.pi, k: loc.k,
      label: labelNow(), snip: snippetNow(loc), t: Date.now() };
    bms.push(b);
    persistBms();
    remoteSet("bm-" + b.id, { pi: b.pi, k: b.k, label: b.label, snip: b.snip, t: b.t }, function () { b.synced = true; persistBms(); });
    update(); renderBms();
  }
  function removeBm(id) {
    bms = bms.filter(function (b) { return b.id !== id; });
    persistBms();
    remoteDelete("bm-" + id);
    update(); renderBms();
  }
  function persistBms() { local.bms = bms; saveLocal(); }

  var posTimer = null, lastPosKey = "";
  function moved() {
    lastInput = Date.now();
    clearTimeout(posTimer);
    posTimer = setTimeout(function () {
      var loc = locatorNow(), key = loc.pi + ":" + loc.k;
      if (key === lastPosKey) return;
      lastPosKey = key;
      local.pos = { pi: loc.pi, k: loc.k, t: Date.now(), label: labelNow() };
      saveLocal();
      remoteSet("pos", { pi: loc.pi, k: loc.k, t: local.pos.t, label: local.pos.label, dev: local.dev });
    }, 1500);
  }

  var listEl = $("bm-list"), syncEl = $("sync-note"), bmCount = $("bm-count");
  function fmtDate(t) {
    try { return new Date(t).toLocaleDateString("ru-RU", { day: "numeric", month: "long", year: "numeric" }); } catch (e) { return ""; }
  }
  function renderBms() {
    var list = bms.slice().sort(function (a, b) { return a.pi - b.pi || a.k - b.k; });
    bmCount.textContent = list.length ? " · " + list.length : "";
    listEl.textContent = "";
    if (!list.length) {
      var p = document.createElement("p"); p.className = "bm-empty";
      p.textContent = "Закладок пока нет. Нажмите значок закладки в верхней панели, и страница появится здесь.";
      listEl.appendChild(p);
      return;
    }
    list.forEach(function (b) {
      var row = document.createElement("div"); row.className = "bm";
      var go = document.createElement("button"); go.type = "button"; go.className = "bm-go";
      var l = document.createElement("span"); l.className = "bm-l"; l.textContent = b.label || "Закладка";
      var s = document.createElement("span"); s.className = "bm-s"; s.textContent = b.snip || "";
      var d = document.createElement("span"); d.className = "bm-d"; d.textContent = fmtDate(b.t);
      go.appendChild(l); go.appendChild(s); go.appendChild(d);
      go.addEventListener("click", function () { closeDrawer(); goToLocator(b); moved(); });
      var x = document.createElement("button"); x.type = "button"; x.className = "btn icon"; x.textContent = "✕";
      x.setAttribute("aria-label", "Удалить закладку");
      x.addEventListener("click", function () { removeBm(b.id); });
      row.appendChild(go); row.appendChild(x);
      listEl.appendChild(row);
    });
  }

  // ---------- синхронизация через аккаунт Claude (если страница открыта как Artifact) ----------
  var sync = { coll: null, ok: false, busy: {}, queued: {} };
  function setSync(state) {
    var t = {
      local: "Закладки и место чтения хранятся в этом браузере.",
      connecting: "Подключаю ваш аккаунт…",
      slow: "Аккаунт пока не отвечает. Закладки сохраняются в этом браузере и отправятся позже.",
      synced: "Закладки и место чтения сохраняются в вашем аккаунте и видны на всех устройствах."
    };
    syncEl.textContent = t[state] || t.local;
  }
  function writeDoc(id, fn, done) {
    if (!sync.coll) return;
    if (sync.busy[id]) { sync.queued[id] = { fn: fn, done: done }; return; }
    sync.busy[id] = true;
    fn(sync.coll.doc(id)).then(function () { if (done) done(); }, function (e) {
      if (e && (e.code === "invalid_argument" || e.code === "not_granted" || e.code === "revoked" || e.code === "capability_disabled")) {
        sync.coll = null; setSync("local");
      }
    }).then(function () {
      sync.busy[id] = false;
      var q = sync.queued[id]; delete sync.queued[id];
      if (q) writeDoc(id, q.fn, q.done);
    });
  }
  function remoteSet(id, data, done) { writeDoc(id, function (ref) { return ref.set(data); }, done); }
  function remoteDelete(id) { writeDoc(id, function (ref) { return ref.delete(); }); }

  function applyRemote(snap, first) {
    var remote = {}, rpos = null;
    snap.docs.forEach(function (d) {
      if (!d.exists) return;
      var v = d.data() || {};
      if (d.id === "pos") rpos = v;
      else if (d.id.indexOf("bm-") === 0 && typeof v.pi === "number") {
        remote[d.id.slice(3)] = { id: d.id.slice(3), pi: v.pi, k: v.k | 0, label: String(v.label || ""), snip: String(v.snip || ""), t: +v.t || 0, synced: true };
      }
    });
    var merged = Object.keys(remote).map(function (k) { return remote[k]; });
    if (first) {
      bms.forEach(function (b) {
        if (remote[b.id]) return;
        if (b.synced) return;                    // удалена на другом устройстве
        merged.push(b);                          // ещё не отправлена — отправляем
        remoteSet("bm-" + b.id, { pi: b.pi, k: b.k, label: b.label, snip: b.snip, t: b.t }, function () { b.synced = true; persistBms(); });
      });
    } else {
      bms.forEach(function (b) { if (!remote[b.id] && !b.synced) merged.push(b); });
    }
    bms = merged;
    persistBms(); renderBms(); update();
    if (first && rpos && typeof rpos.pi === "number") {
      var lp = local.pos;
      if (!lp || (rpos.t || 0) > (lp.t || 0) + 1000) {
        if (rpos.dev !== local.dev) offerJump(rpos);
      } else if (lp && (lp.t || 0) > (rpos.t || 0)) {
        remoteSet("pos", { pi: lp.pi, k: lp.k, t: lp.t, label: lp.label, dev: local.dev });
      }
    } else if (first && !rpos && local.pos) {
      remoteSet("pos", { pi: local.pos.pi, k: local.pos.k, t: local.pos.t, label: local.pos.label, dev: local.dev });
    }
  }
  function startSync() {
    if (!window.claude || typeof window.claude.use !== "function") { setSync("local"); return; }
    Promise.all([window.claude.use("db"), window.claude.use("user")]).then(function (r) {
      var db = r[0], user = r[1];
      if (!db || !user) { setSync("local"); return; }
      return user.id().then(function (uid) {
        if (!uid) { setSync("local"); return; }
        sync.coll = db.collection("data/users/" + uid);
        setSync("connecting");
        var timer = setTimeout(function () { if (!sync.ok) setSync("slow"); }, 10000);
        var first = true;
        sync.coll.onSnapshot(function (snap) {
          if (snap.metadata.fromCache && first) { return; }
          clearTimeout(timer);
          if (!sync.ok) { sync.ok = true; setSync("synced"); }
          applyRemote(snap, first);
          first = false;
        }, function () { clearTimeout(timer); sync.coll = null; setSync("local"); });
      });
    }).catch(function () { setSync("local"); });
  }

  var toastEl = $("toast");
  function offerJump(pos) {
    toastEl.querySelector("span").textContent = "На другом устройстве вы остановились: " + (pos.label || "в книге");
    toastEl.hidden = false;
    $("toast-go").onclick = function () {
      toastEl.hidden = true;
      goToLocator(pos);
      local.pos = { pi: pos.pi, k: pos.k | 0, t: Date.now(), label: pos.label };
      lastPosKey = pos.pi + ":" + (pos.k | 0);
      saveLocal();
    };
    $("toast-x").onclick = function () { toastEl.hidden = true; };
    setTimeout(function () { toastEl.hidden = true; }, 15000);
  }

  // ---------- режимы ----------
  var modePaged = $("mode-paged"), modeScroll = $("mode-scroll"), pager = $("pager");
  function enterMode(m, keep) {
    var loc = keep ? locatorNow() : null;
    mode = m;
    root.classList.toggle("paged", m === "paged");
    $("hint").hidden = m !== "paged";
    modePaged.setAttribute("aria-pressed", m === "paged" ? "true" : "false");
    modeScroll.setAttribute("aria-pressed", m === "scroll" ? "true" : "false");
    if (m === "paged") {
      computeLayout();
      showChunk(loc ? anchors[loc.pi]._ci : 0);
      if (loc) goToLocator(loc); else setPage(0, false);
      measureAll();
    } else {
      if (cur.el) { cur.el.classList.remove("cur", "anim"); cur.el.style.transform = ""; cur.el = null; }
      if (loc) goToLocator(loc);
    }
    curHead = undefined;
    update();
  }
  function relayout() {
    if (mode !== "paged") { update(); return; }
    var loc = locatorNow();
    computeLayout();
    goToLocator(loc);
    measureAll();
  }

  // ---------- события ----------
  // перелистывание: тап по краям, свайп, клавиши
  var touch = null, suppressClick = 0;
  stage.addEventListener("touchstart", function (e) {
    if (mode !== "paged" || e.touches.length !== 1) { touch = null; return; }
    touch = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now() };
  }, { passive: true });
  stage.addEventListener("touchend", function (e) {
    if (!touch) return;
    var dx = e.changedTouches[0].clientX - touch.x, dy = e.changedTouches[0].clientY - touch.y;
    if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy) * 1.3 && Date.now() - touch.t < 800) {
      suppressClick = Date.now();
      if (dx < 0) next(); else prev();
    }
    touch = null;
  }, { passive: true });
  stage.addEventListener("click", function (e) {
    if (mode !== "paged") return;
    if (Date.now() - suppressClick < 500) return;
    if (e.target.closest("a, button, input, .pop")) return;
    if (pop) { closePop(); return; }
    var sel = window.getSelection && window.getSelection();
    if (sel && !sel.isCollapsed) return;
    var r = stage.getBoundingClientRect();
    if (e.clientX - r.left < r.width * 0.33) prev(); else next();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { closePop(); closeMenu(); if (drawer.classList.contains("open")) { closeDrawer(); } return; }
    if (mode !== "paged" || drawer.classList.contains("open") || e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.target.closest && e.target.closest("input, textarea")) return;
    if (e.key === "ArrowRight" || e.key === "PageDown" || (e.key === " " && !e.shiftKey)) { e.preventDefault(); next(); }
    else if (e.key === "ArrowLeft" || e.key === "PageUp" || (e.key === " " && e.shiftKey)) { e.preventDefault(); prev(); }
  });
  $("prev").addEventListener("click", prev);
  $("next").addEventListener("click", next);

  // ползунок по всей книге
  var peek = $("peek");
  function globalToPos(g) {
    var t = totals(); if (!t) return null;
    for (var i = chunks.length - 1; i >= 0; i--) if (g - 1 >= t.start[i]) return { ci: i, page: g - 1 - t.start[i] };
    return { ci: 0, page: 0 };
  }
  slider.addEventListener("input", function () {
    var p = globalToPos(+slider.value); if (!p) return;
    peek.hidden = false;
    peek.textContent = "Стр. " + slider.value + " · " + (chunks[p.ci].getAttribute("data-label") || "");
  });
  slider.addEventListener("change", function () {
    peek.hidden = true;
    var p = globalToPos(+slider.value); if (!p) return;
    showChunk(p.ci); setPage(p.page, false); moved();
  });
  slider.addEventListener("blur", function () { peek.hidden = true; });

  // браузер сам прокручивает скрытую область (поиск по странице, Tab к ссылке): переводим это в номер страницы
  book.addEventListener("scroll", function () {
    if (mode !== "paged") return;
    var x = book.scrollLeft;
    if (!x && !book.scrollTop) return;
    book.scrollLeft = 0; book.scrollTop = 0;
    if (x) { setPage(cur.page + Math.round(x / L.step), false); moved(); }
  });
  book.addEventListener("focusin", function (e) {
    if (mode !== "paged" || !cur.el || !cur.el.contains(e.target)) return;
    var p = pageOfEl(e.target);
    if (p !== cur.page) { setPage(p, false); moved(); }
  });

  // прокрутка в режиме ленты
  var ticking = false;
  window.addEventListener("scroll", function () {
    if (mode !== "scroll") return;
    closePop();
    if (!ticking) { ticking = true; requestAnimationFrame(function () { ticking = false; update(); }); }
    if (Date.now() - quietScroll > 600) moved();
  }, { passive: true });
  var rt = null;
  window.addEventListener("resize", function () { clearTimeout(rt); rt = setTimeout(relayout, 150); });

  // размер шрифта и режим
  var menu = $("menu"), menuBtn = $("menu-btn");
  function closeMenu() { menu.hidden = true; menuBtn.setAttribute("aria-expanded", "false"); }
  menuBtn.addEventListener("click", function (e) { e.stopPropagation(); menu.hidden = !menu.hidden; menuBtn.setAttribute("aria-expanded", menu.hidden ? "false" : "true"); });
  document.addEventListener("click", function (e) { if (!menu.hidden && !e.target.closest("#menu, #menu-btn")) closeMenu(); });
  function resize(d) {
    var n = Math.max(0, Math.min(sizes.length - 1, si + d)); if (n === si) return;
    var loc = locatorNow();
    si = n; local.size = si; saveLocal(); applySize();
    if (mode === "paged") { computeLayout(); goToLocator(loc); measureAll(); } else goToLocator(loc);
  }
  $("smaller").addEventListener("click", function () { resize(-1); });
  $("bigger").addEventListener("click", function () { resize(1); });
  modePaged.addEventListener("click", function () { if (mode !== "paged") { enterMode("paged", true); local.mode = "paged"; saveLocal(); } });
  modeScroll.addEventListener("click", function () { if (mode !== "scroll") { enterMode("scroll", true); local.mode = "scroll"; saveLocal(); } });
  bmBtn.addEventListener("click", toggleBm);

  // оглавление и закладки
  var drawer = $("drawer"), veil = $("veil"), opener = $("open-toc");
  var tabToc = $("tab-toc"), tabBm = $("tab-bm"), tocList = $("toc-list"), bmPane = $("bm-pane");
  function showTab(which) {
    var t = which === "toc";
    tabToc.setAttribute("aria-selected", t ? "true" : "false");
    tabBm.setAttribute("aria-selected", t ? "false" : "true");
    tocList.hidden = !t; bmPane.hidden = t;
  }
  drawer.inert = true;
  function openDrawer(which) {
    showTab(which || "toc");
    drawer.inert = false; drawer.classList.add("open"); veil.hidden = false;
    var c = drawer.querySelector(".toc a.cur");
    if (which !== "bm" && c) c.scrollIntoView({ block: "center" });
    (which === "bm" ? tabBm : tabToc).focus({ preventScroll: true });
  }
  function closeDrawer() { drawer.inert = true; drawer.classList.remove("open"); veil.hidden = true; opener.focus({ preventScroll: true }); }
  opener.addEventListener("click", function () { openDrawer("toc"); });
  tabToc.addEventListener("click", function () { showTab("toc"); });
  tabBm.addEventListener("click", function () { showTab("bm"); });
  $("close-drawer").addEventListener("click", closeDrawer);
  veil.addEventListener("click", closeDrawer);
  tocList.addEventListener("click", function (e) {
    var a = e.target.closest("a"); if (!a) return;
    e.preventDefault(); closeDrawer();
    var el = document.getElementById(a.getAttribute("href").slice(1));
    if (el) goToEl(el, true);
  });

  // сноски
  var pop = null;
  function closePop() { if (pop) { pop.remove(); pop = null; } }
  book.addEventListener("click", function (e) {
    var a = e.target.closest("a");
    if (!a) return;
    var href = a.getAttribute("href") || "";
    if (href.charAt(0) !== "#") return;
    e.preventDefault();
    var target = document.getElementById(href.slice(1));
    if (!target) return;
    if (!a.classList.contains("nref")) { closePop(); goToEl(target, true); return; }
    e.stopPropagation();
    var reopen = !pop || pop._ref !== a;
    closePop();
    if (!reopen) return;
    pop = document.createElement("div"); pop._ref = a;
    pop.className = "pop"; pop.setAttribute("role", "note");
    var n = document.createElement("span"); n.className = "n"; n.textContent = a.textContent + ".";
    var body = document.createElement("span"); body.innerHTML = target.querySelector(".nt").innerHTML;
    pop.appendChild(n); pop.appendChild(body);
    document.body.appendChild(pop);
    var r = a.getBoundingClientRect(), w = pop.offsetWidth, vw = document.documentElement.clientWidth;
    var left = Math.min(Math.max(16, r.left - w / 2), vw - w - 16);
    var top = r.bottom + 8;
    if (top + pop.offsetHeight > window.innerHeight - 16) top = r.top - pop.offsetHeight - 8;
    pop.style.left = left + "px"; pop.style.top = Math.max(8, top) + "px";
  });
  document.addEventListener("click", function (e) { if (pop && !e.target.closest(".pop, a.nref") && mode === "scroll") closePop(); });

  // ---------- старт ----------
  renderBms();
  setSync("local");
  var startEl = location.hash ? document.getElementById(location.hash.slice(1)) : null;
  enterMode(mode, false);
  if (startEl && book.contains(startEl)) goToEl(startEl, false);
  else if (local.pos && typeof local.pos.pi === "number") { goToLocator(local.pos); lastPosKey = local.pos.pi + ":" + (local.pos.k | 0); }
  update();
  var refit = function () { if (mode === "paged") relayout(); else update(); };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(refit);
  startSync();
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
    chunk_notes, chunk_size, last_label = [], 0, "Титул"
    trail = {}  # уровень -> название, для строки «где я» в шапке

    def close_chunk():
        if chunk_notes:
            out.append('<aside class="notes"><h6>Примечания</h6><ol>')
            for n in chunk_notes:
                out.append(f'<li id="n{n}" value="{n}"><span class="nt">{notes[n - 1]}</span>'
                           f'<a class="back" href="#r{n}" aria-label="Назад к тексту">↩</a></li>')
            out.append("</ol></aside>")
        out.append("</section>")
        chunk_notes.clear()

    def open_chunk(label):
        nonlocal chunk_size
        close_chunk()
        out.append(f'<section class="chunk" data-label="{attr(label)}">')
        chunk_size = 0

    # титул — первый фрагмент
    out.append('<section class="chunk" data-label="Титул"><header class="title">'
               f'<div class="author">{esc(front["author"])}</div>'
               '<h1>Единственный<small>и его</small>собственность</h1>'
               '<div class="meta">'
               f'<span>{esc(front["translator"])}</span>'
               + "".join(f"<em>{esc(x)}</em>" for x in front["edition"])
               + '</div><p class="hint" id="hint" hidden>Листайте касанием правого или левого края страницы, свайпом или стрелками.</p>'
               "</header>")

    for b in blocks:
        t = b["t"]
        if t == "part":
            label = f'{b["label"]}. {b["title"]}'
            open_chunk(label)
            trail.clear()
            trail[0] = label
            tr = f'<b>{esc(label)}</b>'
            out.append(f'<div class="part"><div class="label">{esc(b["label"])}</div>'
                       f'<h2 id="{b["id"]}" data-toc data-label="{attr(label)}" data-trail="{attr(tr)}">{esc(b["title"])}</h2></div>')
            toc.append((0, label, b["id"]))
            last_label = label
        elif t == "h":
            lvl = b["lvl"]
            text = html.unescape(b["text"])
            if lvl == 1 or (lvl == 2 and chunk_size > SMALL_CHUNK):
                open_chunk(text)
            for k in [k for k in trail if k >= lvl]:
                del trail[k]
            trail[lvl] = text
            parts = [trail[k] for k in sorted(trail)]
            tr = " · ".join(esc(p) for p in parts[:-1])
            tr = (tr + " · " if tr else "") + f"<b>{esc(parts[-1])}</b>"
            tag = f"h{lvl + 1}"
            out.append(f'<{tag} id="{b["id"]}" data-toc data-label="{attr(text)}" data-trail="{attr(tr)}">{b["text"]}</{tag}>')
            toc.append((lvl, text, b["id"]))
            last_label = text
        elif t == "verse":
            out.append('<div class="verse">' + "".join(f"<p>{l}</p>" for l in b["lines"]) + "</div>")
            chunk_size += sum(len(l) for l in b["lines"])
        else:
            h = b["html"]
            for m in re.finditer(r"\{\{NOTE:(\d+)\}\}", h):
                chunk_notes.append(int(m.group(1)))
            h = re.sub(r"\{\{NOTE:(\d+)\}\}", lambda m: note_ref(int(m.group(1))), h)
            cls = ' class="coda"' if b.get("cls") == "coda" else ""
            out.append(f"<p{cls}>{h}</p>")
            chunk_size += len(h)
    out.append('<footer class="foot">'
               f'<span>{esc(front["author"])}. {esc(front["title"])}. {esc(front["translator"])}.</span>'
               '<span>Текст: Lib.ru/Классика, az.lib.ru. Типографика, разбивка на главы и сноски восстановлены.</span>'
               "</footer>")
    close_chunk()

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

    head = (
        "<title>Единственный и его собственность</title>\n"
        '<meta name="claude:viewport-fit-sides" content="cover">\n'
        '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
        '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,400'
        '&family=IBM+Plex+Sans:wght@400;500&family=Literata:ital,opsz,wght@0,7..72,400;0,7..72,500;1,7..72,400&display=swap">\n'
    )
    bar = (
        '<div class="bar"><div class="bar-in">'
        f'<button class="btn icon" id="open-toc" type="button" aria-label="Оглавление и закладки" aria-controls="drawer">{ICON_TOC}</button>'
        '<div class="where" id="where"><b>Единственный и его собственность</b></div>'
        '<span class="pct" id="pct">0%</span>'
        f'<button class="btn icon" id="bm-btn" type="button" aria-pressed="false" aria-label="Добавить закладку">{ICON_BM}</button>'
        '<button class="btn" id="menu-btn" type="button" aria-haspopup="true" aria-expanded="false" aria-controls="menu" aria-label="Шрифт и режим чтения">Aa</button>'
        '</div><div class="progress"><i id="progress-fill"></i></div></div>'
    )
    menu = (
        '<div class="menu" id="menu" hidden>'
        '<div class="row"><span>Шрифт</span><div class="seg">'
        '<button class="btn" id="smaller" type="button" aria-label="Мельче">A−</button>'
        '<button class="btn" id="bigger" type="button" aria-label="Крупнее">A+</button></div></div>'
        '<div class="row"><span>Чтение</span><div class="seg">'
        '<button class="btn" id="mode-paged" type="button" aria-pressed="true">По страницам</button>'
        '<button class="btn" id="mode-scroll" type="button" aria-pressed="false">Лентой</button></div></div>'
        "</div>"
    )
    drawer = (
        '<nav class="drawer" id="drawer" aria-label="Оглавление и закладки">'
        '<header><div class="tabs" role="tablist">'
        '<button class="tab" id="tab-toc" role="tab" type="button" aria-selected="true" aria-controls="toc-list">Оглавление</button>'
        '<button class="tab" id="tab-bm" role="tab" type="button" aria-selected="false" aria-controls="bm-pane">Закладки<span id="bm-count"></span></button>'
        '</div><button class="btn icon" id="close-drawer" type="button" aria-label="Закрыть">✕</button></header>'
        f'<div class="list toc" id="toc-list" role="tabpanel">{toc_html()}</div>'
        '<div class="list" id="bm-pane" role="tabpanel" hidden><div class="bms" id="bm-list"></div>'
        '<p class="sync" id="sync-note">Закладки и место чтения хранятся в этом браузере.</p></div>'
        '</nav><div class="veil" id="veil" hidden></div>'
    )
    pager = (
        '<div class="pager" id="pager">'
        f'<button class="btn icon" id="prev" type="button" aria-label="Предыдущая страница">{ICON_PREV}</button>'
        '<input type="range" id="slider" min="1" max="1" value="1" aria-label="Перейти к странице" disabled>'
        '<span class="pg" id="pg">1</span>'
        f'<button class="btn icon" id="next" type="button" aria-label="Следующая страница">{ICON_NEXT}</button>'
        '<div class="peek" id="peek" hidden></div>'
        "</div>"
    )
    toast = ('<div class="toast" id="toast" role="status" hidden><span></span>'
             '<button class="btn" id="toast-go" type="button">Перейти</button>'
             '<button class="btn icon" id="toast-x" type="button" aria-label="Закрыть">✕</button></div>')
    return (
        head + STYLE
        + '<div class="app">' + bar
        + '<div class="stage" id="stage"><div class="ribbon" id="ribbon" hidden></div>'
        + '<main class="book" id="book" lang="ru">' + "".join(out) + "</main></div>"
        + pager + "</div>"
        + menu + drawer + toast + SCRIPT
    )


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
