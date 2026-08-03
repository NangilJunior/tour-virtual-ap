"""Prepara as folhas de porta do APARTAMENTO.blend para o unwrap de UV2 do Godot.

Problema que isto resolve
-------------------------
As 5 folhas `C-Porta-70#1.001/.003/.004/.005` e `portaQuarto` compartilham UM
único datablock de malha (`C-Porta-70#1`), cada objeto com uma escala diferente
e duas delas ESPELHADAS (determinante negativo).

O importador do Godot desdobra a UV2 uma vez por *recurso* de malha
(`lightmap_unwrap_cached`), usando a transform da primeira instância que
encontra, e guarda o `lightmap_size_hint` na própria malha. Com o datablock
compartilhado:

  * as outras 4 portas herdam uma UV2 e uma resolução de lightmap calculadas
    para o tamanho de OUTRA porta — densidade de texel errada;
  * nas duas espelhadas o winding da geometria fica invertido em relação ao
    desdobramento, o que suja o padding das ilhas no bake.

O conserto é dar a cada folha a sua própria malha, assar a escala na geometria
(o que também elimina o espelhamento) e limpar as faces degeneradas que fazem o
xatlas emitir ilhas-lixo. Depois disso o Godot desdobra cada porta
individualmente, na escala real dela.

Uso (com o Blender e o editor do Godot FECHADOS):
    blender --background assets/Apartamento/APARTAMENTO.blend \
        --python tools/portas_uv_lightmap.py -- --save

Sem `--save` roda em modo de inspeção e não escreve nada.
Com `--out CAMINHO` salva numa cópia em vez do arquivo original.

Depois de salvar é obrigatório invalidar o cache de unwrap e reimportar, senão o
Godot reaproveita a UV2 velha:
    rm assets/Apartamento/APARTAMENTO.blend.unwrap_cache
    rm -rf .godot/imported/APARTAMENTO.blend-*
    godot --headless --editor --quit
e refazer o bake do LightmapGI.
"""

import sys

import bmesh
import bpy
from mathutils import Matrix

# Folhas de porta que entram no lightmap. Os nomes são referenciados por
# scenes/portas_interativas.gd — NÃO renomear os objetos aqui.
FOLHAS = [
    "C-Porta-70#1.001",
    "C-Porta-70#1.002",
    "C-Porta-70#1.003",
    "C-Porta-70#1.004",
    "C-Porta-70#1.005",
    "portaQuarto",
    "portaGuarda",
]


def argumentos():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    salvar = "--save" in argv
    saida = None
    if "--out" in argv:
        saida = argv[argv.index("--out") + 1]
    return salvar, saida


def volume_assinado(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    v = bm.calc_volume(signed=True)
    bm.free()
    return v


def posicoes_coincidentes(me):
    """Vértices distintos ocupando a mesma posição.

    O SketchUp faz aresta dura por vértice duplicado; se houver duplicados não
    se pode dissolver geometria degenerada sem fundir os splits e suavizar as
    quinas (ver a nota sobre remove_doubles no pipeline do projeto).
    """
    pos = {}
    for v in me.vertices:
        k = (round(v.co.x, 6), round(v.co.y, 6), round(v.co.z, 6))
        pos[k] = pos.get(k, 0) + 1
    return sum(c - 1 for c in pos.values() if c > 1)


def desanexar_malha(ob):
    """Dá ao objeto uma cópia exclusiva da malha, se ela for compartilhada."""
    if ob.data.users <= 1:
        return False
    nova = ob.data.copy()
    nova.name = "%s_lm" % ob.name
    ob.data = nova
    return True


def assar_escala(ob):
    """Move a escala do objeto para dentro da geometria.

    Mantém a posição e a rotação no mundo. Se a escala for espelhada
    (determinante negativo), inverte o winding das faces para as normais
    voltarem a apontar para fora.
    """
    mundo = ob.matrix_world.copy()
    loc, rot, esc = mundo.decompose()
    if abs(esc.x - 1) < 1e-6 and abs(esc.y - 1) < 1e-6 and abs(esc.z - 1) < 1e-6:
        return False, False

    espelhado = ob.matrix_world.to_3x3().determinant() < 0
    ob.data.transform(Matrix.Diagonal(esc).to_4x4())
    ob.matrix_world = Matrix.LocRotScale(loc, rot, (1.0, 1.0, 1.0))

    if espelhado:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
    return True, espelhado


def limpar_degeneradas(ob):
    """Dissolve arestas/faces de área nula que quebram o unwrap do xatlas."""
    if posicoes_coincidentes(ob.data) > 0:
        return -1  # inseguro: dissolver fundiria os splits de aresta dura

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    antes = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    if antes:
        bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
        bm.to_mesh(ob.data)
        ob.data.update()
    bm.free()
    return antes


def main():
    salvar, saida = argumentos()
    print("=== PREPARO DE UV2 DAS PORTAS (%s) ==="
          % ("GRAVANDO" if salvar else "INSPEÇÃO"))

    for nome in FOLHAS:
        ob = bpy.data.objects.get(nome)
        if not ob or ob.type != "MESH":
            print("  %-22s AUSENTE — pulando" % nome)
            continue

        malha_antes = ob.data.name
        users_antes = ob.data.users
        vol_antes = volume_assinado(ob.data)
        dim_antes = tuple(ob.dimensions)

        copiou = desanexar_malha(ob)
        assou, espelhado = assar_escala(ob)
        degen = limpar_degeneradas(ob)

        bpy.context.view_layer.update()
        vol_depois = volume_assinado(ob.data)
        dim_depois = tuple(ob.dimensions)
        desvio = max(abs(a - b) for a, b in zip(dim_antes, dim_depois))

        print("\n  %s" % nome)
        print("    malha  %s (users=%d) -> %s" % (malha_antes, users_antes, ob.data.name)
              if copiou else "    malha  %s (já exclusiva)" % malha_antes)
        print("    escala assada=%s espelhada=%s -> escala final=%s"
              % (assou, espelhado, tuple(round(c, 6) for c in ob.matrix_world.to_scale())))
        print("    faces degeneradas removidas=%s"
              % ("INSEGURO (há vértices coincidentes)" if degen < 0 else degen))
        print("    volume %.6g -> %.6g %s"
              % (vol_antes, vol_depois,
                 "OK" if vol_depois > 0 else "<<< NORMAIS INVERTIDAS"))
        print("    dimensões no mundo inalteradas (desvio máx %.3g m)" % desvio)

    if salvar:
        destino = saida or bpy.data.filepath
        bpy.ops.wm.save_as_mainfile(filepath=destino, compress=False)
        print("\nSalvo em %s" % destino)
    else:
        print("\nNada gravado (rode com -- --save).")


main()
