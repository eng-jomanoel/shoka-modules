-- MUSIC PLAYER MODULE (musica.lua)
-- Offline music player supporting folder-based playlists, album covers, loop, shuffle, GUI and CLI
local M = {}

M.id = "music"
M.name = "Music Player"
M.prefix = "p"
M.help = "p play | p pause | p next | p prev | p loop | p shuf | p queue | p pl <name> | p scan"

-- Internal State
local playlists = {}
local current_pl_idx = 1
local current_song_idx = 1
local view_mode = "player" -- "player", "queue", "playlists"
local loop_mode = "all" -- "off", "all", "one"
local shuffle = false
local history = {}

-- Scan /sdcard/Music directory
local function rescan_library()
    local data = Engine.music.scan()
    playlists = (data and data.playlists) or {}
    if #playlists == 0 then
        playlists = {
            {
                name = "General (/sdcard/Music)",
                path = Engine.music.get_dir(),
                songs = {}
            }
        }
    end
    if current_pl_idx > #playlists then
        current_pl_idx = 1
    end
    local current_pl = playlists[current_pl_idx]
    if current_pl and current_song_idx > #(current_pl.songs or {}) then
        current_song_idx = 1
    end
end

rescan_library()

local function get_current_playlist()
    return playlists[current_pl_idx]
end

local function get_current_song()
    local pl = get_current_playlist()
    if pl and pl.songs and #pl.songs > 0 then
        return pl.songs[current_song_idx]
    end
    return nil
end

local function play_song(song_idx)
    local pl = get_current_playlist()
    if not pl or not pl.songs or #pl.songs == 0 then
        return "No tracks found in this playlist. Add audio files to " .. (pl and pl.path or "/sdcard/Music")
    end

    if song_idx < 1 then song_idx = 1 end
    if song_idx > #pl.songs then song_idx = 1 end

    current_song_idx = song_idx
    local song = pl.songs[current_song_idx]
    if song and song.path then
        Engine.audio.play(song.path)
        return "Now playing: " .. song.title
    end
    return "Error loading audio file."
end

local function next_song()
    local pl = get_current_playlist()
    local total = (pl and pl.songs) and #pl.songs or 1
    if total <= 1 then
        return play_song(1)
    end

    if loop_mode == "one" then
        return play_song(current_song_idx)
    end

    if shuffle then
        local available = {}
        for i = 1, total do
            if i ~= current_song_idx then
                table.insert(available, i)
            end
        end
        local rand_idx = available[math.random(1, #available)] or 1
        table.insert(history, current_song_idx)
        return play_song(rand_idx)
    end

    local next_idx = current_song_idx + 1
    if next_idx > total then
        if loop_mode == "off" then
            Engine.audio.stop()
            return "Reached end of playlist."
        else
            next_idx = 1
        end
    end
    table.insert(history, current_song_idx)
    return play_song(next_idx)
end

local function prev_song()
    local pl = get_current_playlist()
    local total = (pl and pl.songs) and #pl.songs or 1
    if total <= 1 then
        return play_song(1)
    end

    if #history > 0 then
        local prev_idx = table.remove(history)
        return play_song(prev_idx)
    end

    local prev_idx = current_song_idx - 1
    if prev_idx < 1 then prev_idx = total end
    return play_song(prev_idx)
end

function M.on_command(args)
    local raw = string.gsub(args or "", "^%s*(.-)%s*$", "%1")
    local tokens = {}
    for word in string.gmatch(raw, "%S+") do
        table.insert(tokens, word)
    end

    local cmd = string.lower(tokens[1] or "")

    if cmd == "-h" or cmd == "--help" then
        return "MUSIC PLAYER COMMANDS (p)\n" ..
               "  p              : Toggle play / pause\n" ..
               "  p play [name]  : Play current or specific track\n" ..
               "  p pause        : Pause playback\n" ..
               "  p resume       : Resume playback\n" ..
               "  p next / p skip: Next track\n" ..
               "  p prev / p back: Previous track\n" ..
               "  p loop [mode]  : Loop mode (all, one, off)\n" ..
               "  p shuf / shuffle: Toggle shuffle (on/off)\n" ..
               "  p queue        : Show current playlist queue\n" ..
               "  p pl [name]    : Switch or list playlists\n" ..
               "  p scan         : Rescan /sdcard/Music directory"
    end

    if cmd == "" or cmd == "toggle" then
        if Engine.audio.is_playing() then
            Engine.audio.pause()
            return "Playback paused."
        else
            if Engine.audio.get_duration() > 0 and Engine.audio.get_position() > 0 then
                Engine.audio.resume()
                return "Playback resumed."
            else
                return play_song(current_song_idx)
            end
        end
    end

    if cmd == "pause" then
        Engine.audio.pause()
        return "Playback paused."
    end

    if cmd == "resume" then
        Engine.audio.resume()
        return "Playback resumed."
    end

    if cmd == "stop" then
        Engine.audio.stop()
        return "Playback stopped."
    end

    if cmd == "next" or cmd == "skip" then
        return next_song()
    end

    if cmd == "prev" or cmd == "back" then
        return prev_song()
    end

    if cmd == "loop" then
        local mode = tokens[2] and string.lower(tokens[2])
        if mode == "all" or mode == "one" or mode == "off" then
            loop_mode = mode
        else
            -- Cycle loop mode: all -> one -> off -> all
            if loop_mode == "all" then
                loop_mode = "one"
            elseif loop_mode == "one" then
                loop_mode = "off"
            else
                loop_mode = "all"
            end
        end
        return "Loop mode: " .. string.upper(loop_mode)
    end

    if cmd == "shuf" or cmd == "shuffle" then
        local mode = tokens[2] and string.lower(tokens[2])
        if mode == "on" or mode == "true" then
            shuffle = true
        elseif mode == "off" or mode == "false" then
            shuffle = false
        else
            shuffle = not shuffle
        end
        return "Shuffle: " .. (shuffle and "ON" or "OFF")
    end

    if cmd == "play" then
        local param = tokens[2]
        if param then
            local num = tonumber(param)
            if num then
                table.insert(history, current_song_idx)
                return play_song(num)
            else
                local pl = get_current_playlist()
                local query = string.lower(param)
                if pl and pl.songs then
                    for idx, s in ipairs(pl.songs) do
                        if string.find(string.lower(s.title), query, 1, true) then
                            table.insert(history, current_song_idx)
                            return play_song(idx)
                        end
                    end
                end
                return "Track matching '" .. param .. "' not found."
            end
        else
            return play_song(current_song_idx)
        end
    end

    if cmd == "queue" or cmd == "songs" then
        view_mode = (view_mode == "queue") and "player" or "queue"
        return "Switched view to " .. view_mode .. "."
    end

    if cmd == "pl" or cmd == "playlist" or cmd == "playlists" then
        local param = tokens[2]
        if not param then
            view_mode = (view_mode == "playlists") and "player" or "playlists"
            return "Switched view to " .. view_mode .. "."
        end

        local num = tonumber(param)
        if num and num >= 1 and num <= #playlists then
            current_pl_idx = num
            current_song_idx = 1
            history = {}
            view_mode = "queue"
            local pl = playlists[current_pl_idx]
            return "Playlist selected: " .. pl.name .. " (" .. #(pl.songs or {}) .. " tracks)"
        else
            local query = string.lower(param)
            for idx, pl in ipairs(playlists) do
                if string.find(string.lower(pl.name), query, 1, true) then
                    current_pl_idx = idx
                    current_song_idx = 1
                    history = {}
                    view_mode = "queue"
                    return "Playlist selected: " .. pl.name
                end
            end
            return "Playlist '" .. param .. "' not found."
        end
    end

    if cmd == "view" then
        local mode = tokens[2] or "player"
        if mode == "queue" or mode == "playlists" or mode == "player" then
            view_mode = mode
            return "View mode: " .. mode
        else
            return "Valid view modes: 'p view player', 'p view queue', 'p view playlists'"
        end
    end

    if cmd == "scan" then
        rescan_library()
        return string.format("Library rescanned: %d playlists found.", #playlists)
    end

    return "Unknown command. Try: p play, p pause, p next, p prev, p loop, p shuf, p queue, p pl"
end

-- Render Home GUI Card
function M.render()
    local pl = get_current_playlist()
    local song = get_current_song()
    local total_songs = (pl and pl.songs) and #pl.songs or 0

    local is_curr_playing = Engine.audio.is_playing()
    local pos = Engine.audio.get_position()
    local dur = Engine.audio.get_duration()
    local progress = (dur > 0) and (pos / dur) or 0

    local function format_time(ms)
        local total_sec = math.floor(ms / 1000)
        local m = math.floor(total_sec / 60)
        local s = total_sec % 60
        return string.format("%02d:%02d", m, s)
    end

    local progress_str = nil
    if dur > 0 then
        progress_str = format_time(pos) .. " / " .. format_time(dur)
    end

    local card_title = song and song.title or "No track selected"
    local card_subtitle = string.format("%s • [%d/%d]", (pl and pl.name or "General"), current_song_idx, total_songs)
    local cover_img = pl and pl.cover or nil

    -- Control Actions
    local actions = {
        { label = "Prev", cmd = "p prev" },
        { label = "Toggle", cmd = "p toggle" },
        { label = "Next", cmd = "p next" },
        { label = "Shuf", cmd = "p shuf" },
        { label = "Loop", cmd = "p loop" },
        { label = (view_mode == "queue") and "Close" or "Queue", cmd = "p view " .. ((view_mode == "queue") and "player" or "queue") },
        { label = (view_mode == "playlists") and "Close" or "Playlists", cmd = "p view " .. ((view_mode == "playlists") and "player" or "playlists") }
    }

    local items = {}

    if view_mode == "queue" and pl and pl.songs then
        for idx, s in ipairs(pl.songs) do
            local is_this_active = (idx == current_song_idx)
            local is_this_playing = is_this_active and is_curr_playing
            table.insert(items, {
                label = string.format("%d. %s", idx, s.title),
                sublabel = is_this_playing and "PLAYING" or nil,
                cmd = "p play " .. idx,
                active = is_this_active
            })
        end
    elseif view_mode == "playlists" then
        for idx, p in ipairs(playlists) do
            local count = (p.songs and #p.songs) or 0
            table.insert(items, {
                label = p.name,
                sublabel = string.format("%d tracks", count),
                cmd = "p pl " .. idx,
                active = (idx == current_pl_idx)
            })
        end
    end

    return {
        type = "media",
        title = card_title,
        subtitle = card_subtitle,
        cover = cover_img,
        is_playing = is_curr_playing,
        progress = progress,
        progress_text = progress_str,
        shuffle = shuffle,
        loop = loop_mode,
        actions = actions,
        items = items
    }
end

return M
