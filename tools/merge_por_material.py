# Gera a versão otimizada do apartamento: funde objetos por (coleção, materiais)
# para derrubar draw calls (~6200 -> centenas). Roda via tools/gerar_otimizado.sh.
#
# Fica de fora da fusão (de propósito):
#   - 02_Portas_Janelas: nomes com "porta" controlam a exceção de colisão no runtime;
#   - tecidos enrugados (boucle/algodão/colcha...): continuam pequenos para o
#     pós-import marcá-los como probe-lit (no lightmap eles mancham);
#   - objetos ocultos (não são importados) e empties (limpos no final se vazios).
import bpy, re, sys, unicodedata
from collections import defaultdict

argv = sys.argv[sys.argv.index("--") + 1:]
DESTINO = argv[0]

# tecidos: ficam pequenos p/ probes; vid_: transparentes precisam de ordenação
# de profundidade POR OBJETO — fundidos, o vidro fica leitoso/fantasma.
TECIDOS = re.compile(r"24402881|cotton|suede|velvet|boucle|colcha|garment|lencol|^vid_", re.I)
PULAR_COLECOES = {"02_Portas_Janelas"}


def sem_acento(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()


view = bpy.context.view_layer
candidatos = []
for o in view.objects:
    if o.type != 'MESH' or not o.visible_get():
        continue
    colecao = o.users_collection[0].name if o.users_collection else "raiz"
    if colecao in PULAR_COLECOES or "porta" in sem_acento(o.name):
        continue
    if any(s.material and TECIDOS.search(s.material.name) for s in o.material_slots):
        continue
    candidatos.append((colecao, o))

grupos = defaultdict(list)
for colecao, o in candidatos:
    mats = tuple(s.material.name if s.material else "" for s in o.material_slots)
    grupos[(colecao, mats)].append(o)

antes = len([o for o in view.objects if o.type == 'MESH'])
fundidos = 0
for (colecao, mats), objs in sorted(grupos.items()):
    if len(objs) < 2:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    view.objects.active = objs[0]
    bpy.ops.object.make_single_user(type='SELECTED_OBJECTS', object=True, obdata=True)
    bpy.ops.object.join()
    base = re.sub(r"[^A-Za-z0-9_]+", "_", (mats[0] if mats and mats[0] else "sem_mat"))[:40]
    view.objects.active.name = f"M_{colecao}_{base}"
    fundidos += len(objs) - 1

# remove faces duplicadas por posição no mundo (z-fighting): a fusão baka
# transforms nos vértices e faces antes exatamente empatadas passam a piscar.
# Filtro de área (>= 1 cm²) evita falso positivo em micro-geometria densa.
import bmesh

PREC = 5000  # 0,2 mm
vistas_globais = {}
faces_removidas = 0
for o in [x for x in bpy.data.objects if x.type == 'MESH' and x.visible_get()]:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    m = o.matrix_world
    remover = []
    for f in bm.faces:
        if f.calc_area() < 1e-4:
            continue
        chave = frozenset(
            (round((m @ v.co).x * PREC), round((m @ v.co).y * PREC), round((m @ v.co).z * PREC))
            for v in f.verts
        )
        if chave in vistas_globais:
            remover.append(f)
        else:
            vistas_globais[chave] = True
    if remover:
        bmesh.ops.delete(bm, geom=remover, context='FACES_ONLY')
        faces_removidas += len(remover)
        bm.to_mesh(o.data)
    bm.free()
print("DEDUP_FACES|removidas=%d" % faces_removidas)

# remove empties que ficaram sem nenhuma mesh descendente
def tem_mesh(o):
    return o.type == 'MESH' or any(tem_mesh(c) for c in o.children)

removidos = 0
for o in list(view.objects):
    if o.type == 'EMPTY' and not tem_mesh(o):
        bpy.data.objects.remove(o, do_unlink=True)
        removidos += 1

bpy.context.view_layer.update()
depois = len([o for o in bpy.data.objects if o.type == 'MESH'])
print("MERGE|meshes %d -> %d|fundidos=%d|empties_removidos=%d" % (antes, depois, fundidos, removidos))

bpy.ops.wm.save_as_mainfile(filepath=DESTINO, compress=True)
print("SALVO|%s" % DESTINO)
