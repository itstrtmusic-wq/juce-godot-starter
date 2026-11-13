#!/usr/bin/env python3
"""Run native GDScript integration without relying on Godot's assertion exit code."""
import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--expect-no-device', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
common = [args.godot, '--headless', '--path', str(root / 'demo')]
checks = [(['--editor', '--import'], None),
          (['--script', 'res://api_test.gd'], 'JUCE API:'),
          (['--script', 'res://smoke_test.gd'], 'GDScript registration'),
          (['--script', 'res://examples/offline_processing.gd'], 'Rendered:'),
          (['--quit-after', '5'], None)]
for tail, marker in checks:
    if '--script' in tail:
        tail = ['--quit-after', '120'] + tail
    if args.expect_no_device and '--script' in tail and tail[-1] != 'res://examples/offline_processing.gd':
        tail += ['--', '--expect-no-device']
    try:
        result = subprocess.run(common + tail, text=True, encoding='utf-8', errors='replace', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    except subprocess.TimeoutExpired as exc:
        print(exc.stdout or '', file=sys.stderr)
        raise SystemExit('Godot test timed out (possible failed assertion)')
    print(result.stdout, end='', flush=True)
    if result.returncode != 0 or 'SCRIPT ERROR:' in result.stdout or 'ERROR:' in result.stdout or (marker and marker not in result.stdout):
        raise SystemExit('Godot integration check failed: ' + ' '.join(tail))
print('All Godot integration checks passed')
