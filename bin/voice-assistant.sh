#!/usr/bin/env bash
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# HeyJarvis – Haupt-Loop
#   1. Nimmt Mikrofon auf (Stille-Detektion via sox)
#   2. Transkribiert lokal mit whisper.cpp
#   3. Schickt das Transkript an den Agenten (headless, streaming)
#   4. Liest Antwort mit macOS 'say' vor
#
# Flags:
#   --once        Nur eine Runde, dann Ende (für Hotkey)
#   --project DIR Arbeitsverzeichnis für den Agenten (Default: ~)
#   --voice NAME  Stimme für 'say' (z. B. Anna, Markus; Default: Anna)
#   --model M     Modell für den Agenten (Default: dessen Standardmodell)

set -uo pipefail

BASE="$HOME/.heyjarvis"
WHISPER="$BASE/whisper.cpp/build/bin/whisper-cli"
MODEL_PATH="$BASE/whisper.cpp/models/ggml-small.bin"
LOG_DIR="$BASE/logs"
mkdir -p "$LOG_DIR"
TIMING_LOG="$LOG_DIR/timing.log"
_t() { python3 -c 'import time; print(f"{time.time():.3f}")'; }

set_status() {
  mkdir -p "$BASE/state" 2>/dev/null
  printf '%s' "$1" > "$BASE/state/status" 2>/dev/null
}


ONCE=0
PROJECT="$HOME"
VOICE="Anna"
# Follow-up + Gedächtnis
HISTORY_FILE="$BASE/state/history.jsonl"
HISTORY_MAX_TURNS=6
HISTORY_TTL_MIN=10
FOLLOWUP_SECONDS=12

MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)     ONCE=1; shift ;;
    --project)  PROJECT="$2"; shift 2 ;;
    --voice)    VOICE="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

cd "$PROJECT"

set_status idle  # Start

# Singleton-Modus: jeder neue Turn beendet den alten
stop_previous() {
  for pid in $(pgrep -f "voice-assistant.sh" 2>/dev/null); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
      kill "$pid" 2>/dev/null
    fi
  done
  killall say 2>/dev/null
  killall rec 2>/dev/null
  killall sox 2>/dev/null
  pkill -f whisper-cli 2>/dev/null
  pkill -f stream-say.py 2>/dev/null
  pkill -f "claude -p" 2>/dev/null
  sleep 0.2
  true
}
stop_previous
trap 'set_status idle 2>/dev/null; killall say 2>/dev/null; killall rec 2>/dev/null; pkill -f whisper-cli 2>/dev/null; pkill -f stream-say.py 2>/dev/null; pkill -f "claude -p" 2>/dev/null' EXIT INT TERM


record_one() {
  local out="$1"
  # 16 kHz mono WAV, beendet sich nach 1,2 s Stille
  rec -q -c 1 -r 16000 -b 16 "$out" \
      silence 1 0.3 2% 1 1.2 3% >/dev/null 2>&1
}

transcribe() {
  local wav="$1"
  # -l de = Deutsch, -ng = ohne GPU (läuft auf Intel und Apple Silicon)
  "$WHISPER" -m "$MODEL_PATH" -f "$wav" -l de -ng -otxt -of "${wav%.wav}" \
      >/dev/null 2>&1
  cat "${wav%.wav}.txt"
}

speak() {
  # Streaming: liest den Text während er eintrifft
  VOICE="$VOICE" SAY_RATE="220" python3 "$HOME/.heyjarvis/stream-say.py"
}

chime_in()  { afplay /System/Library/Sounds/Tink.aiff  2>/dev/null || true; }
chime_out() { afplay /System/Library/Sounds/Pop.aiff   2>/dev/null || true; }

check_history_ttl() {
  if [[ -f "$HISTORY_FILE" ]]; then
    local mtime now age
    mtime=$(stat -f %m "$HISTORY_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( (now - mtime) / 60 ))
    if (( age > HISTORY_TTL_MIN )); then
      rm -f "$HISTORY_FILE"
    fi
  fi
}

load_history_as_prompt() {
  [[ -f "$HISTORY_FILE" ]] || return 0
  [[ -s "$HISTORY_FILE" ]] || return 0
  python3 - "$HISTORY_FILE" "$HISTORY_MAX_TURNS" <<'PYHIST'
import json, sys
hf = sys.argv[1]; maxt = int(sys.argv[2])
try:
    lines = open(hf).read().strip().splitlines()
except Exception:
    sys.exit(0)
if not lines: sys.exit(0)
print("Bisheriger Gesprächsverlauf (für Kontext):")
for line in lines[-maxt:]:
    try:
        m = json.loads(line)
        role = "Nutzer" if m["role"] == "user" else "Du"
        print(f"{role}: {m['content']}")
    except Exception: pass
print()
print("Aktuelle Frage:")
PYHIST
}

append_history() {
  local role="$1" content="$2"
  mkdir -p "$(dirname "$HISTORY_FILE")"
  python3 -c '
import json, sys
print(json.dumps({"role": sys.argv[1], "content": sys.argv[2]}))
' "$role" "$content" >> "$HISTORY_FILE"
  local lines
  lines=$(wc -l < "$HISTORY_FILE" | tr -d " ")
  if (( lines > HISTORY_MAX_TURNS )); then
    tail -n "$HISTORY_MAX_TURNS" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && \
      mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
  fi
}

record_follow_up() {
  local wav="$1"
  rec -q -c 1 -r 16000 "$wav" \
    silence 1 0.3 2% 1 1.2 3% \
    trim 0 "$FOLLOWUP_SECONDS" 2>/dev/null || true
}

chime_follow() { afplay /System/Library/Sounds/Morse.aiff 2>/dev/null || true; }

run_turn() {
  local mode="${1:-initial}"
  local tmp
  tmp="$(mktemp -t heyjarvis).wav"
  local _t_start=$(_t)

  check_history_ttl

  set_status listen
  if [[ "$mode" == "followup" ]]; then
    echo "🎤  Follow-up (${FOLLOWUP_SECONDS}s Fenster)…"
    chime_follow
    record_follow_up "$tmp"
  else
    echo "🎤  Sprechen… (Stille beendet die Aufnahme)"
    chime_in
    record_one "$tmp"
  fi
  chime_out
  local _t_rec=$(_t)
  echo "📝  Transkribiere…"
  local text
  text="$(transcribe "$tmp" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  rm -f "$tmp" "${tmp%.wav}.txt"

  if [[ -z "$text" ]]; then
    echo "… nichts verstanden."
    set_status idle
    return 1
  fi
  local _t_trans=$(_t)
  echo "🗣️   Du: $text"
  append_history user "$text"
  echo "🤖  Antwort kommt…"

  local ctx full_prompt
  ctx="$(load_history_as_prompt)"
  if [[ -n "$ctx" ]]; then
    full_prompt="${ctx}
${text}"
  else
    full_prompt="$text"
  fi

  local resp_file
  resp_file="$(mktemp -t heyjarvis-resp)"
  set_status think
  # Rechte gelten nur für den Assistenten: --settings lädt die Freigabeliste
  # aus ~/.heyjarvis/settings.json (open, osascript, curl, ...).
  # acceptEdits erlaubt Dateiänderungen, alles andere nur laut Liste.
  # Was dort auf "ask" steht, wird im Sprachmodus abgelehnt.
  claude -p "$full_prompt" ${MODEL:+--model "$MODEL"} \
    --permission-mode acceptEdits \
    --settings "$BASE/settings.json" \
    --append-system-prompt "$(cat "$BASE/system-prompt.md")" \
    2>>"$LOG_DIR/agent.err" | tee -a "$LOG_DIR/agent.out" | tee "$resp_file" | speak

  local response
  response="$(cat "$resp_file" 2>/dev/null | tr -d '\r')"
  [[ -n "$response" ]] && append_history assistant "$response"
  rm -f "$resp_file"
  local _t_end=$(_t)
  python3 -c "
t0=$_t_start; t1=$_t_rec; t2=$_t_trans; t3=$_t_end
print(f'rec={t1-t0:.2f}s whisper={t2-t1:.2f}s agent+tts={t3-t2:.2f}s total={t3-t0:.2f}s')" >> "$TIMING_LOG"
  set_status idle
  echo ""
  return 0
}

if [[ $ONCE -eq 1 ]]; then
  if run_turn initial; then
    while run_turn followup; do :; done
  fi
else
  echo "HeyJarvis läuft (Ctrl+C zum Beenden)."
  while true; do
    if run_turn initial; then
      while run_turn followup; do :; done
    fi
    sleep 0.3
  done
fi