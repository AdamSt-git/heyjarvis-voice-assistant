-- Hammerspoon-Config für HeyJarvis (v3, zsh Login-Shell)

local ASSISTANT   = os.getenv("HOME") .. "/.heyjarvis/voice-assistant.sh"
local WAKE_SCRIPT = os.getenv("HOME") .. "/.heyjarvis/wake-word.py"
local VENV_PY     = os.getenv("HOME") .. "/.heyjarvis/venv/bin/python"
local LOG_FILE    = os.getenv("HOME") .. "/.heyjarvis/logs/hammerspoon.log"

local function logToFile(tag, text)
  if not text or text == "" then return end
  local f = io.open(LOG_FILE, "a")
  if f then
    f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tag .. ": " .. text .. "\n")
    f:close()
  end
end

-- Einzelner Sprachturn – zsh Login-Shell, damit .zprofile/.zshrc und Keychain-Kontext passen
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "V", function()
  -- Wenn der Assistent gerade spricht oder denkt: kurzer Hinweis, der neue Turn unterbricht ihn
  local fh = io.open(os.getenv("HOME") .. "/.heyjarvis/state/status", "r")
  if fh then
    local s = fh:read("*a") or ""; fh:close()
    if s:match("speak") or s:match("think") then
      hs.alert.show("✋ Unterbreche…", 0.8)
    end
  end
  hs.alert.show("🎤 Jarvis hört zu…", 1)
  local t = hs.task.new("/bin/zsh",
    function(exitCode, stdOut, stdErr)
      logToFile("EXIT", tostring(exitCode))
      logToFile("OUT",  stdOut or "")
      logToFile("ERR",  stdErr or "")
      if exitCode ~= 0 then
        hs.alert.show("Fehler – siehe hammerspoon.log", 3)
      end
    end,
    { "-lc", ASSISTANT .. " --once" }
  )
  t:start()  -- kein setEnvironment, damit der User-Kontext erhalten bleibt
end)

-- Wake-Word toggeln
local wakeTask = nil
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "W", function()
  if wakeTask and wakeTask:isRunning() then
    wakeTask:terminate()
    wakeTask = nil
    hs.alert.show("🔇 Wake-Word aus", 1)
  else
    wakeTask = hs.task.new("/bin/zsh",
      function(exitCode, stdOut, stdErr)
        logToFile("WAKE-EXIT", tostring(exitCode))
        logToFile("WAKE-OUT",  stdOut or "")
        logToFile("WAKE-ERR",  stdErr or "")
      end,
      { "-lc", VENV_PY .. " " .. WAKE_SCRIPT })
    wakeTask:start()
    hs.alert.show("🟢 Wake-Word an (sag 'Hey Jarvis')", 1.5)
  end
end)

hs.alert.show("HeyJarvis bereit ⌃⌥⌘V | Wake ⌃⌥⌘W", 2)

-- Not-Aus: stoppt Stimme, Assistent, Wake-Word
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "X", function()
  hs.execute("killall say 2>/dev/null; pkill -f voice-assistant.sh 2>/dev/null; pkill -f wake-word.py 2>/dev/null; pkill -f whisper-cli 2>/dev/null; killall rec 2>/dev/null; killall sox 2>/dev/null", true)
  local fh = io.open(os.getenv("HOME") .. "/.heyjarvis/state/status", "w")
  if fh then fh:write("idle"); fh:close() end
  hs.alert.show("🛑 Alles gestoppt")
end)

-- ===== HEYJARVIS MENUBAR =====
local _cvStatusFile = os.getenv("HOME") .. "/.heyjarvis/state/status"
local _cvStateDir   = os.getenv("HOME") .. "/.heyjarvis/state"

local _cvIcons = {
    idle   = "🟢",
    listen = "🎤",
    think  = "🧠",
    speak  = "🔊",
    error  = "⚠️",
}

local _cvBar = hs.menubar.new()
if _cvBar then
    local function readStatus()
        local fh = io.open(_cvStatusFile, "r")
        if not fh then return "idle" end
        local s = fh:read("*a") or ""
        fh:close()
        s = s:gsub("%s+", "")
        return (s ~= "" and s) or "idle"
    end

    local function updateBar()
        _cvBar:setTitle(_cvIcons[readStatus()] or "⚫")
    end

    _cvBar:setMenu(function()
        return {
            { title = "Status: " .. readStatus(), disabled = true },
            { title = "-" },
            { title = "Frage stellen (⌃⌥⌘V)", fn = function()
                hs.task.new("/bin/zsh", nil,
                    {"-lc", os.getenv("HOME") .. "/.heyjarvis/voice-assistant.sh --once"}):start()
            end },
            { title = "Wake-Word neu starten", fn = function()
                hs.execute("pkill -f wake-word.py; sleep 1; nohup " .. VENV_PY .. " " .. WAKE_SCRIPT .. " >~/.heyjarvis/logs/wake.log 2>&1 & disown", true)
                hs.alert.show("Wake-Word neu gestartet")
            end },
            { title = "Alles stoppen (⌃⌥⌘X)", fn = function()
                hs.execute("killall say 2>/dev/null; pkill -f voice-assistant.sh 2>/dev/null; pkill -f wake-word.py 2>/dev/null; pkill -f whisper-cli 2>/dev/null", true)
                hs.alert.show("Alle Sprach-Prozesse gestoppt")
            end },
            { title = "-" },
            { title = "Logs öffnen", fn = function()
                hs.execute("open " .. os.getenv("HOME") .. "/.heyjarvis/logs/", true)
            end },
        }
    end)

    hs.execute("mkdir -p " .. _cvStateDir, true)
    hs.pathwatcher.new(_cvStateDir .. "/", updateBar):start()
    updateBar()
    hs.timer.doEvery(2, updateBar)
end
-- ===== END HEYJARVIS MENUBAR =====
