"""Deriva os mapas PBR que faltam (altura, normal, AO, rugosidade) de uma textura
de albedo.

Feito para o `assets/textures/wall/wall.jpg` (reboco batido), que estava entrando
no `parede_greige.tres` só como albedo — sem normal, a parede fica lisa demais e
destoa das vizinhas, que usam o `lightwall.tres` (albedo + normal + AO).

Método
------
1. **Altura**: luminância do albedo passada por um filtro passa-alta (subtrai um
   desfoque gaussiano largo). Isso tira o gradiente de iluminação da foto
   original — sem esse passo o normal map ganha uma inclinação global falsa e a
   parede parece abaulada.
2. **Normal**: gradiente Sobel da altura, montado em tangent space (+Y para
   cima, convenção do Godot com `normal_map_invert_y=false`).
3. **AO**: cavidade = quanto a altura local está abaixo da média da vizinhança,
   em duas escalas, só na parte escura (fendas ocluem, ressaltos não).
4. **Rugosidade**: base constante com uma modulação leve pela cavidade — o fundo
   das fendas do reboco espalha mais que os ressaltos.

Todos os filtros usam `mode="wrap"`, então o resultado continua seamless se o
albedo for.

Uso:
    python3 tools/gerar_pbr.py assets/textures/wall/wall.jpg
    python3 tools/gerar_pbr.py <albedo> --forca 1.4 --rugosidade 0.85
"""

import argparse
import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, sobel


def carregar_luminancia(caminho):
    img = Image.open(caminho).convert("RGB")
    a = np.asarray(img).astype(np.float32) / 255.0
    # Rec. 709
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722, img.size


def normalizar(x):
    lo, hi = float(x.min()), float(x.max())
    return (x - lo) / (hi - lo) if hi > lo else np.zeros_like(x)


def gerar_altura(lum, raio_passa_alta):
    """Passa-alta: mantém o relevo fino e descarta a iluminação de fundo."""
    fundo = gaussian_filter(lum, sigma=raio_passa_alta, mode="wrap")
    return normalizar(lum - fundo)


def gerar_normal(altura, forca):
    # Sobel devolve a derivada; o sinal de X é invertido para a convenção
    # OpenGL/Godot (canal vermelho cresce para a direita).
    dx = sobel(altura, axis=1, mode="wrap")
    dy = sobel(altura, axis=0, mode="wrap")
    nx = -dx * forca
    ny = dy * forca
    nz = np.ones_like(altura)
    comp = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / comp, ny / comp, nz / comp
    rgb = np.stack([nx, ny, nz], axis=-1) * 0.5 + 0.5
    return (np.clip(rgb, 0.0, 1.0) * 255.0).astype(np.uint8)


def gerar_cavidade(altura):
    """Quanto cada ponto está abaixo da vizinhança, em duas escalas."""
    cav = np.zeros_like(altura)
    for sigma, peso in ((2.0, 0.6), (8.0, 0.4)):
        media = gaussian_filter(altura, sigma=sigma, mode="wrap")
        cav += np.clip(media - altura, 0.0, None) * peso
    return normalizar(cav)


def gerar_ao(cavidade, intensidade):
    ao = 1.0 - cavidade * intensidade
    return (np.clip(ao, 0.0, 1.0) * 255.0).astype(np.uint8)


def gerar_rugosidade(cavidade, base, variacao):
    r = base + (cavidade - 0.5) * 2.0 * variacao
    return (np.clip(r, 0.0, 1.0) * 255.0).astype(np.uint8)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("albedo")
    # 0.6 dá ~15 graus de inclinação média no wall.jpg — relevo de reboco
    # visível em rasante sem virar casca de tartaruga. Acima de ~1.0 a média
    # passa de 20 graus e a parede começa a parecer estuque grosso.
    p.add_argument("--forca", type=float, default=0.6,
                   help="intensidade do relevo no normal map")
    p.add_argument("--passa-alta", type=float, default=24.0,
                   help="sigma do desfoque que remove a iluminação de fundo")
    p.add_argument("--ao", type=float, default=0.55, help="intensidade da oclusão")
    p.add_argument("--rugosidade", type=float, default=0.85)
    p.add_argument("--variacao-rugosidade", type=float, default=0.06)
    args = p.parse_args()

    lum, tamanho = carregar_luminancia(args.albedo)
    base = os.path.splitext(args.albedo)[0]

    altura = gerar_altura(lum, args.passa_alta)
    cavidade = gerar_cavidade(altura)

    saidas = {
        "_height.png": (altura * 255.0).astype(np.uint8),
        "_normal.png": gerar_normal(altura, args.forca),
        "_ao.png": gerar_ao(cavidade, args.ao),
        "_roughness.png": gerar_rugosidade(cavidade, args.rugosidade,
                                           args.variacao_rugosidade),
    }
    for sufixo, dados in saidas.items():
        caminho = base + sufixo
        Image.fromarray(dados).save(caminho)
        print("%-14s %s  %s" % (sufixo, caminho, tamanho))

    n = saidas["_normal.png"].astype(np.float32) / 255.0 * 2.0 - 1.0
    desvio = np.degrees(np.arccos(np.clip(n[..., 2], -1, 1)))
    print("\ninclinação do normal: média %.1f graus, máx %.1f graus"
          % (desvio.mean(), desvio.max()))


main()
