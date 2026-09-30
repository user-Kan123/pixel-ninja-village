# -*- coding: utf-8 -*-
"""生成村内"地形 / 自然物"贴图（公园 / 演习场 / 森林 / 陵园 / 石碑 / 码头 / 火影岩）。

建筑贴图来自 AI 生成 + process_building_sprites.py；这七种是俯视地形物，
没有可用的图像生成工具时用 PIL 手绘，调色板与描边对齐现有建筑贴图。

跑法（在 WSL 里）：python3 tools/make_nature_sprites.py
输出：assets/buildings/<style>.png，最长边 ≤ 1024，像素块 4 倍放大（NEAREST）
"""
import os
import random
from PIL import Image, ImageDraw

OUT = "/mnt/d/Work/xiangsurencun/pixel-ninja-village/assets/buildings"
SCALE = 4

# ---------------------------------------------------------------- 调色板
GRASS = (61, 92, 58)
GRASS_L = (76, 124, 71)
GRASS_D = (44, 71, 43)
DIRT = (138, 122, 88)
DIRT_L = (162, 144, 106)
DIRT_D = (106, 93, 66)
WOOD = (106, 79, 48)
WOOD_L = (148, 114, 72)
WOOD_D = (70, 52, 30)
STONE = (150, 150, 144)
STONE_L = (188, 188, 180)
STONE_D = (104, 104, 98)
ROCK = (122, 112, 96)
ROCK_L = (150, 140, 122)
ROCK_D = (92, 84, 70)
WATER = (63, 127, 168)
WATER_L = (108, 176, 212)
LEAF = (47, 82, 48)
LEAF_L = (64, 106, 58)
LEAF_D = (32, 58, 34)
RED = (168, 60, 52)
OUTLINE = (40, 36, 32)


def canvas(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name):
    big = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    path = os.path.join(OUT, name + ".png")
    big.save(path, optimize=True)
    print("[OK] %-10s %dx%d  %d KB" % (name, big.width, big.height, os.path.getsize(path) // 1024))


def grass(d, w, h, rnd, base=GRASS):
    d.rectangle([0, 0, w - 1, h - 1], fill=base)
    for _ in range(w * h // 16):
        x, y = rnd.randrange(w), rnd.randrange(h)
        d.point((x, y), fill=GRASS_L if rnd.random() < 0.5 else GRASS_D)


def tree_top(d, cx, cy, r):
    """俯视树冠：几个圆叠出不规则轮廓（同心圆会像靶子）"""
    rnd = random.Random(cx * 31 + cy * 17 + r * 7)
    for _ in range(3):
        ox = cx + rnd.randint(-r // 3, r // 3)
        oy = cy + rnd.randint(-r // 3, r // 3)
        d.ellipse([ox - r, oy - r + 1, ox + r, oy + r + 1], fill=OUTLINE)
    for _ in range(3):
        ox = cx + rnd.randint(-r // 3, r // 3)
        oy = cy + rnd.randint(-r // 3, r // 3)
        d.ellipse([ox - r + 1, oy - r + 2, ox + r - 1, oy + r], fill=LEAF)
    for _ in range(2):
        ox = cx - r // 3 + rnd.randint(-r // 4, r // 4)
        oy = cy - r // 3 + rnd.randint(-r // 4, r // 4)
        d.ellipse([ox - r // 2, oy - r // 2, ox + r // 2, oy + r // 2], fill=LEAF_L)
    for _ in range(max(1, r // 4)):
        d.point((cx - r // 3 + rnd.randint(-r // 3, r // 3),
                 cy - r // 3 + rnd.randint(-r // 3, r // 3)), fill=(96, 140, 82))


def bush(d, cx, cy, r):
    d.ellipse([cx - r, cy - r + 1, cx + r, cy + r + 1], fill=OUTLINE)
    d.ellipse([cx - r + 1, cy - r + 2, cx + r - 1, cy + r], fill=LEAF_L)
    d.ellipse([cx - r + 2, cy - r + 3, cx + r - 3, cy + r - 2], fill=(76, 120, 66))


# ---------------------------------------------------------------- 公园
def make_park():
    w, h = 168, 104
    rnd = random.Random(11)
    img, d = canvas(w, h)
    grass(d, w, h, rnd)
    # 碎石小径：一条横穿的弯道
    path_pts = [(0, 62), (26, 58), (54, 62), (82, 56), (110, 60), (140, 54), (167, 58)]
    for i in range(len(path_pts) - 1):
        d.line([path_pts[i], path_pts[i + 1]], fill=DIRT_D, width=11)
        d.line([path_pts[i], path_pts[i + 1]], fill=DIRT, width=9)
    for _ in range(90):
        x, y = rnd.randrange(w), rnd.randrange(h)
        if 52 < y < 68:
            d.point((x, y), fill=DIRT_L)
    # 水池（靠右上）
    d.ellipse([86, 12, 152, 50], fill=OUTLINE)
    d.ellipse([88, 14, 150, 48], fill=STONE)
    d.ellipse([90, 16, 148, 46], fill=WATER)
    d.ellipse([94, 19, 132, 34], fill=WATER_L)
    d.ellipse([96, 18, 144, 30], fill=(150, 208, 232))
    # 长椅
    for bx, by in [(30, 74), (66, 40)]:
        d.rectangle([bx, by, bx + 18, by + 4], fill=OUTLINE)
        d.rectangle([bx + 1, by + 1, bx + 17, by + 3], fill=WOOD_L)
        d.rectangle([bx + 3, by + 4, bx + 5, by + 6], fill=WOOD_D)
        d.rectangle([bx + 13, by + 4, bx + 15, by + 6], fill=WOOD_D)
    # 树与灌木
    for tx, ty, r in [(18, 26, 13), (54, 16, 11), (120, 76, 12), (152, 84, 10), (96, 88, 11)]:
        tree_top(d, tx, ty, r)
    for bx, by, r in [(44, 84, 6), (140, 26, 5), (10, 88, 5)]:
        bush(d, bx, by, r)
    # 花点
    for _ in range(40):
        x, y = rnd.randrange(w), rnd.randrange(h)
        if img.getpixel((x, y)) in (GRASS, GRASS_L, GRASS_D):
            col = (222, 168, 196) if rnd.random() < 0.5 else (238, 220, 140)
            d.point((x, y), fill=col)
    save(img, "park")


# ---------------------------------------------------------------- 演习场
def make_training():
    w, h = 176, 112
    rnd = random.Random(23)
    img, d = canvas(w, h)
    grass(d, w, h, rnd)
    # 夯土地面
    d.rectangle([14, 16, w - 15, h - 17], fill=DIRT_D)
    d.rectangle([16, 18, w - 17, h - 19], fill=DIRT)
    for _ in range(220):
        x, y = rnd.randrange(17, w - 17), rnd.randrange(19, h - 19)
        d.point((x, y), fill=DIRT_L if rnd.random() < 0.5 else DIRT_D)
    # 围栏：上下两排木桩
    for x in range(16, w - 16, 10):
        for y in (12, h - 14):
            d.rectangle([x, y, x + 3, y + 8], fill=WOOD_D)
            d.rectangle([x, y, x + 2, y + 6], fill=WOOD)
    # 三根木桩（带影子）
    for px, py in [(46, 58), (86, 52), (128, 60)]:
        ## 生土是不透明的，阴影必须是实色，否则会把地表打穿
        d.ellipse([px - 9, py + 10, px + 9, py + 17], fill=(108, 95, 66))
        d.rectangle([px - 5, py - 20, px + 5, py + 12], fill=OUTLINE)
        d.rectangle([px - 4, py - 19, px + 4, py + 11], fill=WOOD)
        d.rectangle([px - 4, py - 19, px - 1, py + 11], fill=WOOD_L)
        d.ellipse([px - 5, py - 24, px + 5, py - 15], fill=WOOD_L)
    # 靶子
    d.ellipse([146, 34, 168, 56], fill=OUTLINE)
    d.ellipse([147, 35, 167, 55], fill=(226, 220, 206))
    d.ellipse([152, 40, 162, 50], fill=RED)
    d.ellipse([155, 43, 159, 47], fill=(238, 234, 224))
    # 地面刮痕
    for _ in range(26):
        x, y = rnd.randrange(20, w - 22), rnd.randrange(24, h - 24)
        d.line([(x, y), (x + rnd.randint(3, 7), y + rnd.choice([-1, 0, 1]))], fill=DIRT_D)
    save(img, "training")


# ---------------------------------------------------------------- 森林
def make_forest():
    w = h = 128
    rnd = random.Random(37)
    img, d = canvas(w, h)
    d.rectangle([0, 0, w - 1, h - 1], fill=LEAF_D)
    # 一层深色底树冠
    for _ in range(70):
        tree_top(d, rnd.randrange(w), rnd.randrange(h), rnd.randint(7, 12))
    # 两层亮色树冠压上去，形成层次
    for _ in range(46):
        tree_top(d, rnd.randrange(w), rnd.randrange(h), rnd.randint(6, 10))
    # 小块空地
    for cx, cy, r in [(34, 96, 8), (98, 30, 7)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GRASS_D)
        d.ellipse([cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2], fill=GRASS)
    save(img, "forest")


# ---------------------------------------------------------------- 陵园
def make_cemetery():
    w, h = 152, 106
    rnd = random.Random(53)
    img, d = canvas(w, h)
    grass(d, w, h, rnd, base=GRASS_D)
    for _ in range(w * h // 20):
        x, y = rnd.randrange(w), rnd.randrange(h)
        d.point((x, y), fill=GRASS)
    # 中央小路
    d.rectangle([70, 0, 80, h - 1], fill=DIRT_D)
    d.rectangle([72, 0, 78, h - 1], fill=DIRT)
    # 两排墓碑
    for row_y in (30, 72):
        for i in range(5):
            mx = 14 + i * 27
            if 60 < mx < 92:
                continue
            d.ellipse([mx - 9, row_y + 12, mx + 13, row_y + 20], fill=(40, 66, 40))
            d.rectangle([mx, row_y, mx + 12, row_y + 16], fill=STONE_D)
            d.rectangle([mx + 1, row_y - 3, mx + 10, row_y + 14], fill=STONE)
            d.ellipse([mx + 1, row_y - 9, mx + 10, row_y + 3], fill=STONE_L)
            d.rectangle([mx + 3, row_y - 4, mx + 8, row_y + 1], fill=STONE_D)
    for bx, by, r in [(24, 92, 6), (126, 18, 5), (130, 92, 6)]:
        bush(d, bx, by, r)
    save(img, "cemetery")


# ---------------------------------------------------------------- 石碑
def make_stone():
    w, h = 64, 88
    img, d = canvas(w, h)
    # 影子
    d.ellipse([10, 74, 54, 84], fill=(0, 0, 0, 60))
    # 基座
    d.rectangle([12, 66, 52, 78], fill=STONE_D)
    d.rectangle([14, 64, 50, 76], fill=STONE)
    d.rectangle([14, 64, 50, 68], fill=STONE_L)
    # 碑身
    d.rectangle([18, 16, 46, 66], fill=OUTLINE)
    d.rectangle([20, 18, 44, 64], fill=STONE)
    d.rectangle([20, 18, 26, 64], fill=STONE_L)
    d.rectangle([38, 18, 44, 64], fill=STONE_D)
    d.ellipse([20, 12, 44, 26], fill=STONE)
    d.ellipse([20, 12, 30, 26], fill=STONE_L)
    # 刻字（三道横刻痕）
    for i in range(3):
        y = 30 + i * 9
        d.line([(28, y), (40, y)], fill=STONE_D)
    save(img, "stone")


# ---------------------------------------------------------------- 码头
def make_wharf():
    w, h = 136, 92
    rnd = random.Random(71)
    img, d = canvas(w, h)
    # 水面
    d.rectangle([0, 0, w - 1, h - 1], fill=WATER)
    for _ in range(150):
        x, y = rnd.randrange(w), rnd.randrange(h)
        d.point((x, y), fill=WATER_L if rnd.random() < 0.5 else (48, 104, 142))
    # 木板平台
    d.rectangle([12, 20, w - 13, h - 21], fill=WOOD_D)
    d.rectangle([14, 22, w - 15, h - 23], fill=WOOD)
    for x in range(16, w - 15, 7):
        d.line([(x, 22), (x, h - 24)], fill=WOOD_D)
    for _ in range(60):
        x, y = rnd.randrange(15, w - 16), rnd.randrange(23, h - 24)
        d.point((x, y), fill=WOOD_L)
    # 立柱
    for px in (16, w - 19):
        for py in (18, h - 26):
            d.rectangle([px, py, px + 4, py + 10], fill=OUTLINE)
            d.rectangle([px + 1, py + 1, px + 3, py + 9], fill=WOOD_L)
    # 缆绳
    d.line([(20, 20), (w - 18, 24)], fill=(196, 186, 150), width=1)
    # 水花
    for _ in range(18):
        x = rnd.randrange(w)
        y = rnd.choice([8, 14, h - 12, h - 6])
        d.point((x, y), fill=(214, 236, 246))
    save(img, "wharf")


# ---------------------------------------------------------------- 火影岩
def make_hokage_rock():
    ## 火影岩在场景里是一条很宽的横带（约 6:1），所以这里也画得宽一些，
    ## 拉伸时才不会把四张脸压扁
    w, h = 448, 88
    rnd = random.Random(97)
    img, d = canvas(w, h)
    # 岩体：几团错落的石块堆出崖壁
    for cx, cy, r, col in [
        (40, 62, 40, ROCK_D), (130, 52, 46, ROCK), (225, 60, 44, ROCK_D),
        (315, 50, 46, ROCK), (405, 62, 42, ROCK_D),
    ]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    for cx, cy, r in [(85, 54, 34), (170, 46, 32), (260, 52, 34), (350, 48, 32)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ROCK_L)
    for _ in range(520):
        x, y = rnd.randrange(w), rnd.randrange(18, h)
        d.point((x, y), fill=ROCK_D if rnd.random() < 0.5 else ROCK)
    # 四张凿出来的脸
    for fx in (62, 172, 282, 392):
        d.ellipse([fx - 19, 32, fx + 19, 72], fill=(96, 88, 74))
        d.ellipse([fx - 17, 30, fx + 17, 68], fill=(132, 124, 108))
        d.ellipse([fx - 15, 32, fx + 15, 64], fill=(196, 188, 168))
        # 头发
        d.rectangle([fx - 16, 30, fx + 16, 38], fill=(96, 90, 78))
        # 眼 / 鼻 / 嘴
        d.rectangle([fx - 9, 43, fx - 3, 47], fill=(74, 68, 60))
        d.rectangle([fx + 3, 43, fx + 9, 47], fill=(74, 68, 60))
        d.rectangle([fx - 2, 48, fx + 2, 56], fill=(160, 152, 134))
        d.line([(fx - 7, 60), (fx + 7, 60)], fill=(74, 68, 60))
    # 底部台沿
    d.rectangle([0, h - 12, w - 1, h - 1], fill=ROCK_D)
    for _ in range(260):
        x = rnd.randrange(w)
        d.point((x, rnd.randrange(h - 11, h)), fill=(74, 68, 58))
    save(img, "hokage_rock")


def main():
    os.makedirs(OUT, exist_ok=True)
    make_park()
    make_training()
    make_forest()
    make_cemetery()
    make_stone()
    make_wharf()
    make_hokage_rock()


if __name__ == "__main__":
    main()
