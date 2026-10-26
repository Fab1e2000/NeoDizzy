#!/usr/bin/env python3
"""Install an opt-in Release diagnostic build, or collect its bounded captures.

python3 scripts/player-transition-diagnostics.py prepare --device 溪泠
python3 scripts/player-transition-diagnostics.py collect --device 溪泠

Each capture ends on settle/close (or after 20 seconds). Data is buffered during
animation; only the latest 30 captures are retained. Callback gaps are not GPU
frame-delivery measurements. Install a normal build to disable instrumentation.
"""
import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(args, log=None):
    subprocess.run(args, cwd=ROOT, check=True, stdout=log,
                   stderr=subprocess.STDOUT if log else None)


def summarize(directory):
    records = []
    for path in directory.rglob('transition-*.json'):
        data = json.loads(path.read_text())
        samples = data['samples']
        gaps = [s for s in samples if s['callbackGap'] > max(0.020, s['displayInterval'] * 1.8)]
        records.append({
            'file': str(path), 'date': data['date'], 'samples': len(samples),
            'events': data['events'],
            'maxCallbackGapMs': round(max((s['callbackGap'] for s in samples), default=0) * 1000, 2),
            'longCallbackGaps': gaps,
        })
    return sorted(records, key=lambda r: r['date'])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('action', choices=['prepare', 'collect'])
    parser.add_argument('--device', required=True)
    parser.add_argument('--bundle-id', default='com.elsterlee.NeoDizzy')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='neodizzy-player-diagnostics-'))
    output.mkdir(parents=True, exist_ok=True)
    print(f'Evidence: {output}', flush=True)
    device = ['--device', args.device]
    if args.action == 'prepare':
        settings = ['-project', 'NeoDizzy.xcodeproj', '-scheme', 'NeoDizzy', '-configuration', 'Release',
                    '-destination', f'platform=iOS,id={args.device}',
                    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PLAYER_TRANSITION_DIAGNOSTICS',
                    'ENABLE_TESTABILITY=YES']
        # Names are accepted by devicectl, but xcodebuild needs name= for names.
        if not re.fullmatch(r'[0-9A-Fa-f-]{24,40}', args.device):
            settings[settings.index('-destination') + 1] = f'platform=iOS,name={args.device}'
        with (output / 'build.log').open('w') as log:
            run(['xcodebuild', 'build', *settings], log)
        result = subprocess.run(['xcodebuild', '-showBuildSettings', '-json', *settings],
                                cwd=ROOT, check=True, capture_output=True, text=True)
        target = next(item['buildSettings'] for item in json.loads(result.stdout) if item['target'] == 'NeoDizzy')
        app = str(Path(target['TARGET_BUILD_DIR']) / target['FULL_PRODUCT_NAME'])
        run(['xcrun', 'devicectl', 'device', 'install', 'app', *device, app])
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', *device,
             '--terminate-existing', args.bundle_id])
        (output / 'build-info.json').write_text(json.dumps({'app': app, 'diagnostics': True}, indent=2))
        print('Diagnostic build launched. Reproduce, let the player settle/close, then run collect.')
    else:
        captures = output / 'captures'
        if captures.exists():
            parser.error('Use a new output directory; captures already exists.')
        run(['xcrun', 'devicectl', 'device', 'copy', 'from', *device,
             '--domain-type', 'appDataContainer', '--domain-identifier', args.bundle_id,
             '--source', 'Documents/PlayerTransitionDiagnostics', '--destination', str(captures)])
        records = summarize(captures)
        (output / 'summary.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
        for record in records:
            print(f"{record['date']}  {record['samples']} samples  max callback gap {record['maxCallbackGapMs']} ms  "
                  f"{len(record['longCallbackGaps'])} long gaps")
        print(f'{len(records)} captures collected. See summary.json; gaps do not establish GPU hitches or causality.')


if __name__ == '__main__':
    main()
