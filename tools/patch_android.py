"""Chỉnh khung Android do `flutter create` sinh ra:
- ký APK bằng khóa cố định trong keys/ (để cài bản mới đè bản cũ mà KHÔNG mất dữ liệu)
- đặt tên app, quyền mở ứng dụng gọi điện / SMS / Zalo
- thay icon app
- nâng phiên bản Kotlin nếu quá cũ
"""
import pathlib
import re
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
android = root / "android"
app = android / "app"

# ---------------------------------------------------------------- ký APK
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"
if kts.exists():
    gradle = kts
    block = '''
    signingConfigs {
        getByName("debug") {
            storeFile = file("../../keys/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
'''
elif groovy.exists():
    gradle = groovy
    block = '''
    signingConfigs {
        debug {
            storeFile file("../../keys/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
'''
else:
    sys.exit("Không tìm thấy android/app/build.gradle(.kts)")

text = gradle.read_text(encoding="utf-8")
if "keys/debug.keystore" not in text:
    text, n = re.subn(r"^android\s*\{\s*$", "android {" + block, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("Không chèn được signingConfigs vào " + gradle.name)
if "signingConfigs.getByName(\"debug\")" not in text and "signingConfigs.debug" not in text:
    print("CẢNH BÁO: buildTypes.release không dùng khóa debug — kiểm tra lại", gradle.name)
gradle.write_text(text, encoding="utf-8")
print("Đã cấu hình khóa ký:", gradle.name)

# ------------------------------------------------------------- Manifest
manifest = app / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")
m = re.sub(r'android:label="[^"]*"', 'android:label="Lớp Toán"', m, count=1)
if "android.intent.action.DIAL" not in m:
    queries = '''
    <queries>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="sms" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>
'''
    m = m.replace("</manifest>", queries + "</manifest>")
manifest.write_text(m, encoding="utf-8")
print("Đã sửa AndroidManifest.xml")

# ----------------------------------------------------------------- Icon
icons = root / "branding" / "icons"
if not icons.exists():
    # Vẽ icon (sổ tay + dấu tích đỏ) nếu chưa có sẵn
    import subprocess
    try:
        from PIL import Image, ImageDraw, ImageFilter
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "pillow"], check=False)
        from PIL import Image, ImageDraw, ImageFilter
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
    for k, v in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = icons / f"mipmap-{k}"
        out.mkdir(parents=True, exist_ok=True)
        img.resize((v, v), Image.LANCZOS).save(out / "ic_launcher.png")
res = app / "src" / "main" / "res"
for d in icons.glob("mipmap-*"):
    target = res / d.name
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(d / "ic_launcher.png", target / "ic_launcher.png")
print("Đã thay icon")

# --------------------------------------------------------------- Kotlin
for name in ("settings.gradle.kts", "settings.gradle"):
    f = android / name
    if not f.exists():
        continue
    s = f.read_text(encoding="utf-8")
    s2 = re.sub(
        r'(id\(?\s*"org\.jetbrains\.kotlin\.android"\s*\)?\s+version\s+")1\.[0-9.]+(")',
        r"\g<1>2.1.0\g<2>",
        s,
    )
    if s2 != s:
        f.write_text(s2, encoding="utf-8")
        print("Đã nâng Kotlin lên 2.1.0 trong", name)
