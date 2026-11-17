#!/usr/bin/env python3
"""convert.py — конвертація файлів для кільця Edots (services/ConvertService).

  convert.py kinds
      типи й формати кільця: {"kinds": {kind: [ext…]}, "formats": {kind: [{id,label}…]}}

  convert.py sizes KIND FILE…
      що вийде з цих файлів у кожному форматі KIND: {"now": байти, "sizes": {id: байти}, "same": [id…]}

  convert.py convert FORMAT FILE…
      кожен FILE у FORMAT; результат — тека «Converted» поруч із оригіналом,
      оригінали не змінюються. Картинки — ImageMagick, відео й звук — ffmpeg
      (NVENC, якщо він справді відкривається). Відео можна витягнути в звук.

Кожна команда друкує JSON-рядки:
  {"ev": "progress", "got": n, "total": n, "file": "…"}
  {"ev": "done", "path": "…", "size": n}
  {"ev": "error", "text": "…"}

Коди виходу: 0 — усе гаразд, 1 — помилка (текст у "error"), 2 — неправильний виклик.
З --plain замість JSON — рядки, як їх читає людина в терміналі.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

KINDS = {
    "image": ["png", "jpg", "jpeg", "webp", "avif", "gif", "bmp", "tif", "tiff", "heic", "heif", "ico", "jxl", "tga"],
    "video": ["mp4", "mkv", "webm", "mov", "m4v", "avi", "flv", "ts", "mts", "m2ts", "wmv", "mpg", "mpeg", "3gp", "ogv"],
    "audio": ["mp3", "wav", "flac", "ogg", "oga", "opus", "m4a", "aac", "wma", "aiff", "aif", "alac", "mka"],
}

# id = розширення результату (для gifv — gif)
FORMATS = {
    "image": [("png", "PNG"), ("jpg", "JPG"), ("webp", "WebP"), ("avif", "AVIF"), ("gif", "GIF"), ("ico", "ICO")],
    "video": [("mp4", "MP4"), ("webm", "WebM"), ("mkv", "MKV"), ("gifv", "GIF")],
    "audio": [("mp3", "MP3"), ("wav", "WAV"), ("flac", "FLAC"), ("ogg", "OGG"), ("m4a", "M4A")],
}

# розширення, які вважаємо тим самим форматом
SAME = {"jpeg": "jpg", "tif": "tiff", "oga": "ogg", "opus": "ogg"}

OUT_DIR = "Converted"   # тека поруч із файлами


class Fail(Exception):
    pass


PLAIN = False   # --plain: людині в терміналі замість JSON


def say(ev, **data):
    if PLAIN:
        if ev == "done":
            print(data.get("path", ""), flush=True)
        elif ev == "error":
            print("error: " + str(data.get("text", "")), file=sys.stderr, flush=True)
        elif ev == "sizes":
            for k, v in (data.get("sizes") or {}).items():
                print(f"{k}: {v}")
        elif ev == "kinds":
            for kind, fmts in (data.get("formats") or {}).items():
                print(f"{kind}: " + " ".join(f["label"] for f in fmts))
        return
    print(json.dumps({"ev": ev} | data, ensure_ascii=False), flush=True)


def ext_of(path):
    return SAME.get(Path(path).suffix.lower().lstrip("."), Path(path).suffix.lower().lstrip("."))


def target_ext(fmt):
    return "gif" if fmt == "gifv" else fmt


def kind_of(path):
    e = Path(path).suffix.lower().lstrip(".")
    return next((k for k, exts in KINDS.items() if e in exts), "")


def free_name(path):
    """шлях, який ще не зайнятий: «name.png», далі «name (2).png»"""
    if not path.exists():
        return path
    for i in range(2, 1000):
        cand = path.with_name(f"{path.stem} ({i}){path.suffix}")
        if not cand.exists():
            return cand
    raise Fail(f"no free name next to {path}")


def converted(src, ext):
    """тека «Converted» поруч із src (або ~/Converted, якщо поруч не можна писати)"""
    folder = src.parent / OUT_DIR
    try:
        folder.mkdir(exist_ok=True)
        if not os.access(folder, os.W_OK):
            raise OSError
    except OSError:
        folder = Path.home() / OUT_DIR
        folder.mkdir(exist_ok=True)
    return free_name(folder / f"{src.stem}.{ext}")


# ─────────────────────────── probe / estimates ───────────────────────────

def media(src):
    """тривалість, розміри, бітрейти, чи є звук — для оцінки розміру"""
    r = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(src)],
                       capture_output=True, text=True)
    try:
        j = json.loads(r.stdout)
    except ValueError:
        j = {}
    fmt = j.get("format") or {}
    d = {"duration": 0.0, "width": 0, "height": 0, "fps": 30.0, "vbps": 0,
         "audio": False, "channels": 2, "rate": 48000}
    try:
        d["duration"] = float(fmt.get("duration") or 0)
    except ValueError:
        pass
    total = int(fmt.get("bit_rate") or 0)
    abps = 0
    for st in j.get("streams") or []:
        if st.get("codec_type") == "video" and not (st.get("disposition") or {}).get("attached_pic") and not d["width"]:
            d["width"] = int(st.get("width") or 0)
            d["height"] = int(st.get("height") or 0)
            num, _, den = str(st.get("avg_frame_rate") or "30/1").partition("/")
            try:
                d["fps"] = min(240.0, float(num) / float(den or 1)) or 30.0
            except (ValueError, ZeroDivisionError):
                pass
            d["vbps"] = int(st.get("bit_rate") or 0)
        elif st.get("codec_type") == "audio" and not d["audio"]:
            d["audio"] = True
            d["channels"] = int(st.get("channels") or 2)
            d["rate"] = int(st.get("sample_rate") or 48000)
            abps = int(st.get("bit_rate") or 0)
    if not d["vbps"] and d["width"]:
        d["vbps"] = max(0, total - abps)
    return d


def probe_length(src):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(src)],
                       capture_output=True, text=True)
    try:
        return max(0.1, float(r.stdout.strip()))
    except ValueError:
        return 1.0


def estimate_one(kind, fmt, src):
    """скільки байтів дасть fmt із src — за тривалістю, пікселями й бітрейтами"""
    size = src.stat().st_size
    if kind == "image":
        return size
    m = media(src)
    dur = m["duration"] or 0
    if fmt in dict(FORMATS["audio"]):
        if not m["audio"]:
            return 0
        pcm = m["rate"] * m["channels"] * 2 * dur
        return int({"mp3": 190_000, "wav": 0, "flac": 0, "ogg": 160_000, "m4a": 256_000}.get(fmt, 0) * dur / 8
                   or pcm * {"wav": 1, "flac": 0.55}.get(fmt, 1))
    px = m["width"] * m["height"] * m["fps"]
    sound = (192_000 if m["audio"] else 0) * dur / 8
    if fmt == "mkv":
        return size
    if fmt == "gifv":
        w = min(480, m["width"] or 480)
        h = (m["height"] or 270) * w / max(1, m["width"] or 480)
        return int(w * h * 15 * dur * 0.15)
    bpp = 0.035 if fmt == "webm" else 0.07     # h264 cq23 ≈ 0.07 біта на піксель, AV1 ≈ половина
    v = px * bpp
    if m["vbps"]:
        v = min(v, m["vbps"] * (0.8 if fmt == "webm" else 1.1))
    return int(v * dur / 8 + sound * (128 / 192 if fmt == "webm" else 1))


def pixels(src):
    r = subprocess.run(["magick", "identify", "-format", "%w %h\n", str(src)], capture_output=True, text=True)
    try:
        w, h = r.stdout.split()[:2]
        return int(w) * int(h)
    except ValueError:
        return 0


def sizes(kind, files):
    takes = {"image": ("image",), "video": ("video",), "audio": ("audio", "video")}[kind]
    todo = [Path(f).resolve() for f in files if kind_of(f) in takes and Path(f).is_file()]
    now = sum(f.stat().st_size for f in todo)
    same = [i for i, _ in FORMATS[kind] if todo and all(ext_of(f) == target_ext(i) for f in todo)]
    est = {}
    if kind == "image" and todo:
        # першу картинку конвертуємо по-справжньому, решту оцінюємо за пікселями
        first = todo[0]
        scale = sum(pixels(f) for f in todo) / max(1, pixels(first))
        tmp = Path(tempfile.mkdtemp(prefix="edots-sizes-"))
        try:
            for i, _ in FORMATS["image"]:
                try:
                    copy = tmp / first.name
                    shutil.copy(first, copy)
                    est[i] = int(image_convert(i, copy).stat().st_size * scale)
                except (Fail, OSError):
                    pass
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        for i, _ in FORMATS[kind]:
            est[i] = sum(estimate_one(kind_of(f) if kind != "audio" else "audio", i, f) for f in todo)
    say("sizes", now=now, sizes=est, same=same)


# ─────────────────────────── encoding ───────────────────────────

_NVENC = {}


def nvenc(codec="h264_nvenc"):
    """NVENC, який справді відкривається (наявність у списку кодеків ще нічого не значить)"""
    if codec not in _NVENC:
        if os.environ.get("EDOTS_NVENC") == "0":
            _NVENC[codec] = False
        else:
            r = subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=s=256x256:d=0.1", "-c:v", codec, "-f", "null", "-"],
                               capture_output=True, text=True)
            _NVENC[codec] = r.returncode == 0
    return _NVENC[codec]


def ffmpeg(args, out, length, part=0, parts=1):
    """один запуск ffmpeg; прогрес віддаємо як частину загального"""
    with tempfile.TemporaryFile() as err:
        p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-nostats", "-progress", "pipe:1", "-i"] + args,
                             stdout=subprocess.PIPE, stderr=err, text=True)
        for line in p.stdout:
            if line.startswith("out_time_ms="):
                try:
                    got = float(line.split("=", 1)[1]) / 1_000_000
                except ValueError:
                    continue
                ratio = min(1.0, got / length) if length else 0
                say("progress", got=round((part + ratio) * 1000 / parts), total=1000, file=str(out))
        p.wait()
        if p.returncode:
            err.seek(0)
            tail = (err.read().decode("utf-8", "replace").strip().splitlines() or ["?"])[-1]
            raise Fail("ffmpeg: " + tail)


def image_convert(fmt, src):
    """картинка через ImageMagick"""
    out = converted(src, fmt)
    frame = "[0]" if src.suffix.lower() == ".gif" and fmt not in ("gif", "webp") else ""
    extra = {"jpg": ["-background", "white", "-alpha", "remove", "-quality", "92"],
             "ico": ["-background", "none", "-resize", "256x256>", "-define", "icon:auto-resize=256,128,64,48,32,16"],
             "webp": ["-quality", "90"],
             "avif": ["-quality", "70"]}.get(fmt, [])
    r = subprocess.run(["magick", str(src) + frame] + extra + [str(out)], capture_output=True, text=True)
    if r.returncode:
        out.unlink(missing_ok=True)
        raise Fail("ImageMagick: " + ((r.stderr.strip().splitlines() or ["?"])[-1]))
    return out


AUDIO_CODEC = {
    "mp3": ["-c:a", "libmp3lame", "-q:a", "2"],
    "wav": ["-c:a", "pcm_s16le"],
    "flac": ["-c:a", "flac"],
    "ogg": ["-c:a", "libopus", "-b:a", "160k"],
    "m4a": ["-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart"],
}


def has_audio(src):
    return bool(media(src)["audio"])


def convert_one(kind, fmt, src, part, parts):
    if kind == "image":
        return image_convert(fmt, src)
    out = converted(src, target_ext(fmt))
    length = probe_length(src)
    if fmt in AUDIO_CODEC:
        if not has_audio(src):
            raise Fail(f"{src.name}: no sound")
        ffmpeg([str(src), "-map", "0:a:0", "-vn"] + AUDIO_CODEC[fmt] + [str(out)], out, length, part, parts)
        return out
    sound = ["-map", "0:a?"]
    if fmt == "mkv":
        args = ["-map", "0:v", "-map", "0:a?", "-map", "0:s?", "-c", "copy"]
    elif fmt == "gifv":
        args = ["-map", "0:v:0", "-vf",
                "fps=15,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0"]
    elif fmt == "webm":
        if nvenc("av1_nvenc"):
            v = ["-c:v", "av1_nvenc", "-preset", "p5", "-cq", "32"]
        else:
            v = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good", "-cpu-used", "4"]
        args = ["-map", "0:v:0"] + sound + v + ["-c:a", "libopus", "-b:a", "128k"]
    else:   # mp4
        v = ["-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23"] if nvenc() else \
            ["-c:v", "libx264", "-preset", "medium", "-crf", "20"]
        args = ["-map", "0:v:0"] + sound + v + ["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                                                "-movflags", "+faststart"]
    ffmpeg([str(src)] + args + [str(out)], out, length, part, parts)
    return out


def convert(fmt, files):
    kind = next((k for k, v in FORMATS.items() if fmt in dict(v)), "")
    if not kind:
        raise Fail(f"unknown format: {fmt}")
    takes = {"image": ("image",), "video": ("video",), "audio": ("audio", "video")}[kind]
    todo = [Path(f).resolve() for f in files if kind_of(f) in takes and Path(f).is_file()]
    todo = [f for f in todo if ext_of(f) != target_ext(fmt)]      # уже в цьому форматі — нічого робити
    if not todo:
        raise Fail("no files of that kind (or they are that format already)")
    failed = []
    for i, src in enumerate(todo):
        try:
            out = convert_one(kind_of(src) if kind != "audio" else "audio", fmt, src, i, len(todo))
            say("done", path=str(out), size=out.stat().st_size)
        except Fail as e:
            failed.append(f"{src.name}: {e.args[0]}")
    if failed:
        raise Fail("\n".join(failed))


def kinds():
    say("kinds", **{"kinds": KINDS,
                    "formats": {k: [{"id": i, "label": l} for i, l in v] for k, v in FORMATS.items()}})


def main(argv):
    global PLAIN
    if "--plain" in argv:
        PLAIN = True
        argv = [a for a in argv if a != "--plain"]
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "kinds":
            kinds()
        elif cmd == "sizes" and len(args) >= 2 and args[0] in FORMATS:
            sizes(args[0], args[1:])
        elif cmd == "convert" and len(args) >= 2:
            os.nice(10)
            convert(args[0], args[1:])
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except Fail as e:
        say("error", text=str(e.args[0]))
        return 1
    except OSError as e:
        say("error", text=str(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
