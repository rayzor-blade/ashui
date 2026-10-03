#!/usr/bin/env python3
"""Runs the Pacing bench and reports, per phase, frame pacing from
ASHUI_FRAME_LOG and, on Linux, CPU per thread from /proc.

    pacing.py [--out DIR] -- <command that runs Pacing.hl>

The command's stdout carries the bench's `phase` lines. Threads are grouped
by name, so the app's own threads stay apart from a software renderer's
(llvmpipe, lavapipe) and the driver's.
"""
import os
import statistics
import subprocess
import sys
import threading
import time

HZ = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100


def threads(pid):
    out = {}
    try:
        tids = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return out
    for tid in tids:
        try:
            with open(f"/proc/{pid}/task/{tid}/stat") as f:
                stat = f.read()
        except OSError:
            continue
        name = stat[stat.index("(") + 1 : stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2 :].split()
        out[tid] = (name, (int(fields[11]) + int(fields[12])) / HZ)
    return out


def group(name):
    # Worker pools number their threads; one row per pool.
    return name.rstrip("0123456789:-_ ") or name


def sample(pid, samples, done):
    while not done.is_set():
        samples.append((time.time(), threads(pid)))
        time.sleep(0.25)


def main():
    args = sys.argv[1:]
    out_dir = "."
    if args[:1] == ["--out"]:
        out_dir, args = args[1], args[2:]
    if args[:1] == ["--"]:
        args = args[1:]
    frame_log = os.path.join(os.path.abspath(out_dir), "pacing-frames.tsv")
    env = dict(os.environ, ASHUI_FRAME_LOG=frame_log)
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True, env=env)
    samples, done = [], threading.Event()
    sampler = threading.Thread(target=sample, args=(proc.pid, samples, done))
    if os.path.isdir("/proc"):
        sampler.start()
    phases = []
    for line in proc.stdout:
        if line.startswith("phase "):
            _, name, epoch, ms, *state = line.split()
            phases.append((name, float(epoch), float(ms)))
            if "active=false" in state:
                print(f"note: the window is not active at the start of {name}")
        else:
            sys.stdout.write(line)
    proc.wait()
    done.set()
    if sampler.is_alive():
        sampler.join()
    report(phases, frame_log, samples)


def frames(path):
    rows = []
    with open(path) as f:
        header = None
        for line in f:
            cells = line.rstrip("\n").split("\t")
            if cells[0] == "frame":
                header = cells
            elif header and cells[0].isdigit():
                rows.append({k: float(v) for k, v in zip(header, cells)})
    return rows


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(p * len(s)))]


def report(phases, frame_log, samples):
    rows = frames(frame_log)
    print(f"{'phase':<11} {'frames':>6} {'fps':>6} {'gap p50':>8} {'p95':>6} {'max':>6} {'wait p50':>9} {'ui p50':>7} {'ui p95':>7} {'gpu p50':>8} {'present p50':>12} {'p95':>6}")
    for (name, _, start), (_, _, end) in zip(phases, phases[1:]):
        # The first frame of a phase measures the wait since the last phase.
        inside = [r for r in rows if start <= r["at_ms"] < end]
        gaps = [r["since_last_frame"] for r in inside[1:]]
        ui = [r["tick"] + r["flush"] + r["draw_flush"] + r["layout"] + r["list"] for r in inside]
        gpu = [r["gpu"] for r in inside]
        wait = [r["wait"] for r in inside[1:]]
        present = [r["present"] for r in inside]
        seconds = (end - start) / 1000
        print(f"{name:<11} {len(inside):>6} {len(inside) / seconds:>6.1f} {pct(gaps, .5):>8.1f} {pct(gaps, .95):>6.1f} {max(gaps, default=float('nan')):>6.1f} {pct(wait, .5):>9.1f} "
              f"{pct(ui, .5):>7.2f} {pct(ui, .95):>7.2f} {pct(gpu, .5):>8.2f} {pct(present, .5):>12.2f} {pct(present, .95):>6.2f}")
    print("(ms; wait = in the window's wait for events, ui = tick + flush + layout + display list, gpu = encode and submit, present = the rest of the frame)")
    if not samples:
        return
    print()
    names = sorted({group(n) for _, ts in samples for n, _ in ts.values()})
    print(f"{'phase':<11} " + " ".join(f"{n[:14]:>14}" for n in names) + f" {'total':>7}")
    for (name, start, _), (_, end, _) in zip(phases, phases[1:]):
        inside = [s for s in samples if start <= s[0] <= end]
        if len(inside) < 2:
            continue
        (t0, a), (t1, b) = inside[0], inside[-1]
        used = {}
        for tid, (n, cpu) in b.items():
            used[group(n)] = used.get(group(n), 0) + cpu - (a[tid][1] if tid in a else 0)
        span = t1 - t0
        cells = [100 * used.get(n, 0) / span for n in names]
        print(f"{name:<11} " + " ".join(f"{c:>13.1f}%" for c in cells) + f" {sum(cells):>6.1f}%")
    print("(% of one core, by thread name)")


if __name__ == "__main__":
    main()
