#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$HOME/.heyjarvis/voice-assistant.sh"
[ -f "$SCRIPT" ] || { echo "Fehler: $SCRIPT nicht gefunden."; exit 1; }
echo
echo "Aktuell gesetzte Stimme:"
grep '^VOICE=' "$SCRIPT" | head -1
echo
IFS=$'\n' read -r -d '' -a voices < <(
  say -v '?' | awk '/de_DE/ {
    match($0, / {2,}/);
    print substr($0, 1, RSTART-1);
  }' && printf '\0'
)
[ ${#voices[@]} -gt 0 ] || { echo "Keine deutschen Stimmen gefunden."; exit 1; }
echo "Verfügbare deutsche Stimmen:"
for i in "${!voices[@]}"; do
  printf "  %2d) %s\n" "$((i+1))" "${voices[$i]}"
done
echo
read -r -p "Nummer wählen: " num
[[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#voices[@]}" ] || { echo "Ungültig."; exit 1; }
selected="${voices[$((num-1))]}"
echo
echo "Hörprobe: $selected"
say -v "$selected" "Hallo, ich bin deine neue Stimme. Klinge ich gut?"
echo
read -r -p "Übernehmen? (j/n) " ok
[ "$ok" = "j" ] || [ "$ok" = "J" ] || { echo "Abgebrochen."; exit 0; }
sed -i '' "s|^VOICE=.*|VOICE=\"$selected\"|" "$SCRIPT"
echo "Fertig. Neue Stimme eingetragen: $selected"
