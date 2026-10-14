#!/usr/bin/env python3
"""Verify the actual macOS distributable, with an optional isolated CI launch."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()


parser = argparse.ArgumentParser()
parser.add_argument('archive', type=Path)
parser.add_argument('--launch', action='store_true')
args = parser.parse_args()
if args.launch and os.environ.get('CI') != 'true':
    parser.error('--launch is restricted to disposable CI machines; it uses the normal application container')
root = Path(__file__).resolve().parent.parent
archive = args.archive.resolve()
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
assert archive.with_suffix(archive.suffix + '.sha256').read_text().split()[0] == sha, 'Archive checksum mismatch'
commit = run('git', '-C', str(root), 'rev-parse', 'HEAD')
expected_version = os.environ.get('TELEPHONE_MARKETING_VERSION') or re.search(
    r'"MARKETING_VERSION":\s*"([0-9.]+)"',
    (root / 'Telephone.xcodeproj/project.xcproj').read_text(),
).group(1)
expected_build = os.environ.get('TELEPHONE_BUILD_NUMBER') or run('git', '-C', str(root), 'rev-list', '--count', 'HEAD')
expected_commit = os.environ.get('TELEPHONE_BUILD_COMMIT') or commit[:7]
assert commit.startswith(expected_commit), 'Build source commit mismatch'

with tempfile.TemporaryDirectory(prefix='telephone-package-') as scratch:
    run('/usr/bin/ditto', '-x', '-k', str(archive), scratch)
    app = (Path(scratch) / 'Telephone.app').resolve()
    with (app / 'Contents/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    assert info['CFBundleIdentifier'] == 'com.tlphn.Telephone', 'Bundle identifier changed'
    assert info['CFBundleShortVersionString'] == expected_version, 'Marketing version mismatch'
    assert info['CFBundleVersion'] == expected_build, 'Build number mismatch'
    assert info['TelephoneBuildCommit'] == expected_commit, 'Embedded commit mismatch'
    assert info['LSMinimumSystemVersion'] == '26.0', 'Unexpected minimum macOS version'
    binaries = [app / 'Contents/MacOS/Telephone']
    binaries.extend(sorted((app / 'Contents/Frameworks').glob('*.framework/Versions/A/*')))
    machos = []
    for binary in binaries:
        if binary.is_file() and 'Mach-O' in run('/usr/bin/file', '-b', str(binary)):
            assert run('/usr/bin/lipo', '-archs', str(binary)) == 'arm64', 'Unexpected binary architecture'
            machos.append(str(binary.relative_to(app)))
    assert len(machos) == 3, 'Expected application and two embedded frameworks'
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    entitlements = plistlib.loads(subprocess.check_output(
        ['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL,
    ))
    for key in ['app-sandbox', 'network.client', 'network.server', 'device.microphone']:
        assert entitlements.get('com.apple.security.' + key) is True, 'Required entitlement missing: ' + key
    launched = False
    if args.launch:
        # Never terminate an unrelated Telephone process or use saved CI accounts.
        existing = subprocess.run(['/usr/bin/pgrep', '-x', 'Telephone'], capture_output=True, text=True)
        assert existing.returncode == 1, 'Telephone already running; refusing to disturb it'
        pid = None
        launcher = subprocess.Popen([
            '/usr/bin/open', '-n', '-W', str(app), '--args',
            '-Accounts', '()', '-Telephone.CRMGateway.enabled', 'NO',
        ])
        try:
            for _ in range(20):
                found = subprocess.run(['/usr/bin/pgrep', '-x', 'Telephone'], capture_output=True, text=True)
                if found.returncode == 0:
                    ids = found.stdout.split()
                    assert len(ids) == 1, 'Unexpected multiple Telephone processes'
                    candidate = int(ids[0])
                    command = run('/bin/ps', '-ww', '-p', str(candidate), '-o', 'comm=')
                    assert command == str(app / 'Contents/MacOS/Telephone'), 'Wrong application launched'
                    pid = candidate
                    break
                assert launcher.poll() is None, 'Packaged app exited during launch'
                time.sleep(0.5)
            assert pid is not None, 'Packaged app did not launch'
            time.sleep(3)
            os.kill(pid, 0)
            assert launcher.poll() is None, 'Packaged app quit unexpectedly'
            launched = True
        finally:
            if pid is not None:
                process = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'comm='], capture_output=True, text=True)
                if process.returncode == 0:
                    assert process.stdout.strip() == str(app / 'Contents/MacOS/Telephone'), 'Refusing to stop another process'
                    try:
                        os.kill(pid, 15)
                    except ProcessLookupError:
                        pass
            try:
                launcher.wait(timeout=10)
            except subprocess.TimeoutExpired:
                if pid is not None:
                    process = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'comm='], capture_output=True, text=True)
                    if process.returncode == 0:
                        assert process.stdout.strip() == str(app / 'Contents/MacOS/Telephone'), 'Refusing to stop another process'
                        os.kill(pid, 9)
                launcher.terminate()
                launcher.wait(timeout=5)
            if pid is not None:
                for _ in range(20):
                    process = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'comm='], capture_output=True, text=True)
                    if process.returncode != 0:
                        break
                    assert process.stdout.strip() == str(app / 'Contents/MacOS/Telephone'), 'Process identity changed during cleanup'
                    time.sleep(0.1)
                else:
                    raise RuntimeError('Packaged app did not stop; refusing to continue to UI tests')
    report = dict(
        version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
        commit=commit, embeddedCommit=info['TelephoneBuildCommit'],
        bundleIdentifier=info['CFBundleIdentifier'], minimumMacOS=info['LSMinimumSystemVersion'],
        architecture='arm64', verifiedMachOBinaries=machos, sha256=sha,
        signatureVerified=True, sandboxVerified=True, nativeLaunchVerified=launched,
        notarized=False,
    )
    archive.with_suffix('.verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
