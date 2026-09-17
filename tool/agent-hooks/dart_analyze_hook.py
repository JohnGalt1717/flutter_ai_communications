#!/usr/bin/env python3
"""Grok Build and GitHub Copilot hooks for dart analyze.

Modes:
  after-save   PostToolUse after a file write. Force-fix ERROR/WARNING in the
               saved files. Diagnostics only in other files are a mid-refactor
               and are left for the next save or the before-run gate.
  before-run   PreToolUse before flutter/dart test or run. Deny unless the
               whole workspace is clean.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

EDIT_TOOLS = re.compile(
    r'(search_replace|write|Write|Edit|create|edit|str_replace_editor|'
    r'apply_patch|MultiEdit)$',
    re.I,
)
LAUNCH_TOOLS = re.compile(r'launch_app', re.I)
RUN_RE = re.compile(
    r'(?:^|[;&|\n]|\b(?:then|do|if)\b)\s*(?:flutter|dart)\s+'
    r'(?:test|run|drive)\b',
    re.I,
)
ANALYZE_SELF_RE = re.compile(
    r'\b(?:dart|flutter)\s+analyze\b|\bdart_analyze_hook\.py\b',
    re.I,
)


def _read_event() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _tool_name(event: dict[str, Any]) -> str:
    for key in ('toolName', 'tool_name'):
        value = event.get(key)
        if isinstance(value, str) and value:
            return value
    return ''


def _tool_input(event: dict[str, Any]) -> dict[str, Any]:
    for key in ('toolInput', 'tool_input', 'toolArgs', 'tool_args'):
        value = event.get(key)
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                return {}
        if isinstance(value, dict):
            return value
    return {}


def _workspace(event: dict[str, Any]) -> Path:
    for key in (
        os.environ.get('GROK_WORKSPACE_ROOT'),
        os.environ.get('CLAUDE_PROJECT_DIR'),
        event.get('workspaceRoot'),
        event.get('workspace_root'),
        event.get('cwd'),
    ):
        if isinstance(key, str) and key and Path(key).is_dir():
            root = Path(key)
            if (root / 'pubspec.yaml').exists():
                return root
    try:
        out = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except OSError:
        pass
    return Path.cwd()


def _paths_from(node: Any, found: list[str]) -> None:
    if isinstance(node, str) and node:
        found.append(node)
        return
    if isinstance(node, list):
        for item in node:
            _paths_from(item, found)
        return
    if not isinstance(node, dict):
        return
    for key in ('file_path', 'filePath', 'path', 'target_file'):
        value = node.get(key)
        if isinstance(value, str) and value:
            found.append(value)
    for key in ('files', 'edits'):
        if key in node:
            _paths_from(node[key], found)


def _is_analyze_target(path: Path) -> bool:
    name = path.name
    if name in {'pubspec.yaml', 'analysis_options.yaml'}:
        return True
    return path.suffix == '.dart'


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write('\n')


def _allow() -> None:
    _emit(
        {
            'decision': 'allow',
            'permissionDecision': 'allow',
        }
    )


def _dart_bin() -> str | None:
    return shutil.which('dart')


def _analyze(root: Path, targets: list[Path] | None) -> list[dict[str, str]]:
    dart = _dart_bin()
    if dart is None:
        return []
    cmd = [dart, 'analyze', '--format=json']
    if targets:
        cmd.extend(str(path) for path in targets)
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    blob = proc.stdout or proc.stderr
    start = blob.find('{')
    if start < 0:
        return []
    try:
        data = json.loads(blob[start:])
    except json.JSONDecodeError:
        return []
    diags = data.get('diagnostics') if isinstance(data, dict) else None
    if not isinstance(diags, list):
        return []
    out: list[dict[str, str]] = []
    for item in diags:
        if not isinstance(item, dict):
            continue
        severity = str(item.get('severity') or '').upper()
        if severity not in {'ERROR', 'WARNING'}:
            continue
        loc = item.get('location') if isinstance(item.get('location'), dict) else {}
        file = str(loc.get('file') or loc.get('path') or '')
        rng = loc.get('range') if isinstance(loc.get('range'), dict) else {}
        start_loc = rng.get('start') if isinstance(rng.get('start'), dict) else {}
        line = start_loc.get('line') or loc.get('line') or ''
        message = str(item.get('problemMessage') or item.get('message') or '')
        code = str(item.get('code') or '')
        out.append(
            {
                'severity': severity,
                'file': file,
                'line': str(line),
                'code': code,
                'message': message,
            }
        )
    return out


def _format_diags(diags: list[dict[str, str]], limit: int = 20) -> str:
    lines = []
    for item in diags[:limit]:
        loc = item['file']
        if item['line']:
            loc = f'{loc}:{item["line"]}'
        code = f' ({item["code"]})' if item['code'] else ''
        lines.append(f'- {item["severity"]} {loc}{code}: {item["message"]}')
    extra = len(diags) - limit
    if extra > 0:
        lines.append(f'- … {extra} more')
    return '\n'.join(lines)


def _same_file(left: str, right: Path) -> bool:
    try:
        return Path(left).resolve() == right.resolve()
    except OSError:
        return os.path.normpath(left) == os.path.normpath(str(right))


def after_save(event: dict[str, Any]) -> None:
    name = _tool_name(event)
    if name and not EDIT_TOOLS.search(name):
        return
    payload = _tool_input(event)
    raw_paths: list[str] = []
    _paths_from(payload, raw_paths)
    if not raw_paths and not name:
        return
    root = _workspace(event)
    saved: list[Path] = []
    for raw in raw_paths:
        path = Path(raw)
        if not path.is_absolute():
            path = (root / path).resolve()
        if _is_analyze_target(path):
            saved.append(path)
    if not saved:
        return
    if _dart_bin() is None:
        return
    diags = _analyze(root, saved)
    in_saved = [
        item
        for item in diags
        if any(_same_file(item['file'], path) for path in saved)
    ]
    if not in_saved:
        return
    listed_names: list[str] = []
    for path in saved:
        try:
            listed_names.append(str(path.relative_to(root)))
        except ValueError:
            listed_names.append(str(path))
    listed = ', '.join(listed_names)
    msg = (
        'dart analyze found issues in the file(s) just saved. Fix these now. '
        'Errors in other files may wait only while a multi-file refactor is '
        f'still in flight.\nSaved: {listed}\n{_format_diags(in_saved)}'
    )
    _emit(
        {
            'decision': 'block',
            'reason': msg,
            'additionalContext': msg,
            'hookSpecificOutput': {
                'hookEventName': 'PostToolUse',
                'additionalContext': msg,
            },
        }
    )


def _command_text(event: dict[str, Any]) -> str:
    payload = _tool_input(event)
    for key in ('command', 'cmd', 'script'):
        value = payload.get(key)
        if isinstance(value, str):
            return value
    extra = payload.get('extra_args')
    if isinstance(extra, list):
        return ' '.join(str(item) for item in extra)
    return ''


def before_run(event: dict[str, Any]) -> None:
    name = _tool_name(event)
    command = _command_text(event)
    launch = bool(name and LAUNCH_TOOLS.search(name))
    run = bool(command and RUN_RE.search(command))
    if not launch and not run:
        _allow()
        return
    if command and ANALYZE_SELF_RE.search(command):
        _allow()
        return
    if _dart_bin() is None:
        _allow()
        return
    root = _workspace(event)
    diags = _analyze(root, None)
    if not diags:
        _allow()
        return
    msg = (
        'Workspace dart analyze is not clean. Fix every ERROR and WARNING '
        'before flutter test, dart test, flutter run, or launching the '
        f'example.\n{_format_diags(diags)}'
    )
    _emit(
        {
            'decision': 'deny',
            'reason': msg,
            'permissionDecision': 'deny',
            'permissionDecisionReason': msg,
        }
    )


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {'after-save', 'before-run'}:
        print('usage: dart_analyze_hook.py after-save|before-run', file=sys.stderr)
        return 0
    try:
        event = _read_event()
        if sys.argv[1] == 'after-save':
            after_save(event)
        else:
            before_run(event)
    except Exception as exc:  # noqa: BLE001 — hooks must fail open
        print(f'dart_analyze_hook failed open: {exc}', file=sys.stderr)
        if sys.argv[1] == 'before-run':
            _allow()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
