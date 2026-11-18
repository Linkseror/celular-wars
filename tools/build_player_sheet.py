#!/usr/bin/env python3
"""Procesa los frames del barrel roll de la nave y genera el sprite sheet final.

Convierte el fondo verde croma (#00FF00) en transparencia eliminando el halo verde
en bordes y propulsores, limpia fragmentos sueltos en los recortes, alinea todos
los fotogramas respecto al casco de la nave y empaqueta los 8 ángulos (0°..315°)
en una tira horizontal 8x1.
"""

from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image

FRAME_SIZE = 256
SHIP_TARGET_HEIGHT = 184  # Deja margen superior e inferior para los propulsores.


def keep_main_component(rgba: np.ndarray, alpha_thresh: int = 24) -> np.ndarray:
    """Elimina cualquier fragmento desconectado en los bordes del recorte."""
    mask = rgba[:, :, 3] >= alpha_thresh
    h, w = mask.shape
    visited = np.zeros((h, w), dtype=bool)
    best_comp: list[tuple[int, int]] = []

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
                if len(comp) > len(best_comp):
                    best_comp = comp

    keep = np.zeros((h, w), dtype=bool)
    if best_comp:
        ys, xs = zip(*best_comp)
        keep[ys, xs] = True
        # Expandimos 4px alrededor del componente principal para conservar bordes suaves.
        padded = keep.copy()
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                y0, y1 = max(0, dy), min(h, h + dy)
                x0, x1 = max(0, dx), min(w, w + dx)
                padded[y0:y1, x0:x1] |= keep[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
        keep = padded

    out = rgba.copy()
    out[~keep] = 0
    return out


def remove_green_screen(img: Image.Image) -> Image.Image:
    """Elimina el fondo verde croma conservando el brillo cian de los propulsores."""
    arr = np.array(img.convert("RGB"), dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]

    max_rb = np.maximum(r, b)
    spill = np.clip(g - max_rb, 0.0, 255.0)

    # Fracción estimada de fondo verde (~245).
    bg_frac = np.clip((spill - 12.0) / 200.0, 0.0, 1.0)
    alpha = 1.0 - bg_frac
    alpha = np.where(alpha < 0.04, 0.0, alpha)

    # Des-contaminación de verde: si hay azul dominante (llama cian), mantenemos el G alto
    # respecto a B para que no vire a violeta/magenta.
    is_cyan_glow = (b > r + 20.0) & (b > 70.0)
    target_g = np.where(is_cyan_glow, np.maximum(max_rb * 0.96, g - bg_frac * 220.0), max_rb)
    new_g = np.where(spill > 12.0, np.minimum(g, np.maximum(target_g, max_rb * 0.92)), g)

    # En la llama cian con algo de fondo verde, potenciamos ligeramente B/G para mantener cian limpio.
    safe_a = np.maximum(alpha, 0.12)
    boost = np.where(bg_frac > 0.15, safe_a, 1.0)
    out_r = np.where(alpha > 0, np.clip(r / boost, 0, 255), 0)
    out_g = np.where(alpha > 0, np.clip(new_g / np.where(is_cyan_glow & (bg_frac > 0.15), safe_a * 1.05, 1.0), 0, 255), 0)
    out_b = np.where(alpha > 0, np.clip(b / boost, 0, 255), 0)

    # Si un píxel de llama cian quedó con G < B*0.85 tras des-spill, lo reequilibramos a cian.
    cyan_fix = is_cyan_glow & (alpha > 0.04) & (out_g < out_b * 0.88)
    out_g = np.where(cyan_fix, np.clip(out_b * 0.92, 0, 255), out_g)

    mask_zero = alpha <= 0.0
    out_r[mask_zero] = 0
    out_g[mask_zero] = 0
    out_b[mask_zero] = 0

    rgba = np.stack([out_r, out_g, out_b, alpha * 255.0], axis=-1).astype(np.uint8)
    rgba = keep_main_component(rgba)
    return Image.fromarray(rgba, mode="RGBA")


def find_hull_bounds(rgba_img: Image.Image) -> tuple[int, int, int, int]:
    """Encuentra el bounding box del casco sólido (ignorando el humo suave del propulsor)."""
    arr = np.array(rgba_img)
    solid = arr[:, :, 3] >= 220
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    is_flame = (r < 120) & (g > 175) & (b > 210)
    hull = solid & (~is_flame)
    ys, xs = np.where(hull)
    if len(ys) == 0:
        ys, xs = np.where(arr[:, :, 3] > 20)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def normalize_frame(raw_crop: Image.Image) -> Image.Image:
    """Quita fondo, escala el casco a altura uniforme y centra horizontalmente."""
    clean = remove_green_screen(raw_crop)
    hx0, hy0, hx1, hy1 = find_hull_bounds(clean)
    hull_h = hy1 - hy0
    scale = SHIP_TARGET_HEIGHT / float(hull_h)

    new_w = max(1, round(clean.width * scale))
    new_h = max(1, round(clean.height * scale))
    resized = clean.resize((new_w, new_h), Image.Resampling.LANCZOS)

    shx0 = hx0 * scale
    shx1 = hx1 * scale
    shy0 = hy0 * scale
    shy1 = hy1 * scale

    hull_cx = (shx0 + shx1) * 0.5
    hull_cy = (shy0 + shy1) * 0.5

    target_cx = FRAME_SIZE * 0.5
    target_cy = FRAME_SIZE * 0.45

    paste_x = round(target_cx - hull_cx)
    paste_y = round(target_cy - hull_cy)

    cell = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    cell.alpha_composite(resized, (paste_x, paste_y))
    return cell


def build_sheet(sheet_main_path: Path, sheet_angles_path: Path, out_path: Path) -> None:
    main_im = Image.open(sheet_main_path)
    mw, mh = main_im.size
    mcw, mch = mw // 4, mh // 2

    angles_im = Image.open(sheet_angles_path)
    aw, ah = angles_im.size

    raw_000 = main_im.crop((0, 0, mcw, mch))
    raw_090 = main_im.crop((2 * mcw, 0, 3 * mcw - 14, mch))
    raw_180 = main_im.crop((0, mch, mcw, mh))

    raw_045 = angles_im.crop((0, 0, aw // 2, ah))
    raw_225 = angles_im.crop((aw // 2, 0, aw, ah))

    f_000 = normalize_frame(raw_000)
    f_045 = normalize_frame(raw_045)
    f_090 = normalize_frame(raw_090)
    f_225 = normalize_frame(raw_225)
    f_180 = normalize_frame(raw_180)

    # Simetría bilateral para completar los 360° de forma coherente.
    f_135 = f_225.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    f_270 = f_090.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    f_315 = f_045.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    frames = [f_000, f_045, f_090, f_135, f_180, f_225, f_270, f_315]
    sheet = Image.new("RGBA", (FRAME_SIZE * len(frames), FRAME_SIZE), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * FRAME_SIZE, 0))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, "PNG")
    print(f"Sprite sheet guardado en {out_path} ({sheet.width}x{sheet.height}, {len(frames)} frames)")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parent.parent
    build_sheet(
        repo / "tools/raw/player_base_views.jpg",
        repo / "tools/raw/player_roll_angles.jpg",
        repo / "assets/sprites/player_ship_sheet.png",
    )
