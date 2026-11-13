#!/usr/bin/env python3
"""Run native GDScript integration without relying on Godot's assertion exit code."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
sys.stderr.reconfigure(encoding='utf-8', errors='replace')

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--expect-no-device', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
common = [args.godot, '--headless', '--path', str(root / 'demo')]
# Godot #111048: immediate exit during first extension discovery races doc generation.
# Keep the editor alive for bounded iterations so deferred documentation work finishes.
# https://github.com/godotengine/godot/issues/111048
editor_flags = ['--editor', '--quit-after', '120', '--frame-delay', '50']

# Distinguish host/editor failures from addon failures before loading project scripts.
for with_extension in (False, True):
    with tempfile.TemporaryDirectory(prefix='godot_host_check_') as folder:
        project = Path(folder)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="JUCE integration host check"\n', encoding='utf-8')
        if with_extension:
            target = project / 'addons/juce_bridge/bin'
            target.mkdir(parents=True)
            for source in (root / 'demo/addons/juce_bridge/bin').glob('*'):
                if source.suffix in ('.dll', '.so'):
                    shutil.copy2(source, target / source.name)
            shutil.copy2(root / 'demo/addons/juce_bridge/juce_bridge.gdextension', target.parent / 'juce_bridge.gdextension')
        label = 'extension-only project' if with_extension else 'empty Godot project'
        print('Checking ' + label, flush=True)
        result = subprocess.run([args.godot, '--headless', '--path', folder] + editor_flags, text=True, encoding='utf-8', errors='replace', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        print(result.stdout, flush=True)
        if result.returncode != 0 or 'ERROR:' in result.stdout:
            raise SystemExit('Godot host check failed: ' + label)
checks = [(editor_flags, None),
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
