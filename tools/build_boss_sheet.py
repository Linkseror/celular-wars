#!/usr/bin/env python3
"""Procesa el sprite sheet del jefe Giroscopio Orbital (Cerrado / Abierto).

Elimina el fondo verde croma (#00FF00) preservando los arcos eléctricos cian/violeta
del estado cerrado y el brillo de las bobinas del estado abierto, centra ambos estados
con el mismo radio de casco central y empaqueta una tira 2x1 (512x512 por celda).
"""

from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image

CELL_SIZE = 512
TARGET_CLOSED_DIAMETER = 430


def keep_main_components(rgba: np.ndarray, alpha_thresh: int = 24, min_size: int = 250) -> np.ndarray:
    """Conserva el cuerpo central y los 4 escudos orbitales, limpiando ruido aislado."""
    mask = rgba[:, :, 3] >= alpha_thresh
    h, w = mask.shape
    visited = np.zeros((h, w), dtype=bool)
    keep = np.zeros((h, w), dtype=bool)

    for y in range(h):
        for x in range(w):
            if mask[y, x] and not visited[y, x]:
                q: deque[tuple[int, int]] = deque([(y, x)])
                visited[y, x] = True
                comp: list[tuple[int, int]] = []
                while q:
                    cy, cx = q.popleft()
                    comp.append((cy, cx))
                    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            q.append((ny, nx))
                if len(comp) >= min_size:
                    ys, xs = zip(*comp)
                    keep[ys, xs] = True

    padded = keep.copy()
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            y0, y1 = max(0, dy), min(h, h + dy)
            x0, x1 = max(0, dx), min(w, w + dx)
            padded[y0:y1, x0:x1] |= keep[y0 - dy:y1 - dy, x0 - dx:x1 - dx]

    out = rgba.copy()
    out[~padded] = 0
    return out


def remove_green_screen(img: Image.Image) -> Image.Image:
    """Elimina el fondo verde croma conservando los rayos cian/violeta entre escudos."""
    arr = np.array(img.convert("RGB"), dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]

    max_rb = np.maximum(r, b)
    spill = np.clip(g - max_rb, 0.0, 255.0)

    bg_frac = np.clip((spill - 12.0) / 198.0, 0.0, 1.0)
    alpha = 1.0 - bg_frac
    alpha = np.where(alpha < 0.04, 0.0, alpha)

    is_electric = (b > r + 15.0) & (b > 75.0)
    target_g = np.where(is_electric, np.maximum(max_rb * 0.94, g - bg_frac * 220.0), max_rb)
    new_g = np.where(spill > 12.0, np.minimum(g, np.maximum(target_g, max_rb * 0.90)), g)

    safe_a = np.maximum(alpha, 0.12)
    boost = np.where(bg_frac > 0.15, safe_a, 1.0)
    out_r = np.where(alpha > 0, np.clip(r / boost, 0, 255), 0)
    out_g = np.where(alpha > 0, np.clip(new_g / np.where(is_electric & (bg_frac > 0.15), safe_a * 1.05, 1.0), 0, 255), 0)
    out_b = np.where(alpha > 0, np.clip(b / boost, 0, 255), 0)

    cyan_fix = is_electric & (alpha > 0.04) & (out_g < out_b * 0.85)
    out_g = np.where(cyan_fix, np.clip(out_b * 0.90, 0, 255), out_g)

    mask_zero = alpha <= 0.0
    out_r[mask_zero] = 0
    out_g[mask_zero] = 0
    out_b[mask_zero] = 0

    rgba = np.stack([out_r, out_g, out_b, alpha * 255.0], axis=-1).astype(np.uint8)
    rgba = keep_main_components(rgba)
    return Image.fromarray(rgba, mode="RGBA")


def bbox_of_alpha(img: Image.Image, thresh: int = 180) -> tuple[int, int, int, int]:
    arr = np.array(img)[:, :, 3] >= thresh
    ys, xs = np.where(arr)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def place_in_cell(clean: Image.Image, scale: float) -> Image.Image:
    x0, y0, x1, y1 = bbox_of_alpha(clean)
    cx = (x0 + x1) * 0.5 * scale
    cy = (y0 + y1) * 0.5 * scale

    nw = max(1, round(clean.width * scale))
    nh = max(1, round(clean.height * scale))
    resized = clean.resize((nw, nh), Image.Resampling.LANCZOS)

    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    px = round(CELL_SIZE * 0.5 - cx)
    py = round(CELL_SIZE * 0.5 - cy)
    cell.alpha_composite(resized, (px, py))
    return cell


def build_boss_sheet(src_path: Path, out_path: Path) -> None:
    im = Image.open(src_path)
    w, h = im.size
    mid = w // 2

    closed_clean = remove_green_screen(im.crop((0, 0, mid, h)))
    open_clean = remove_green_screen(im.crop((mid, 0, w, h)))

    cx0, cy0, cx1, cy1 = bbox_of_alpha(closed_clean)
    closed_diam = max(cx1 - cx0, cy1 - cy0)
    scale = TARGET_CLOSED_DIAMETER / float(closed_diam)

    f_closed = place_in_cell(closed_clean, scale)
    f_open = place_in_cell(open_clean, scale)

    sheet = Image.new("RGBA", (CELL_SIZE * 2, CELL_SIZE), (0, 0, 0, 0))
    sheet.paste(f_closed, (0, 0))
    sheet.paste(f_open, (CELL_SIZE, 0))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, "PNG")
    print(f"Boss sprite sheet guardado en {out_path} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parent.parent
    build_boss_sheet(
        repo / "tools/raw/boss_orbital_green.jpg",
        repo / "assets/sprites/boss_giroscopio_sheet.png",
    )
