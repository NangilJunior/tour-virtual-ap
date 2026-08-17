"""Converte a saída do Materialize (.mtz + mapas) para o conjunto que o
StandardMaterial3D da Godot espera.

Feito para `texturas_para_pbr/wallpaper/` (papel de parede de linho do quarto do
casal), onde o Materialize gerou height/metallic/smoothness mas NÃO gerou normal
nem AO. Além disso a saída dele não entra direto na Godot:

- **smoothness x roughness**: a Godot lê rugosidade, o Materialize escreve
  suavidade. Inverter é só metade do trabalho — o mapa dele vem do brilho do
  albedo, então a média cai em ~0.5 (verniz), longe do papel de parede real.
  Aqui a variação é preservada mas recomprimida em volta de uma base fosca.
- **height do Materialize**: neste arquivo veio com 42 níveis de contraste e
  carrega as manchas de iluminação da foto original, o que viraria um normal map
  abaulado. O relevo sai melhor do passa-alta do albedo, mesmo método do
  `gerar_pbr.py`.
- **metallic**: papel de parede é dielétrico; o mapa gerado (média 0.64) é ruído
  do algoritmo e é descartado.

Uso:
    python3 tools/gerar_pbr_materialize.py texturas_para_pbr/wallpaper \\
        --albedo baseColor.jpg --saida assets/textures/papelParedeSuite \\
        --prefixo papelParedeSuite
"""

import argparse
import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, sobel


def normalizar(x):
    lo, hi = float(x.min()), float(x.max())
    return (x - lo) / (hi - lo) if hi > lo else np.zeros_like(x)


def luminancia(caminho):
    a = np.asarray(Image.open(caminho).convert("RGB")).astype(np.float32) / 255.0
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def gerar_altura(lum, sigma):
    """Passa-alta: mantém a trama e descarta o degradê de iluminação da foto."""
    return normalizar(lum - gaussian_filter(lum, sigma=sigma, mode="wrap"))


def gerar_normal(altura, forca):
    dx = sobel(altura, axis=1, mode="wrap")
    dy = sobel(altura, axis=0, mode="wrap")
    nx, ny = -dx * forca, dy * forca  # +Y para cima (normal_map_invert_y=false)
    nz = np.ones_like(altura)
    comp = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / comp, ny / comp, nz / comp], axis=-1) * 0.5 + 0.5
    return (np.clip(rgb, 0.0, 1.0) * 255.0).astype(np.uint8)


def gerar_cavidade(altura):
    cav = np.zeros_like(altura)
    for sigma, peso in ((2.0, 0.6), (8.0, 0.4)):
        media = gaussian_filter(altura, sigma=sigma, mode="wrap")
        cav += np.clip(media - altura, 0.0, None) * peso
    return normalizar(cav)


def gerar_ao(cavidade, intensidade):
    return (np.clip(1.0 - cavidade * intensidade, 0.0, 1.0) * 255.0).astype(np.uint8)


def gerar_rugosidade(caminho_smoothness, base, ganho):
    """1 - suavidade, recentrado na base e com o contraste reduzido pelo ganho."""
    s = luminancia(caminho_smoothness)
    r = 1.0 - s
    r = base + (r - r.mean()) * ganho
    return (np.clip(r, 0.0, 1.0) * 255.0).astype(np.uint8), r


def main():
    p = argparse.ArgumentParser()
    p.add_argument("pasta", help="pasta com a saída do Materialize")
    p.add_argument("--albedo", default="baseColor.jpg")
    p.add_argument("--smoothness", default=None,
                   help="nome dentro da pasta; padrão: o primeiro *_smoothness.png")
    p.add_argument("--saida", required=True)
    p.add_argument("--prefixo", required=True)
    # trama fina de linho: sigma pequeno segura o fio, sigma grande traz de volta
    # as manchas da foto.
    p.add_argument("--passa-alta", type=float, default=8.0)
    # 0.5 dá ~18 graus de inclinação média nesta trama; acima disso o fio vira
    # ruído de specular quando a parede é vista de longe no headset.
    p.add_argument("--forca", type=float, default=0.5)
    p.add_argument("--ao", type=float, default=0.5)
    p.add_argument("--rugosidade", type=float, default=0.85)
    p.add_argument("--ganho-rugosidade", type=float, default=0.35)
    args = p.parse_args()

    albedo = os.path.join(args.pasta, args.albedo)
    smooth = os.path.join(args.pasta, args.smoothness) if args.smoothness else next(
        os.path.join(args.pasta, f) for f in sorted(os.listdir(args.pasta))
        if f.endswith("_smoothness.png"))

    os.makedirs(args.saida, exist_ok=True)
    lum = luminancia(albedo)
    altura = gerar_altura(lum, args.passa_alta)
    cavidade = gerar_cavidade(altura)
    rug, rug_f = gerar_rugosidade(smooth, args.rugosidade, args.ganho_rugosidade)

    saidas = {
        "_normal.png": gerar_normal(altura, args.forca),
        "_ao.png": gerar_ao(cavidade, args.ao),
        "_roughness.png": rug,
    }
    for sufixo, dados in saidas.items():
        caminho = os.path.join(args.saida, args.prefixo + sufixo)
        Image.fromarray(dados).save(caminho)
        print("%-14s %s" % (sufixo, caminho))

    n = saidas["_normal.png"].astype(np.float32) / 255.0 * 2.0 - 1.0
    desvio = np.degrees(np.arccos(np.clip(n[..., 2], -1, 1)))
    print("\ninclinação do normal: média %.1f graus, máx %.1f graus"
          % (desvio.mean(), desvio.max()))
    print("rugosidade: %.2f a %.2f (média %.2f)"
          % (rug_f.min(), rug_f.max(), rug_f.mean()))


main()
