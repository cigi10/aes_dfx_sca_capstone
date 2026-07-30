#!/usr/bin/env python3

import serial
import time
import re
import argparse
import sys
import os
import json
import statistics
import os as _os

DEFAULT_PORT = '/dev/ttyUSB1'
BAUD = 115200
MAX_TOTAL_TIME = 90          # hard ceiling per transaction, in seconds
INTER_BYTE_DELAY = 0.02      # matches the throttled-send that worked before

PLAINTEXT = bytes.fromhex('00112233445566778899aabbccddeeff')
KEY       = bytes.fromhex('000102030405060708090a0b0c0d0e0f')
EXPECTED  = "69c4e0d86a7b0430d8cdb78070b4c55a"

ITER_COMPLETE_RE = re.compile(r'-+ Iteration (\d+) complete -+')
CT_BLOCK_RE = re.compile(
    r'\[bram\] Reading ciphertext region:(.*?)(?=\[send\])', re.S
)
CT_TX_RE = re.compile(r'\[ciphertext TX\] byte\s*(\d+)\s*=\s*0x([0-9A-Fa-f]{2})\s*sent')

VERBOSE = False  # set from --verbose in main()


def vprint(*args, **kwargs):
    """Print only when --verbose is set."""
    if VERBOSE:
        print(*args, **kwargs)


def random_bytes16():
    """Fresh random 16-byte value, used for --mode random."""
    return _os.urandom(16)


def check_latency_timer(port):
    """
    Prints the current FTDI latency_timer setting for the given serial
    port device, if it can be found. Doesn't change anything -- just
    reports, so you can decide whether to fix it before testing.
    """
    dev_name = os.path.basename(port)  # e.g. 'ttyUSB1' from '/dev/ttyUSB1'
    sys_path = f"/sys/bus/usb-serial/devices/{dev_name}/latency_timer"

    print(f"\nChecking FTDI latency_timer for {port} ...")
    if not os.path.exists(sys_path):
        print(f"  Could not find {sys_path}")
        print("  (device may not be an FTDI adapter, or not currently connected)")
        return

    with open(sys_path) as f:
        value = f.read().strip()

    print(f"  Current latency_timer: {value} ms")
    if value == "1":
        print("  Good -- already set to 1ms, minimal batching delay.")
    else:
        print("  This is the Linux FTDI default (16ms). It can cause a")
        print("  bimodal split in round-trip timing (~16ms gap between")
        print("  clusters) that has nothing to do with your RTL. Fix with:")
        print(f"\n    echo 1 | sudo tee {sys_path}\n")
        print("  This only affects this USB device's buffering, resets on")
        print("  replug/reboot unless you add a udev rule, and is safe.")


def run_one_transaction(ser, run_index, plaintext, key, expected=None, label=""):
    """
    Sends plaintext+key over UART, waits for the firmware's completion
    marker, parses the transmitted ciphertext bytes, and reports timing.

    Returns (result, elapsed_seconds, ciphertext_hex_or_None) where result is:
        True  -> matched expected value (fixed mode only)
        False -> mismatched expected value (fixed mode only)
        "OK"  -> well-formed ciphertext received, random mode (NOT verified correct)
        None  -> couldn't parse a valid ciphertext at all (timeout/parse failure)
    """
    vprint(f"\n=== Run {run_index}{label}: sending plaintext/key ===")
    vprint(f"Plaintext: {plaintext.hex()}")
    vprint(f"Key:       {key.hex()}")

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    for b in (plaintext + key):
        ser.write(bytes([b]))
        time.sleep(INTER_BYTE_DELAY)

    vprint("Sent 32 bytes. Waiting for firmware's 'Iteration complete' marker...")

    # --- timed region starts here ---
    start_time = time.perf_counter()

    data = bytearray()
    start = time.time()
    while True:
        chunk = ser.read(1024)
        if chunk:
            data.extend(chunk)
            text_so_far = bytes(data).decode('ascii', errors='replace')
            if ITER_COMPLETE_RE.search(text_so_far):
                break
        if time.time() - start > MAX_TOTAL_TIME:
            print(f"\n*** TIMEOUT after {MAX_TOTAL_TIME}s — no completion marker seen "
                  f"(run {run_index}{label}). ***")
            print("Possible causes: firmware hung in the poll loop (check for a")
            print("'*** TIMEOUT ***' line below), wrong baud rate, or wrong port.")
            break

    elapsed = time.perf_counter() - start_time
    # --- timed region ends here ---

    text = bytes(data).decode('ascii', errors='replace')
    vprint(f"  ({len(data)} bytes received)")

    if '*** TIMEOUT ***' in text:
        print(f"\n[run {run_index}{label}] Firmware itself reported a poll timeout "
              f"(op_complete never seen).")
        print("This is a hardware/trigger issue, not a parsing issue -- check the")
        print("trigger/status GPIO wiring and the FSM writeback separately.")

    ct_match = CT_BLOCK_RE.search(text)
    if not ct_match:
        print(f"\n[run {run_index}{label}] No '[bram] Reading ciphertext region:' "
              f"block found.")
        print("Raw capture follows for inspection:\n")
        print(text)
        return None, elapsed, None

    tx_matches = CT_TX_RE.findall(text)
    if len(tx_matches) != 16:
        print(f"\n[run {run_index}{label}] Couldn't find all 16 "
              f"'[ciphertext TX] byte N = 0xXX sent' lines "
              f"(found {len(tx_matches)}). Falling back to raw text inspection.")
        print(text)
        return None, elapsed, None

    # sort by byte index to be safe, then take just the hex values in order
    tx_matches.sort(key=lambda pair: int(pair[0]))
    ct_hex = ''.join(v.lower() for _, v in tx_matches)

    vprint("\nActual bytes transmitted over UART (ground truth, post-firmware-reversal):")
    vprint(f"  {ct_hex}")

    if expected is not None:
        vprint(f"Expected (FIPS-197):      {expected}")
        if ct_hex == expected:
            return True, elapsed, ct_hex
        else:
            print(f"\n[run {run_index}{label}] *** MISMATCH ***")
            exp_words = [expected[i:i+8] for i in range(0, 32, 8)]
            got_words = [ct_hex[i:i+8] for i in range(0, 32, 8)]
            for i, (e, g) in enumerate(zip(exp_words, got_words)):
                flag = "OK" if e == g else "DIFFERS"
                print(f"  word[{i}]: got={g}  expected={e}  [{flag}]")
            return False, elapsed, ct_hex
    else:
        # random-input mode: no known expected value. "OK" means we got a
        # well-formed 16-byte ciphertext back -- NOT that it's verified
        # correct. See module docstring, limitation #4.
        return "OK", elapsed, ct_hex


def check_stale_output(run_index, label, plaintext, key, ct_hex, prev_entry):
    """
    Random-mode-only sanity check: if this run's inputs differ from the
    previous run's inputs but the ciphertext is IDENTICAL, that strongly
    suggests the firmware timed out and returned a stale value left over
    in BRAM from a previous successful run, rather than a fresh result.
    Prints a loud warning if so. Returns this run's (plaintext, key, ct_hex)
    to become `prev_entry` for the next call.
    """
    if prev_entry is not None and ct_hex is not None:
        prev_pt, prev_key, prev_ct = prev_entry
        inputs_differ = (plaintext != prev_pt) or (key != prev_key)
        if inputs_differ and ct_hex == prev_ct:
            print(f"\n{'!'*70}")
            print(f"  WARNING [run {run_index}{label}]: ciphertext is IDENTICAL to the")
            print(f"  previous run's ciphertext, but plaintext/key were DIFFERENT.")
            print(f"  This is a classic symptom of stale BRAM / a timed-out compute")
            print(f"  being reported as a valid result. Do not trust this run as a")
            print(f"  genuine fresh computation -- check for a firmware")
            print(f"  '*** TIMEOUT ***' line, or rerun with --verbose to inspect the")
            print(f"  raw poll-loop output for this run.")
            print(f"{'!'*70}")
    return (plaintext, key, ct_hex)


def compute_stats(times_ms):
    """Returns a dict of summary statistics for a list of times in ms."""
    n = len(times_ms)
    mean = statistics.mean(times_ms)
    stdev = statistics.stdev(times_ms) if n > 1 else 0.0
    return {
        "n": n,
        "mean": mean,
        "median": statistics.median(times_ms),
        "stdev": stdev,
        "cv_pct": (stdev / mean * 100) if mean else 0.0,
        "min": min(times_ms),
        "max": max(times_ms),
        "range": max(times_ms) - min(times_ms),
        "p90": statistics.quantiles(times_ms, n=10)[8] if n >= 10 else max(times_ms),
    }


def print_stats_table(rm_label, times, results, ciphertexts, inputs_log, mode):
    """Prints a stats block, saves per-RM JSON + a plain-text summary file."""
    times_ms = [t * 1000 for t in times]
    s = compute_stats(times_ms)

    n_total = len(results)
    n_match = sum(1 for r in results if r is True)
    n_ok = sum(1 for r in results if r == "OK")
    n_mismatch = sum(1 for r in results if r is False)
    n_nodata = sum(1 for r in results if r is None)
    match_rate = n_match / n_total * 100 if n_total else 0.0
    ok_rate = n_ok / n_total * 100 if n_total else 0.0

    valid_cts = [c for c in ciphertexts if c is not None]
    # ciphertext consistency only meaningful in fixed mode (same input every run)
    ct_consistent = (len(set(valid_cts)) <= 1) if (mode == 'fixed' and valid_cts) else None
    # in random mode, unique-ciphertext count is a useful sanity signal instead
    ct_unique_count = len(set(valid_cts)) if (mode == 'random' and valid_cts) else None

    lines = []
    lines.append(f"{'='*55}")
    lines.append(f"  Timing stats — {rm_label}  (n={s['n']} runs, mode={mode})")
    lines.append(f"{'='*55}")
    lines.append(f"  {'Mean':<12}: {s['mean']:8.3f} ms")
    lines.append(f"  {'Median':<12}: {s['median']:8.3f} ms")
    lines.append(f"  {'Std Dev':<12}: {s['stdev']:8.3f} ms")
    lines.append(f"  {'CoV %':<12}: {s['cv_pct']:8.2f} %   (stdev as % of mean)")
    lines.append(f"  {'Min':<12}: {s['min']:8.3f} ms")
    lines.append(f"  {'Max':<12}: {s['max']:8.3f} ms")
    lines.append(f"  {'Range':<12}: {s['range']:8.3f} ms")
    lines.append(f"  {'90th %ile':<12}: {s['p90']:8.3f} ms")
    if mode == 'fixed':
        lines.append(f"  {'Match rate':<12}: {n_match}/{n_total} ({match_rate:.1f}%)  "
                      f"[mismatches: {n_mismatch}, no-data/timeout: {n_nodata}]")
        if ct_consistent is not None:
            lines.append(f"  {'CT stable?':<12}: {'Yes' if ct_consistent else 'NO - VARIED'}")
    else:
        lines.append(f"  {'Well-formed':<12}: {n_ok}/{n_total} ({ok_rate:.1f}%)  "
                      f"[no-data/timeout: {n_nodata}]  (NOT a correctness check)")
        if ct_unique_count is not None:
            lines.append(f"  {'Unique CTs':<12}: {ct_unique_count}/{len(valid_cts)}  "
                          f"(should be ~= number of valid runs; low count with")
            lines.append(f"  {'':12}  differing inputs suggests stale/stuck output)")
    lines.append(f"{'='*55}")

    for line in lines:
        print(line)

    os.makedirs("results", exist_ok=True)
    with open(f"results/{rm_label}.json", "w") as f:
        json.dump({
            "rm_label": rm_label,
            "mode": mode,
            "times_ms": times_ms,
            "stats": s,
            "match_rate": match_rate if mode == 'fixed' else None,
            "ok_rate": ok_rate if mode == 'random' else None,
            "n_match": n_match,
            "n_ok": n_ok,
            "n_mismatch": n_mismatch,
            "n_nodata": n_nodata,
            "n_total": n_total,
            "ct_consistent": ct_consistent,
            "ct_unique_count": ct_unique_count,
            "runs_raw": inputs_log,   # full per-run plaintext/key/ciphertext log
        }, f, indent=2)

    # human-readable summary you can paste directly into a report/email
    with open(f"results/{rm_label}_summary.txt", "w") as f:
        f.write("\n".join(lines) + "\n")

    return s


THEORY_NOTE = """
  Theoretical cycle-cost note (auto-printed, not measured directly):
    - rm_desync's RTL adds a random 1-15 cycle delay before aes_done
      asserts. At ~100MHz that's 10-150ns of intended delay per run.
    - rm_dummy's RTL adds 0-3 dummy AES rounds before aes_done asserts;
      actual added time depends on round pipeline depth, but is also
      on the order of tens-to-hundreds of ns per run.
    - Both of these are far below the resolution of UART-level wall-clock
      timing (millisecond scale, sub-millisecond at best even with a
      1ms FTDI latency timer), and can be swamped further by OS-scheduler
      jitter.
    - This means NO SINGLE RUN can resolve these delays directly. What
      CAN be detected is a statistically significant difference in
      variance (stdev) across many repeated runs, IF the randomization
      is large/frequent enough to shift the aggregate distribution.
    - A negative result (no significant variance difference) does NOT
      necessarily mean the RTL isn't working -- it may simply mean the
      delay is too small relative to UART/OS noise to surface at this
      measurement resolution. Direct ILA/cycle-counter measurement (not
      done here) would be needed to rule that out conclusively.
"""


def levene_pairwise(all_data, baseline_label="rm_bare"):
    """
    Runs Levene's test (equal-variance test) between the baseline RM and
    every other RM, reporting whether each RM's timing variance is
    statistically significantly different from the baseline's.
    """
    try:
        from scipy.stats import levene
    except ImportError:
        print("\n(scipy not installed -- skipping Levene's significance test.")
        print(" Install with: pip install scipy --break-system-packages)")
        return

    by_label = {d["rm_label"]: d["times_ms"] for d in all_data}
    if baseline_label not in by_label:
        print(f"\n(No '{baseline_label}' results found -- skipping Levene's test, "
              f"no baseline to compare against.)")
        return

    baseline_times = by_label[baseline_label]

    print(f"\n{'='*80}")
    print(f"  Levene's Test — variance significance vs. baseline ({baseline_label})")
    print(f"{'='*80}")
    print(f"  {'RM':<14}{'statistic':>12}{'p-value':>12}  Significant? (p<0.05)")
    print(f"  {'-'*76}")
    for label, times_ms in by_label.items():
        if label == baseline_label:
            continue
        stat, p = levene(baseline_times, times_ms)
        sig = "YES - variance differs" if p < 0.05 else "no - not significant"
        print(f"  {label:<14}{stat:>12.4f}{p:>12.4f}  {sig}")
    print(f"{'='*80}")
    print("  A 'YES' result means this RM's timing variance is statistically")
    print("  distinguishable from the baseline's -- i.e. more than random chance.")
    print(f"{'='*80}\n")


def print_comparison_table():
    """Reads all saved results/*.json files and prints a combined table."""
    if not os.path.isdir("results"):
        print("No saved results found yet — run each RM first.")
        return

    all_data = []
    for fname in sorted(os.listdir("results")):
        if fname.endswith(".json"):
            with open(f"results/{fname}") as f:
                all_data.append(json.load(f))

    if not all_data:
        print("No saved results found yet.")
        return

    rows = [(d["rm_label"], d["stats"]) for d in all_data]

    print(f"\n{'='*80}")
    print(f"  Cross-RM Timing Comparison")
    print(f"{'='*80}")
    header = f"  {'RM':<14}{'Mean(ms)':>10}{'StDev(ms)':>11}{'CoV%':>8}{'Min':>10}{'Max':>10}"
    print(header)
    print(f"  {'-'*76}")
    for label, s in rows:
        print(f"  {label:<14}{s['mean']:>10.3f}{s['stdev']:>11.3f}"
              f"{s['cv_pct']:>8.2f}{s['min']:>10.3f}{s['max']:>10.3f}")
    print(f"{'='*80}")
    print("  Interpretation: rm_bare's stdev is your measurement noise floor.")
    print("  rm_desync/rm_dummy should show higher stdev if their RTL-intended")
    print("  randomization (1-15 cycle delay / 0-3 dummy rounds) surfaces through")
    print("  UART-level timing. rm_masking is a power-domain countermeasure and")
    print("  is not expected to show a timing difference.")
    print(f"{'='*80}")

    levene_pairwise(all_data, baseline_label="rm_bare")
    print(THEORY_NOTE)


def plot_comparison():
    """Generates and saves bar/scatter/3D comparison plots from saved results."""
    import matplotlib.pyplot as plt
    import numpy as np

    if not os.path.isdir("results"):
        print("No saved results found yet.")
        return

    all_data = []
    for fname in sorted(os.listdir("results")):
        if fname.endswith(".json"):
            with open(f"results/{fname}") as f:
                all_data.append(json.load(f))

    if not all_data:
        print("No saved results found yet.")
        return

    labels = [d["rm_label"] for d in all_data]
    means = [d["stats"]["mean"] for d in all_data]
    stdevs = [d["stats"]["stdev"] for d in all_data]
    colors = ['#4C72B0', '#DD8452', '#55A868', '#C44E52']

    # --- Plot 1: Bar chart, mean +/- stdev per RM ---
    fig1, ax1 = plt.subplots(figsize=(8, 5))
    bars = ax1.bar(labels, means, yerr=stdevs, capsize=6,
                    color=[colors[i % len(colors)] for i in range(len(labels))])
    ax1.set_ylabel("Round-trip time (ms)")
    ax1.set_title("Mean Round-Trip Time by RM (error bars = stdev)")
    ax1.grid(axis='y', linestyle='--', alpha=0.5)
    for bar, m in zip(bars, means):
        ax1.text(bar.get_x() + bar.get_width()/2, m, f"{m:.2f}",
                  ha='center', va='bottom', fontsize=9)
    plt.tight_layout()
    plt.savefig("results/mean_stdev_comparison.png", dpi=150)
    print("Saved: results/mean_stdev_comparison.png")
    plt.close(fig1)

    # --- Plot 2: Scatter of every individual run, all RMs on one plot ---
    fig2, ax2 = plt.subplots(figsize=(9, 5))
    for i, d in enumerate(all_data):
        y = d["times_ms"]
        x = np.array([i] * len(y)) + np.random.normal(0, 0.05, len(y))  # jitter
        ax2.scatter(x, y, alpha=0.6, color=colors[i % len(colors)], label=d["rm_label"])
    ax2.set_xticks(range(len(labels)))
    ax2.set_xticklabels(labels)
    ax2.set_ylabel("Round-trip time (ms)")
    ax2.set_title("Individual Run Timings by RM (spread visualization)")
    ax2.legend()
    ax2.grid(axis='y', linestyle='--', alpha=0.5)
    plt.tight_layout()
    plt.savefig("results/individual_runs_scatter.png", dpi=150)
    print("Saved: results/individual_runs_scatter.png")
    plt.close(fig2)

    # --- Plot 3: 3D — RM index, run index, time ---
    fig3 = plt.figure(figsize=(9, 7))
    ax3 = fig3.add_subplot(111, projection='3d')
    for i, d in enumerate(all_data):
        y = d["times_ms"]
        x = [i] * len(y)
        z = list(range(len(y)))
        ax3.scatter(x, z, y, color=colors[i % len(colors)], label=d["rm_label"], alpha=0.7)
    ax3.set_xlabel("RM")
    ax3.set_xticks(range(len(labels)))
    ax3.set_xticklabels(labels)
    ax3.set_ylabel("Run number")
    ax3.set_zlabel("Round-trip time (ms)")
    ax3.set_title("3D View: RM x Run x Timing")
    ax3.legend()
    plt.tight_layout()
    plt.savefig("results/3d_comparison.png", dpi=150)
    print("Saved: results/3d_comparison.png")
    plt.close(fig3)


def main():
    global VERBOSE

    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default=DEFAULT_PORT)
    ap.add_argument('--baud', type=int, default=BAUD)
    ap.add_argument('--runs', type=int, default=30,
                     help="number of timed runs to perform (default 30)")
    ap.add_argument('--warmup', type=int, default=3,
                     help="throwaway runs before timed runs start (default 3)")
    ap.add_argument('--rm-label', default='unknown',
                     help="label for which RM is currently loaded, e.g. rm_bare")
    ap.add_argument('--mode', choices=['fixed', 'random'], default='fixed',
                     help="'fixed' uses the FIPS-197 vector every run; "
                          "'random' sends a fresh random plaintext/key each run")
    ap.add_argument('--compare', action='store_true',
                     help="skip hardware, just print comparison table from saved results")
    ap.add_argument('--plot', action='store_true',
                     help="skip hardware, generate comparison graphs from saved results")
    ap.add_argument('--check-latency', action='store_true',
                     help="print the FTDI latency_timer setting for --port and exit")
    ap.add_argument('--verbose', action='store_true',
                     help="print every byte/step from the firmware capture (very "
                          "long output). Off by default; full raw text is always "
                          "still printed automatically on parse failures/timeouts.")
    args = ap.parse_args()
    VERBOSE = args.verbose

    if args.check_latency:
        check_latency_timer(args.port)
        return
    if args.compare:
        print_comparison_table()
        return
    if args.plot:
        plot_comparison()
        return

    print(f"\n{'#'*70}")
    print(f"# NOTE: INTER_BYTE_DELAY = {INTER_BYTE_DELAY}s is a FIXED delay applied to")
    print(f"# every one of the 32 bytes sent per run (~{INTER_BYTE_DELAY*32*1000:.0f}ms artificial")
    print(f"# overhead per transaction, identical across all RMs). This delay happens")
    print(f"# BEFORE the timer starts, so it does not pollute the recorded timing --")
    print(f"# only the response-wait phase is measured.")
    print(f"# See module docstring for the full set of measurement limitations.")
    print(f"{'#'*70}\n")

    check_latency_timer(args.port)

    print(f"\nOpening {args.port} @ {args.baud} baud...")
    ser = serial.Serial(args.port, args.baud, timeout=0.5)
    time.sleep(0.3)
    leftover = ser.read(100000)
    if leftover:
        print(f"(discarded {len(leftover)} stale bytes sitting in buffer)")

    # --- warmup runs, discarded ---
    if args.warmup > 0:
        print(f"\n--- Running {args.warmup} warmup transaction(s) (not recorded) ---")
        for i in range(args.warmup):
            if args.mode == 'random':
                run_one_transaction(ser, f"warmup-{i+1}", random_bytes16(), random_bytes16())
            else:
                run_one_transaction(ser, f"warmup-{i+1}", PLAINTEXT, KEY, expected=EXPECTED)

    # --- timed runs ---
    print(f"\n--- Running {args.runs} timed run(s), mode={args.mode} ---")
    results, times, ciphertexts, inputs_log = [], [], [], []
    prev_entry = None  # (plaintext, key, ct_hex) of previous run, for stale-output check

    for i in range(1, args.runs + 1):
        if args.mode == 'random':
            pt, key = random_bytes16(), random_bytes16()
            r, t, ct = run_one_transaction(ser, i, pt, key, label=" [random]")
        else:
            pt, key = PLAINTEXT, KEY
            r, t, ct = run_one_transaction(ser, i, pt, key, expected=EXPECTED, label=" [fixed]")

        results.append(r)
        times.append(t)
        ciphertexts.append(ct)
        inputs_log.append({"plaintext": pt.hex(), "key": key.hex(), "ciphertext": ct})

        # live per-run status line
        status = ("MATCH" if r is True else
                   "OK (well-formed, unverified)" if r == "OK" else
                   "MISMATCH" if r is False else
                   "NO DATA / TIMEOUT")
        print(f"  run {i:>3}: {status:<28} ({t*1000:8.3f} ms)  ct={ct if ct else '-'}")

        # stale-BRAM / stuck-output check, random mode only
        if args.mode == 'random':
            prev_entry = check_stale_output(i, " [random]", pt, key, ct, prev_entry)

    ser.close()

    print("\n=== Summary ===")
    for i, r in enumerate(results, 1):
        status = ("MATCH" if r is True else
                   "OK (well-formed, unverified)" if r == "OK" else
                   "MISMATCH" if r is False else
                   "NO DATA / TIMEOUT")
        print(f"  run {i}: {status}  ({times[i-1]*1000:.3f} ms)")

    print_stats_table(args.rm_label, times, results, ciphertexts, inputs_log, args.mode)

    # exit code: fail only on an actual verified mismatch (fixed mode).
    # "OK"/None don't count as failures on their own, since random mode
    # has nothing to verify against -- but None (timeout/parse failure)
    # is still worth surfacing distinctly if you're scripting around this.
    if results and all(r is not False for r in results):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
