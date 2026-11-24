#!/usr/bin/env bash
# HeyJarvis – Installer für macOS
# Richtet whisper.cpp (lokale Spracherkennung), sox (Audio), openWakeWord (Wake-Word)
# und Hammerspoon (Hotkeys und Menüleiste) ein und kopiert alles nach ~/.heyjarvis.
#
#   ./install.sh               Installation ohne Autostart
#   ./install.sh --autostart   zusätzlich Wake-Word beim Anmelden und nächtliche Log-Rotation

set -euo pipefail

AUTOSTART=0
[[ "${1:-}" == "--autostart" ]] && AUTOSTART=1

PROJECT_DIR="$HOME/.heyjarvis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$PROJECT_DIR/bin" "$PROJECT_DIR/logs" "$PROJECT_DIR/state"

echo "==> 1/7  Homebrew prüfen"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew nicht gefunden. Bitte erst installieren: https://brew.sh"
  exit 1
fi

echo "==> 2/7  Kernpakete installieren (sox, cmake, ffmpeg, python@3.12, hammerspoon)"
brew install sox cmake ffmpeg python@3.12 || true
brew install --cask hammerspoon || true

echo "==> 3/7  Agent-CLI installieren (falls nicht vorhanden)"
if ! command -v claude >/dev/null 2>&1; then
  brew install node
  npm install -g @anthropic-ai/claude-code
fi

echo "==> 4/7  whisper.cpp klonen und kompilieren"
if [ ! -d "$PROJECT_DIR/whisper.cpp" ]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$PROJECT_DIR/whisper.cpp"
fi
cd "$PROJECT_DIR/whisper.cpp"
# small: gute Qualität für Deutsch, base: schneller, dafür ungenauer
bash ./models/download-ggml-model.sh small
cmake -B build >/dev/null
cmake --build build -j --config Release >/dev/null
cd - >/dev/null

echo "==> 5/7  Python-venv + openWakeWord installieren"
python3.12 -m venv "$PROJECT_DIR/venv"
# shellcheck disable=SC1091
source "$PROJECT_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install openwakeword sounddevice numpy scipy >/dev/null
deactivate

echo "==> 6/7  Dateien nach ~/.heyjarvis kopieren"
cp "$SCRIPT_DIR/bin/voice-assistant.sh" "$PROJECT_DIR/voice-assistant.sh"
cp "$SCRIPT_DIR/bin/stream-say.py"      "$PROJECT_DIR/stream-say.py"
cp "$SCRIPT_DIR/bin/wake-word.py"       "$PROJECT_DIR/wake-word.py"
cp "$SCRIPT_DIR/bin/change-voice.sh"    "$PROJECT_DIR/change-voice.sh"
cp "$SCRIPT_DIR/bin/rotate-logs.sh"     "$PROJECT_DIR/bin/rotate-logs.sh"
cp "$SCRIPT_DIR/config/system-prompt.md"       "$PROJECT_DIR/system-prompt.md"
cp "$SCRIPT_DIR/config/settings.json"   "$PROJECT_DIR/settings.json"
chmod +x "$PROJECT_DIR/voice-assistant.sh" "$PROJECT_DIR/stream-say.py" \
         "$PROJECT_DIR/wake-word.py" "$PROJECT_DIR/change-voice.sh" "$PROJECT_DIR/bin/rotate-logs.sh"

# Hammerspoon-Config übernehmen (nur wenn noch nichts existiert)
HAMMER_CFG="$HOME/.hammerspoon/init.lua"
mkdir -p "$HOME/.hammerspoon"
if [ ! -f "$HAMMER_CFG" ]; then
  cp "$SCRIPT_DIR/config/hammerspoon-init.lua" "$HAMMER_CFG"
  echo "   Hammerspoon-Config nach $HAMMER_CFG kopiert."
else
  cp "$SCRIPT_DIR/config/hammerspoon-init.lua" "$PROJECT_DIR/hammerspoon-snippet.lua"
  echo "   Vorhandene Hammerspoon-Config gefunden – Snippet liegt in $PROJECT_DIR/hammerspoon-snippet.lua."
fi

echo "==> 7/7  Autostart"
if [[ $AUTOSTART -eq 1 ]]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  for p in com.heyjarvis.wake com.heyjarvis.logrotate; do
    sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/launchd/$p.plist" > "$HOME/Library/LaunchAgents/$p.plist"
    launchctl unload "$HOME/Library/LaunchAgents/$p.plist" 2>/dev/null || true
    launchctl load "$HOME/Library/LaunchAgents/$p.plist"
  done
  echo "   Wake-Word startet beim Anmelden, Logs werden nachts rotiert."
else
  echo "   Übersprungen. Mit ./install.sh --autostart einschalten."
fi

cat <<EOF

Fertig!

Nächste Schritte:
  1. Mikrofon für Terminal und Hammerspoon erlauben:
       Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon
  2. Hammerspoon öffnen und unter Bedienungshilfen erlauben.
  3. Freigabeliste prüfen und bei Bedarf anpassen (gilt nur für den Assistenten):
       ~/.heyjarvis/settings.json
  4. Test: ⌃⌥⌘V drücken, sprechen, Antwort abwarten.
  5. Wake-Word an/aus: ⌃⌥⌘W, alles stoppen: ⌃⌥⌘X

EOF
