"""Chỉnh khung Windows do `flutter create` sinh ra: tên cửa sổ, icon, cỡ cửa sổ."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
runner = root / "windows" / "runner"

main_cpp = runner / "main.cpp"
s = main_cpp.read_text(encoding="utf-8")
TITLE = r'window.Create(L"L\u1edbp To\u00e1n \u2013 \u0110i\u1ec3m danh & ch\u1ea5m \u0111i\u1ec3m"'
s = re.sub(r'window\.Create\(L"[^"]*"', lambda m: TITLE, s)
s = re.sub(r"Win32Window::Size size\(\d+, \d+\);", "Win32Window::Size size(1280, 820);", s)
main_cpp.write_text(s, encoding="utf-8")
print("Đã đặt tên cửa sổ")

rc = runner / "Runner.rc"
if rc.exists():
    t = rc.read_text(encoding="utf-8", errors="ignore")
    t = re.sub(r'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "Lop Toan"', t)
    t = re.sub(r'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Lop Toan"', t)
    rc.write_text(t, encoding="utf-8")

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("Thiếu Pillow")

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bot = (37, 70, 160), (20, 36, 90)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
img.paste(grad, (0, 0), mask)
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle([238, 200, 806, 860], radius=60, fill=(0, 0, 0, 110))
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
d = ImageDraw.Draw(img)
d.rounded_rectangle([222, 170, 792, 830], radius=56, fill=(250, 247, 238, 255))
d.line([(330, 190), (330, 812)], fill=(230, 150, 150, 255), width=8)
for y in range(300, 800, 92):
    d.line([(250, y), (764, y)], fill=(170, 195, 235, 255), width=8)
for y in (260, 500, 740):
    d.ellipse([244, y - 16, 276, y + 16], fill=(37, 70, 160, 255))
pts = [(390, 520), (500, 640), (720, 360)]
d.line(pts, fill=(200, 45, 40, 255), width=86, joint="curve")
for q in (pts[0], pts[2]):
    d.ellipse([q[0] - 43, q[1] - 43, q[0] + 43, q[1] + 43], fill=(200, 45, 40, 255))
ico = runner / "resources" / "app_icon.ico"
ico.parent.mkdir(parents=True, exist_ok=True)
img.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("Đã thay icon Windows")
