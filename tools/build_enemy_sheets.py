#!/usr/bin/env python3
"""Procesa los sprite sheets del primer enemigo básico:
- Regular (Opción B: Hematíe Parásito Mecánico) -> assets/sprites/enemy_globulo_regular_sheet.png
- Élite   (Opción A: Eritrocito Ciber-Injerto)   -> assets/sprites/enemy_globulo_elite_sheet.png
"""

from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image

CELL_SIZE = 256
TARGET_BODY_SIZE = 174


def remove_green_screen(img: Image.Image, outer_only: bool = False) -> Image.Image:
    """Elimina el fondo verde (#00FF00).

    Si `outer_only=True`, inunda solo desde el exterior para conservar las venas
    verde-neón en el interior de la Opción A (Élite). Si `outer_only=False`, limpia
    también los huecos interiores entre las pinzas mecánicas de la Opción B (Regular).
    """
    arr = np.array(img.convert("RGB"), dtype=np.float32)
    h, w, _ = arr.shape
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    max_rb = np.maximum(r, b)
    spill = np.clip(g - max_rb, 0.0, 255.0)

    if outer_only:
        is_green_bg = (spill > 38.0) & (g > 110.0)
        ext_bg = np.zeros((h, w), dtype=bool)
        q: deque[tuple[int, int]] = deque()
        for x in range(w):
            for y in (0, h - 1):
                if is_green_bg[y, x] and not ext_bg[y, x]:
                    ext_bg[y, x] = True
                    q.append((y, x))
        for y in range(h):
            for x in (0, w - 1):
                if is_green_bg[y, x] and not ext_bg[y, x]:
                    ext_bg[y, x] = True
                    q.append((y, x))

        while q:
            cy, cx = q.popleft()
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and not ext_bg[ny, nx] and is_green_bg[ny, nx]:
                    ext_bg[ny, nx] = True
                    q.append((ny, nx))

        zone = ext_bg.copy()
        for _ in range(3):
            nxt = zone.copy()
            nxt[1:, :] |= zone[:-1, :]
            nxt[:-1, :] |= zone[1:, :]
            nxt[:, 1:] |= zone[:, :-1]
            nxt[:, :-1] |= zone[:, 1:]
            zone = nxt
    else:
        zone = np.ones((h, w), dtype=bool)

    bg_frac = np.where(zone, np.clip((spill - 12.0) / 195.0, 0.0, 1.0), 0.0)
    alpha = 1.0 - bg_frac
    alpha = np.where(alpha < 0.05, 0.0, alpha)

    is_cyan_glow = (b > r + 20.0) & (b > 90.0)
    target_g = np.where(is_cyan_glow, np.maximum(max_rb * 0.94, g - bg_frac * 220.0), max_rb)
    new_g = np.where(zone & (spill > 12.0), np.minimum(g, np.maximum(target_g, max_rb * 0.90)), g)

    safe_a = np.maximum(alpha, 0.12)
    boost = np.where(zone & (bg_frac > 0.15), safe_a, 1.0)

    out_r = np.where(alpha > 0, np.clip(r / boost, 0, 255), 0)
    out_g = np.where(alpha > 0, np.clip(new_g, 0, 255), 0)
    out_b = np.where(alpha > 0, np.clip(b / boost, 0, 255), 0)

    mask_zero = alpha <= 0.0
    out_r[mask_zero] = 0
    out_g[mask_zero] = 0
    out_b[mask_zero] = 0

    rgba = np.stack([out_r, out_g, out_b, alpha * 255.0], axis=-1).astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA")


def find_hull_bbox(rgba_img: Image.Image) -> tuple[int, int, int, int]:
    """Calcula el bounding box del cuerpo sólido ignorando el fogonazo inferior."""
    arr = np.array(rgba_img)
    solid = arr[:, :, 3] >= 210
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    is_muzzle_glow = ((r > 190) & (b > 220) & (g < 170)) | ((g > 210) & (b > 200) & (r < 120))
    hull = solid & (~is_muzzle_glow)
    ys, xs = np.where(hull)
    if len(ys) == 0:
        ys, xs = np.where(solid)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def place_in_cell(clean: Image.Image, scale: float) -> Image.Image:
    x0, y0, x1, y1 = find_hull_bbox(clean)
    cx = (x0 + x1) * 0.5 * scale
    cy = (y0 + y1) * 0.5 * scale

    nw = max(1, round(clean.width * scale))
    nh = max(1, round(clean.height * scale))
    resized = clean.resize((nw, nh), Image.Resampling.LANCZOS)

    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    px = round(CELL_SIZE * 0.5 - cx)
    py = round(CELL_SIZE * 0.48 - cy)
    cell.alpha_composite(resized, (px, py))
    return cell


def build_enemy_sheet(src_path: Path, out_path: Path, outer_only: bool = False) -> None:
    im = Image.open(src_path)
    w, h = im.size
    mid = w // 2

    idle_clean = remove_green_screen(im.crop((0, 0, mid, h)), outer_only=outer_only)
    fire_clean = remove_green_screen(im.crop((mid, 0, w, h)), outer_only=outer_only)

    x0, y0, x1, y1 = find_hull_bbox(idle_clean)
    body_w = x1 - x0
    scale = TARGET_BODY_SIZE / float(body_w)

    f_idle = place_in_cell(idle_clean, scale)
    f_fire = place_in_cell(fire_clean, scale)

    sheet = Image.new("RGBA", (CELL_SIZE * 2, CELL_SIZE), (0, 0, 0, 0))
    sheet.paste(f_idle, (0, 0))
    sheet.paste(f_fire, (CELL_SIZE, 0))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, "PNG")
    print(f"Enemy sprite sheet guardado en {out_path} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parent.parent
    build_enemy_sheet(
        repo / "tools/raw/enemy_b_regular_green.jpg",
        repo / "assets/sprites/enemy_globulo_regular_sheet.png",
        outer_only=False,
    )
    build_enemy_sheet(
        repo / "tools/raw/enemy_a_elite_green.jpg",
        repo / "assets/sprites/enemy_globulo_elite_sheet.png",
        outer_only=True,
    )
