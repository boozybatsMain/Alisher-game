#!/usr/bin/env python3
"""Пакетная генерация картинок через Codex (параллельно).

Файл заданий: строки «выход | промпт | реф1,реф2», пути от art_src/.
Пустая строка с «---» — барьер: следующие задания ждут завершения предыдущих.
Уже существующие выходные файлы пропускаются (удалите файл, чтобы перегенерировать).
"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "art_src")


def run(job):
    out, prompt, refs = job
    out_p = os.path.join(SRC, out)
    if os.path.exists(out_p):
        return f"skip {out}"
    cmd = [sys.executable, os.path.join(ROOT, "tools", "codex_image.py"), out_p, os.path.join(SRC, "prompts", prompt)]
    for r in refs:
        cmd += ["-i", os.path.join(SRC, r)]
    for attempt in range(2):
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode == 0:
            return p.stdout.strip()
    return f"FAIL {out}: {p.stderr[-500:]}"


def main():
    jobs_file, workers = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4
    stages, cur = [], []
    for line in open(jobs_file, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "---":
            stages.append(cur)
            cur = []
            continue
        parts = [x.strip() for x in line.split("|")]
        refs = [r for r in (parts[2].split(",") if len(parts) > 2 else []) if r]
        cur.append((parts[0], parts[1], refs))
    stages.append(cur)
    with ThreadPoolExecutor(workers) as ex:
        for st in stages:
            for res in ex.map(run, st):
                print(res, flush=True)


if __name__ == "__main__":
    main()
