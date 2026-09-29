# -*- coding: utf-8 -*-
"""把 raw/ 里的 AI 生成贴图裁剪、缩放、重命名成游戏可用的建筑贴图。"""
import os
from PIL import Image

RAW = r"D:\Work\xiangsurencun\pixel-ninja-village\assets\buildings\raw"
OUT = r"D:\Work\xiangsurencun\pixel-ninja-village\assets\buildings"
MAX_DIM = 640  # 输出最长边

# 原始时间戳文件名 -> 建筑贴图名（style 名对齐 VillageArt）
MAPPING = {
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-23-53.png": "hokage_office",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-23-39.png": "office",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-23-34.png": "house",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-23-40.png": "apartment",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-27-30.png": "shop",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-24-34.png": "tools",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-27-32.png": "ramen",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-24-38.png": "hospital",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-24-37.png": "school",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-24-40.png": "tower",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-27-37.png": "clan",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-25-23.png": "vault",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-25-24.png": "watch",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-25-29.png": "bath",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T02-25-22.png": "theater",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T03-23-46.png": "house2",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T03-23-56.png": "house3",
    "16_bit_pixel_art_game_sprite_o_2026-09-29T03-23-50.png": "shop2",
}

def main():
    os.makedirs(OUT, exist_ok=True)
    for fname, name in MAPPING.items():
        src = os.path.join(RAW, fname)
        if not os.path.exists(src):
            print(f"[MISS] {fname}")
            continue
        img = Image.open(src).convert("RGBA")
        # 先缩放：棋盘格假透明背景会被模糊成均匀浅色，方便 flood-fill 抠图
        w, h = img.size
        scale = MAX_DIM / max(w, h)
        if scale < 1.0:
            img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
        # 从边缘多点 flood-fill 抠背景（建筑有深色描边，填充不会进入建筑内部）
        from PIL import ImageDraw
        w2, h2 = img.size
        seeds = [(0, 0), (w2 - 1, 0), (0, h2 - 1), (w2 - 1, h2 - 1),
                 (w2 // 2, 0), (w2 // 2, h2 - 1), (0, h2 // 2), (w2 - 1, h2 // 2)]
        for seed in seeds:
            try:
                ImageDraw.floodfill(img, seed, (0, 0, 0, 0), thresh=110)
            except Exception:
                pass
        # 裁剪到不透明内容的包围盒
        bbox = img.getbbox()
        if bbox is None:
            print(f"[EMPTY] {fname}")
            continue
        img = img.crop(bbox)
        # 检查透明度占比
        alpha = img.getchannel("A")
        transparent_ratio = sum(1 for a in alpha.getdata() if a < 16) / (img.size[0] * img.size[1])
        dst = os.path.join(OUT, f"{name}.png")
        img.save(dst, optimize=True)
        print(f"[OK] {name}: {img.size[0]}x{img.size[1]}, 透明占比 {transparent_ratio:.0%}, {os.path.getsize(dst)//1024} KB")

if __name__ == "__main__":
    main()
