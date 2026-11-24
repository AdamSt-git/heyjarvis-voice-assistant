#!/usr/bin/env python3
"""
Wake-Word-Lauscher für HeyJarvis (v3).
- Hört dauerhaft auf 'Hey Jarvis' mit openWakeWord
- Baut den Audio-Stream pro Turn komplett neu auf (robust auf macOS)
- Setzt das Modell zurück → keine Ghost-Trigger
- Chime signalisiert, wenn wieder aktiv gelauscht wird
"""
import os
import queue
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import sounddevice as sd
from openwakeword.model import Model

BASE = Path.home() / ".heyjarvis"
ASSISTANT = BASE / "voice-assistant.sh"

SAMPLE_RATE = 16_000
CHUNK = 1280
THRESHOLD = 0.35
COOLDOWN_S = 1.5
WAKE_MODELS = ["hey_jarvis"]

q: "queue.Queue[np.ndarray]" = queue.Queue()


def audio_cb(indata, frames, time_info, status):
    if status:
        print(status, file=sys.stderr)
    q.put((indata[:, 0] * 32767).astype(np.int16).copy())


def drain_queue() -> None:
    while not q.empty():
        try:
            q.get_nowait()
        except queue.Empty:
            break


def chime_ready() -> None:
    subprocess.Popen(
        ["afplay", "/System/Library/Sounds/Glass.aiff"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def reset_model(model) -> None:
    try:
        if hasattr(model, "reset"):
            model.reset()
    except Exception as exc:
        print(f"(Hinweis: model.reset() fehlgeschlagen: {exc})", file=sys.stderr)


def listen_for_wake(model) -> str:
    """Blockiert bis Wake-Word erkannt wird. Gibt den Trigger-Namen zurück."""
    drain_queue()
    stream = sd.InputStream(
        channels=1,
        samplerate=SAMPLE_RATE,
        blocksize=CHUNK,
        dtype="float32",
        callback=audio_cb,
    )
    stream.start()
    try:
        last_trigger = 0.0
        while True:
            frame = q.get()
            scores = model.predict(frame)
            for name, score in scores.items():
                if score > THRESHOLD and (time.time() - last_trigger) > COOLDOWN_S:
                    last_trigger = time.time()
                    print(f"\n🟢 Wake-Word erkannt ({name}: {score:.2f}) – starte Sprachrunde…")
                    return name
    finally:
        stream.stop()
        stream.close()


def main() -> None:
    print("Lade openWakeWord-Modell…")
    model = Model(wakeword_models=WAKE_MODELS, inference_framework="onnx")
    print(f"Lausche auf {WAKE_MODELS} (Threshold {THRESHOLD}). Ctrl+C zum Beenden.")

    while True:
        listen_for_wake(model)
        # Stream ist zu, Mikro jetzt frei für sox/rec
        subprocess.run(
            ["/bin/zsh", "-lc", f'"{ASSISTANT}" --once'],
            env={**os.environ},
        )
        time.sleep(0.5)
        reset_model(model)
        drain_queue()
        chime_ready()
        print("Wieder im Lausch-Modus.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nBeendet.")
