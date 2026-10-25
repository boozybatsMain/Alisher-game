#!/usr/bin/env python3
"""Генерация картинки через локальный Codex CLI (встроенный image_gen).

Пример:
    python3 tools/codex_image.py art_src/hero/sheet.png prompts/hero.txt -i art_src/ref/yurt_ref.png

Codex сохраняет картинки в ~/.codex/generated_images/<thread_id>/,
поэтому берём thread_id из JSON-событий и копируем оттуда результат.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

PREAMBLE = (
    "Use your built-in image generation tool to create exactly ONE image from the description below. "
    "Do not write code, do not run shell commands, do not edit or create files yourself. "
    "If reference images are attached, use them only as a style reference unless told otherwise. "
    "After the image is generated, reply only with the word DONE.\n\n"
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("prompt_file")
    ap.add_argument("-i", "--image", action="append", default=[])
    ap.add_argument("--effort", default="low")
    a = ap.parse_args()

    prompt = PREAMBLE + open(a.prompt_file, encoding="utf-8").read()
    work = tempfile.mkdtemp(prefix="codex_img_")
    cmd = ["codex", "exec", "--json", "--skip-git-repo-check", "-s", "read-only",
           "-c", f'model_reasoning_effort="{a.effort}"', "-C", work]
    for img in a.image:
        cmd += ["-i", os.path.abspath(img)]
    cmd.append("-")
    t0 = time.time()
    proc = subprocess.run(cmd, input=prompt, text=True, capture_output=True, timeout=1500)
    thread_id = None
    saved = []
    for line in proc.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "thread.started":
            thread_id = ev.get("thread_id")
        blob = json.dumps(ev)
        for token in blob.split('"'):
            if token.endswith(".png") and "generated_images" in token:
                saved.append(token)
    candidates = []
    if thread_id:
        candidates = sorted(glob.glob(os.path.expanduser(f"~/.codex/generated_images/{thread_id}/*.png")),
                            key=os.path.getmtime)
    candidates += [s for s in saved if os.path.exists(s)]
    if not candidates:
        sys.stderr.write("NO IMAGE. stdout tail:\n" + proc.stdout[-3000:] + "\nstderr:\n" + proc.stderr[-2000:])
        sys.exit(1)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    shutil.copy(candidates[-1], a.out)
    print(f"{a.out}  ({time.time() - t0:.0f}s, thread {thread_id})")


if __name__ == "__main__":
    main()
