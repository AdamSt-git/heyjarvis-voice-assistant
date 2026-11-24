# HeyJarvis: Voice Assistant for macOS

A voice assistant for the Mac: say "Hey Jarvis" or press a hotkey, speak, and get a spoken answer. Speech recognition runs locally with whisper.cpp, a command-line agent handles the request, and the built-in macOS voice reads the reply. HeyJarvis answers questions, opens apps and websites, controls apps via AppleScript, searches the web and creates files, all by voice.

One of my first larger personal projects, built in April 2026 as a working prototype.

## Features

- **Wake word and hotkeys:** "Hey Jarvis" starts a turn hands-free, `⌃⌥⌘V` starts one by hotkey, `⌃⌥⌘W` switches the wake word on and off, `⌃⌥⌘X` stops everything
- **Local speech recognition** with whisper.cpp, no audio leaves the Mac
- **Streaming speech:** the answer is spoken sentence by sentence while it is still being generated, Markdown is stripped before speaking
- **Follow-up questions:** after an answer, HeyJarvis listens for 12 more seconds, no need to say the wake word again
- **Short-term memory:** the last six messages are passed along as context and expire after ten minutes
- **Interrupting:** a new turn stops the current answer immediately
- **Menu bar status** via Hammerspoon: idle, listening, thinking or speaking
- **Timing log** for every turn (recording, transcription, answer) and nightly log rotation
- **Voice switcher** for all installed German macOS voices

## How it works

```
Wake word / hotkey ─► sox records ─► whisper.cpp transcribes ─► agent answers ─► stream-say.py ─► macOS say
  (openWakeWord,       until silence     locally (German)          with voice prompt   sentence by
   Hammerspoon)                                                    and permission list sentence
```

| File | Role |
|---|---|
| `bin/voice-assistant.sh` | main loop: record, transcribe, ask the agent, speak, follow-up and memory |
| `bin/stream-say.py` | splits the streamed answer into sentences and speaks them |
| `bin/wake-word.py` | listens for "Hey Jarvis" with openWakeWord |
| `bin/change-voice.sh` | interactive voice switcher |
| `bin/rotate-logs.sh` | keeps the logs small |
| `config/system-prompt.md` | voice prompt: short answers, no Markdown, rules for actions |
| `config/settings.json` | permission list for the assistant |
| `config/hammerspoon-init.lua` | hotkeys and menu bar |
| `launchd/` | optional autostart templates |
| `install.sh` | installs everything into `~/.heyjarvis` |

## Installation

Requirements: macOS, Homebrew and an account for Claude Code, the command-line agent HeyJarvis uses. `install.sh` sets it up if it is missing.

```bash
./install.sh
```

The script installs sox, ffmpeg, Python and Hammerspoon, builds whisper.cpp, downloads the `small` model (about 466 MB) and sets up openWakeWord. With `./install.sh --autostart` the wake word also starts at login.

Afterwards, allow microphone access for Terminal and Hammerspoon and accessibility access for Hammerspoon in System Settings.

## Safety and permissions

A voice assistant is meant to act on spoken commands, so it deserves a careful setup. Please review `config/settings.json` before you use it.

- The permissions apply **only to HeyJarvis**. They are loaded with `--settings` and do not change any global settings.
- The agent may **create and edit files** without asking (`acceptEdits`).
- Shell commands run only if they are on the allow list: `open`, `osascript`, `curl`, `say` and a few more. `osascript` can control other apps, so remove it if you do not need that.
- `sudo`, `rm`, `git push` and similar commands need a confirmation, which the voice mode cannot give, so they are not run. Commands like `dd` and `mkfs` are blocked outright.
- The voice prompt asks for a confirmation before purchases, messages or installations.

## Prototype limits

- **Wake word:** "Hey Jarvis" is a ready-made openWakeWord model and sometimes triggers on TV, music or conversations. For daily use, train your own wake word or raise the threshold in `wake-word.py`, or use only the hotkey.
- **Interrupting** stops all running `say` processes on the Mac, not only the assistant's.
- **Speed:** a turn takes a few seconds, mostly for transcription and the answer.
- **Language:** recognition and voice prompt are set up for German.

The project is paused at the moment. This repository contains the latest version; after cleaning it up for GitHub it was checked for syntax, but not run again end to end.
