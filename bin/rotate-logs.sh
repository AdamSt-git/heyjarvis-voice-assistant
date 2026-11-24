#!/usr/bin/env bash
set -uo pipefail
LOG_DIR="$HOME/.heyjarvis/logs"
MAX_SIZE=1048576   # 1 MB
KEEP=3             # Rotationen behalten
RETENTION_DAYS=14

cd "$LOG_DIR" 2>/dev/null || exit 0

# Für jede Log-Datei: wenn größer als MAX_SIZE → rotieren
for log in agent.err agent.out whisper.err timing.log wake-word.err wake-word.out wake.log clipboard.log hammerspoon.log; do
  [[ -f "$log" ]] || continue
  size=$(stat -f%z "$log" 2>/dev/null || echo 0)
  if (( size > MAX_SIZE )); then
    # Ältere rotieren: .3.gz löschen, .2.gz → .3.gz, etc.
    [[ -f "${log}.${KEEP}.gz" ]] && rm -f "${log}.${KEEP}.gz"
    for ((i=KEEP-1; i>=1; i--)); do
      [[ -f "${log}.${i}.gz" ]] && mv "${log}.${i}.gz" "${log}.$((i+1)).gz"
    done
    # Aktuelle Log: kopieren, truncaten, altes komprimieren
    cp "$log" "${log}.1"
    : > "$log"
    gzip -f "${log}.1"
  fi
done

# Alles älter als 14 Tage weg
find "$LOG_DIR" -type f \( -name "*.gz" -o -name "*.[0-9]" \) -mtime +${RETENTION_DAYS} -delete 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] rotate OK" >> "$LOG_DIR/rotate.log"
