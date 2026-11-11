#!/usr/bin/env bash
# Полная проверка проекта без Roblox Studio. Запускать из папки roblox-game.
# Нужны: rojo, lune, selene, stylua (cargo install ...), python3 + Pillow (для картинок).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== формат и линтер"
stylua --check src tools/harness tools/check_syntax.luau
selene src

echo "== синтаксис"
lune run tools/check_syntax.luau src

echo "== сборка места"
rojo build default.project.json -o build/Resonance.rbxlx

echo "== дымовой тест в эмуляторе"
lune run tools/harness/smoke.luau | grep -E "^ FAIL|^== Ошибки|^   ×|ИТОГ" || true
lune run tools/harness/smoke.luau >/dev/null

echo "== стресс-тест: случайные действия трёх игроков"
for seed in 1 2 3; do
	lune run tools/harness/monkey.luau "$seed" 120
done

if [ "${1:-}" = "--previews" ]; then
	echo "== картинки-превью"
	tmp="$(mktemp -d)"
	lune run tools/harness/smoke.luau --dump "$tmp" >/dev/null
	lune run tools/harness/dump_anims.luau "$tmp" >/dev/null
	lune run tools/harness/dump_gui.luau "$tmp" >/dev/null
	python3 tools/preview/render.py "$tmp" docs
	python3 tools/preview/render_gui.py "$tmp" docs
	rm -rf "$tmp"
fi
echo "готово"
