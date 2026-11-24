#!/usr/bin/env python3
"""Streamt die Antwort des Agenten Satz für Satz an `say` für niedrige Latenz."""
import sys, os, re, subprocess, signal


from pathlib import Path as _Path
STATUS_FILE = _Path.home() / ".heyjarvis/state/status"

def write_status(s):
    try:
        STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATUS_FILE.write_text(s)
    except Exception:
        pass

VOICE = os.environ.get("VOICE", "Anna")
RATE = os.environ.get("SAY_RATE", "220")
SENTENCE_END = re.compile(r'[.!?…]+(?:[\s\n]|$)|\n\n+')

def strip_markdown(text):
    text = re.sub(r'```[\s\S]*?```', ' ', text)
    text = re.sub(r'`([^`]+)`', r'\1', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'^#+\s*', '', text, flags=re.MULTILINE)
    text = re.sub(r'^[\s]*[-*+]\s+', '', text, flags=re.MULTILINE)
    return text

current = [None]

def cleanup(*_):
    if current[0] and current[0].poll() is None:
        current[0].terminate()
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

def speak(text):
    text = strip_markdown(text).strip()
    if not text:
        return
    if current[0] and current[0].poll() is None:
        current[0].wait()
    write_status("speak")
    current[0] = subprocess.Popen(
        ["say", "-v", VOICE, "-r", RATE, text],
        stdin=subprocess.DEVNULL,
    )

buf = ""
for chunk in iter(lambda: sys.stdin.read(64), ""):
    buf += chunk
    while True:
        m = SENTENCE_END.search(buf)
        if not m:
            break
        speak(buf[:m.end()])
        buf = buf[m.end():]
if buf.strip():
    speak(buf)
if current[0]:
    current[0].wait()
