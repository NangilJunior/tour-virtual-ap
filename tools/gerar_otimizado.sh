#!/usr/bin/env bash
# Gera assets/Apartamento/APARTAMENTO.blend (otimizado, fundido por material)
# a partir de fonte_blend/APARTAMENTO.blend (o arquivo editável).
# FECHE O EDITOR GODOT ANTES DE RODAR (crash por arquivo meio-escrito).
set -euo pipefail
cd "$(dirname "$0")/.."

BLENDER=/mnt/Games/Softwares/blender-5.1.2-linux-x64/blender
FONTE=fonte_blend/APARTAMENTO.blend
DESTINO=$PWD/assets/Apartamento/APARTAMENTO.blend

if pgrep -f "godot.*--editor" >/dev/null; then
    echo "ERRO: feche o editor Godot antes de gerar o blend otimizado." >&2
    exit 1
fi

"$BLENDER" --background "$FONTE" --python tools/merge_por_material.py -- "$DESTINO" 2>&1 | grep -E "^(MERGE|SALVO)"
echo "Pronto: abra o Godot para reimportar (e rebakeie o lightmap)."
