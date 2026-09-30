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

## 🚀 How to Install on Device

1. Connect your Android device via USB or Wireless ADB.
2. Push module files to the launcher's module directory:
   ```bash
   adb push musica.lua /sdcard/Documents/Shoka/modules/musica.lua
   ```
3. In Shoka Launcher CLI, run:
   ```bash
   sys reload
   ```
   Or restart the launcher.

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
- `Engine.system.*` (vibrate, notify, toast)
