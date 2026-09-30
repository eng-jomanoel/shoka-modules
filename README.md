# 🌸 Shoka Modules

Official Lua modules and extensions for **[Shoka Launcher](https://github.com/eng-jomanoel/shoka-launcher)**.

---

## 📦 Installed Modules

### 🎵 `musica.lua` — Music Player Module
Full-featured, hot-reloadable music player with GUI & CLI integration.
- **Audio auto-scan**: Scans `/sdcard/Music/` for playlists (directories) and audio tracks (`.mp3`, `.wav`, `.ogg`, `.flac`, `.m4a`, `.aac`).
- **Cover art**: Automatically loads `cover.jpg`, `cover.png`, `folder.jpg`, or embedded images in the playlist folder.
- **GUI Controls**: Play / Pause / Skip / Previous, interactive progress bar, live queue view, shuffle toggle, loop cycling (ALL / ONE / OFF).
- **CLI Commands (`p`)**:
  - `p play` / `p pause` / `p toggle` — Toggle playback
  - `p next` / `p prev` — Change tracks
  - `p shuf` — Toggle shuffle mode
  - `p loop` — Cycle loop modes (`ALL` -> `ONE` -> `OFF`)
  - `p list` — View current playlist queue
  - `p playlists` — Browse available playlists
  - `p sel <id>` — Play specific track by index
  - `p pl <index>` — Switch active playlist

---

### 🏋️ `academia.lua` — Gym & Workout Routine Module
Minimalist, AMOLED workout tracker and rest timer synchronized with custom JSON routines.
- **Custom Routine JSON**: Imports workout routines from `/sdcard/Documents/Shoka/data/treino.json`. Supports multiple split days (A, B, C, etc.).
- **Live Rest Countdown**: Synchronized countdown timer with animated progress bar and haptic vibration (`Engine.system.vibrate`) when rest finishes.
- **Set & Reps Logging**: One-tap completion, dynamic weight adjustments (`+2.5kg`, `-2.5kg`), and custom reps logging.
- **Interactive Exercise HUD**: Shows completed series, target reps, expandable full exercise list with one-tap exercise selection.
- **GUI Controls**: Check set, skip timer, +30s timer, quick load adjustments, toggle routine list.
- **CLI Commands (`g`)**:
  - `g check` (or `g c`) — Mark current set as completed and start rest timer
  - `g skip` — Skip active rest countdown timer
  - `g timer <seconds>` — Start or adjust custom rest timer
  - `g +2.5` / `g -2.5` / `g +5` — Adjust weight load
  - `g <kg> [reps]` — Set custom weight and target reps (e.g., `g 85 10`)
  - `g next` / `g prev` — Navigate exercises
  - `g sel <id>` — Jump directly to exercise index
  - `g day [A|B|C]` — Switch routine day / split
  - `g list` — Toggle routine exercise list view
  - `g reset` — Reset current routine sets and progress

---

## 🤖 Generating Workouts with AI (ChatGPT / Claude / Gemini)

You can copy and send the following prompt along with `treino_exemplo.json` to any AI to create your custom workout routines:

```text
Crie uma rotina de treino personalizada para mim no formato JSON estrito compatível com o Shoka Launcher.
Siga exatamente a estrutura abaixo:

{
  "version": 1,
  "description": "Meu Treino Personalizado",
  "active_day": "A",
  "routines": [
    {
      "day_id": "A",
      "name": "Treino A - Peito, Tríceps & Ombro",
      "exercises": [
        {
          "id": "supino_reto",
          "name": "Supino Reto com Barra",
          "target_sets": 4,
          "target_reps": "8-12",
          "default_weight": 80.0,
          "rest_seconds": 90,
          "notes": "Execução com controle escapular"
        }
      ]
    }
  ]
}

Regras:
1. Retorne APENAS o JSON válido sem blocos de texto adicionais.
2. Cada rotina deve ter um "day_id" (ex: "A", "B", "C") e uma lista de "exercises".
3. Para cada exercício informe: id, name, target_sets (número), target_reps (string ou número), default_weight (número em kg), rest_seconds (tempo de descanso em segundos) e notes (opcional).
```

Save the generated file to:
`/sdcard/Documents/Shoka/data/treino.json`

---

## 🚀 How to Install on Device

1. Connect your Android device via USB or Wireless ADB.
2. Push module files to the launcher's module directory:
   ```bash
   adb push musica.lua /sdcard/Documents/Shoka/modules/musica.lua
   adb push academia.lua /sdcard/Documents/Shoka/modules/academia.lua
   ```
3. Push your workout data:
   ```bash
   adb push treino_exemplo.json /sdcard/Documents/Shoka/data/treino.json
   ```
4. In Shoka Launcher CLI, run:
   ```bash
   sys reload
   ```

---

## 🛠️ Developing Your Own Module

Create a new `.lua` file and implement the required module interface:

```lua
local module = {
    id = "custom_tool",
    name = "Custom Tool",
    commandPrefix = "c",
    helpText = "c <arg> - Custom command help"
}

function module.render()
    return {
        title = "My Widget",
        description = "Status: OK",
        tag = "ACTIVE"
    }
end

function module.executeCommand(args)
    return "Executed with: " .. args
end

Engine.register_module(module)
```

Available `Engine` APIs:
- `Engine.audio.*` (play, pause, resume, stop, seek, is_playing, get_position, get_duration)
- `Engine.files.*` (list_dir, exists, read, write)
- `Engine.json.*` (parse, encode)
- `Engine.system.*` (vibrate, notify, toast)

