-- ============================================================
-- musica.lua — Music Player Remastered (Offline)
-- Suporte a pastas como playlists, busca, seek, persistência,
-- fila interativa, shuffle com histórico e loop mode.
-- Prefixo: p
-- ============================================================
local M = {}

M.id = "music"
M.name = "Music Player"
M.prefix = "p"
M.help = "p [play|pause|next|prev|ff|rw|loop|shuf|queue|pl|find|scan]"

local STATE_FILE = "music_state.json"

-- Estado Interno
local playlists = {}
local current_pl_idx = 1
local current_song_idx = 1
local view_mode = "player" -- "player", "queue", "playlists"
local loop_mode = "off" -- "off", "all", "one"
local shuffle = false
local history = {}

-- ── Persistência de Estado ──

local function save_state()
    local to_save = {
        pl_idx = current_pl_idx,
        song_idx = current_song_idx,
        loop_mode = loop_mode,
        shuffle = shuffle,
        view_mode = view_mode
    }
    Engine.files.write(STATE_FILE, Engine.json.encode(to_save))
end

local function load_state()
    local raw = Engine.files.read(STATE_FILE)
    if raw and raw ~= "" then
        local data = Engine.json.parse(raw)
        if type(data) == "table" then
            if data.pl_idx and type(data.pl_idx) == "number" then current_pl_idx = data.pl_idx end
            if data.song_idx and type(data.song_idx) == "number" then current_song_idx = data.song_idx end
            if data.loop_mode then loop_mode = data.loop_mode end
            if data.shuffle ~= nil then shuffle = data.shuffle end
            if data.view_mode then view_mode = data.view_mode end
        end
    end
end

-- ── Varredura de Músicas (/sdcard/Music) ──

local function rescan_library()
    local data = Engine.music.scan()
    playlists = (data and data.playlists) or {}
    if #playlists == 0 then
        playlists = {
            {
                name = "Geral (/sdcard/Music)",
                path = Engine.music.get_dir(),
                songs = {}
            }
        }
    end

    if current_pl_idx > #playlists then current_pl_idx = 1 end
    local current_pl = playlists[current_pl_idx]
    if current_pl and current_song_idx > #(current_pl.songs or {}) then
        current_song_idx = 1
    end

    -- Se o áudio já estiver tocando, sincroniza o índice
    local current_path = Engine.audio.current_path()
    if current_path and current_path ~= "" then
        for p_idx, pl in ipairs(playlists) do
            if pl.songs then
                for s_idx, s in ipairs(pl.songs) do
                    if s.path == current_path then
                        current_pl_idx = p_idx
                        current_song_idx = s_idx
                        return
                    end
                end
            end
        end
    end
end

load_state()
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
        return "Nenhuma música nesta playlist. Adicione arquivos de áudio em " .. (pl and pl.path or "/sdcard/Music")
    end

    if song_idx < 1 then song_idx = 1 end
    if song_idx > #pl.songs then song_idx = 1 end

    current_song_idx = song_idx
    local song = pl.songs[current_song_idx]
    if song and song.path then
        Engine.audio.play(song.path)
        save_state()
        return "Tocando agora: " .. song.title
    end
    return "Erro ao carregar arquivo de áudio."
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
            return "Fim da playlist alcançado."
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

-- ── Execução de Comandos ──

function M.on_command(args)
    local raw = string.gsub(args or "", "^%s*(.-)%s*$", "%1")
    local tokens = {}
    for word in string.gmatch(raw, "%S+") do
        table.insert(tokens, word)
    end

    local cmd = string.lower(tokens[1] or "")

    if cmd == "-h" or cmd == "--help" or cmd == "help" then
        return "PLAYER DE MÚSICA (p):\n" ..
               "• p                 : Alterna Reproduzir / Pausar\n" ..
               "• p play [nome|nº]  : Toca música atual ou específica\n" ..
               "• p pause           : Pausa a reprodução\n" ..
               "• p resume          : Retoma a reprodução\n" ..
               "• p stop            : Para a reprodução\n" ..
               "• p next / p skip   : Próxima faixa\n" ..
               "• p prev / p back   : Faixa anterior\n" ..
               "• p ff / p seek +15 : Avança 15 segundos\n" ..
               "• p rw / p seek -15 : Retrocede 15 segundos\n" ..
               "• p loop [all|one|off] : Modo de repetição\n" ..
               "• p shuf            : Alterna modo aleatório (ON/OFF)\n" ..
               "• p queue / p q     : Abre/fecha lista da playlist\n" ..
               "• p pl [nome|nº]    : Troca de playlist\n" ..
               "• p find <termo>    : Busca música em todas as pastas\n" ..
               "• p scan            : Re-escaneia /sdcard/Music"
    end

    if cmd == "" or cmd == "toggle" then
        if Engine.audio.is_playing() then
            Engine.audio.pause()
            return "Pausado."
        else
            local is_paused = (Engine.audio.is_paused and Engine.audio.is_paused()) or false
            if is_paused or (Engine.audio.get_duration() > 0 and Engine.audio.get_position() > 0) then
                Engine.audio.resume()
                return "Reproduzindo."
            else
                return play_song(current_song_idx)
            end
        end
    end

    if cmd == "pause" then
        Engine.audio.pause()
        return "Pausado."
    end

    if cmd == "resume" then
        Engine.audio.resume()
        return "Reproduzindo."
    end

    if cmd == "stop" then
        Engine.audio.stop()
        return "Parado."
    end

    if cmd == "next" or cmd == "skip" then
        return next_song()
    end

    if cmd == "prev" or cmd == "back" then
        return prev_song()
    end

    -- Avanço e retrocesso rápido
    if cmd == "ff" then
        local pos = Engine.audio.get_position()
        local dur = Engine.audio.get_duration()
        local new_pos = math.min(dur, pos + 15000)
        Engine.audio.seek(new_pos)
        return string.format("Avançado para %02d:%02d", math.floor(new_pos / 60000), math.floor((new_pos % 60000) / 1000))
    end

    if cmd == "rw" then
        local pos = Engine.audio.get_position()
        local new_pos = math.max(0, pos - 15000)
        Engine.audio.seek(new_pos)
        return string.format("Retrocedido para %02d:%02d", math.floor(new_pos / 60000), math.floor((new_pos % 60000) / 1000))
    end

    if cmd == "seek" and tokens[2] then
        local arg = tokens[2]
        local dur = Engine.audio.get_duration()
        local pos = Engine.audio.get_position()
        if arg:sub(1, 1) == "+" then
            local sec = tonumber(arg:sub(2)) or 10
            local new_pos = math.min(dur, pos + (sec * 1000))
            Engine.audio.seek(new_pos)
            return "Seek +" .. sec .. "s"
        elseif arg:sub(1, 1) == "-" then
            local sec = tonumber(arg:sub(2)) or 10
            local new_pos = math.max(0, pos - (sec * 1000))
            Engine.audio.seek(new_pos)
            return "Seek -" .. sec .. "s"
        else
            local sec = tonumber(arg)
            if sec then
                local new_pos = math.min(dur, sec * 1000)
                Engine.audio.seek(new_pos)
                return "Seek para " .. sec .. "s"
            end
        end
    end

    if cmd == "loop" then
        local mode = tokens[2] and string.lower(tokens[2])
        if mode == "all" or mode == "one" or mode == "off" then
            loop_mode = mode
        else
            if loop_mode == "all" then loop_mode = "one"
            elseif loop_mode == "one" then loop_mode = "off"
            else loop_mode = "all" end
        end
        save_state()
        return "Modo Loop: " .. string.upper(loop_mode)
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
        save_state()
        return "Aleatório: " .. (shuffle and "LIGADO" or "DESLIGADO")
    end

    if cmd == "play" then
        local query = raw:match("^%s*%S+%s+(.*)")
        if query and query ~= "" then
            local num = tonumber(query)
            if num then
                table.insert(history, current_song_idx)
                return play_song(num)
            else
                local pl = get_current_playlist()
                local q_lower = string.lower(query)
                if pl and pl.songs then
                    for idx, s in ipairs(pl.songs) do
                        if string.find(string.lower(s.title), q_lower, 1, true) then
                            table.insert(history, current_song_idx)
                            return play_song(idx)
                        end
                    end
                end
                return "Música contendo '" .. query .. "' não encontrada na playlist atual."
            end
        else
            return play_song(current_song_idx)
        end
    end

    -- Busca global em todas as playlists
    if (cmd == "find" or cmd == "search") and tokens[2] then
        local term = string.lower(raw:match("^%s*%S+%s+(.*)") or "")
        for p_idx, pl in ipairs(playlists) do
            if pl.songs then
                for s_idx, s in ipairs(pl.songs) do
                    if string.find(string.lower(s.title), term, 1, true) then
                        current_pl_idx = p_idx
                        current_song_idx = s_idx
                        play_song(s_idx)
                        return string.format("Encontrado em '%s': %s", pl.name, s.title)
                    end
                end
            end
        end
        return "Nenhuma música encontrada com o termo '" .. term .. "'."
    end

    if cmd == "queue" or cmd == "q" or cmd == "songs" then
        view_mode = (view_mode == "queue") and "player" or "queue"
        save_state()
        return "Visualização: " .. view_mode
    end

    if cmd == "pl" or cmd == "playlist" or cmd == "playlists" then
        local param = tokens[2]
        if not param then
            view_mode = (view_mode == "playlists") and "player" or "playlists"
            save_state()
            return "Visualização: " .. view_mode
        end

        local num = tonumber(param)
        if num and num >= 1 and num <= #playlists then
            current_pl_idx = num
            current_song_idx = 1
            history = {}
            view_mode = "queue"
            save_state()
            local pl = playlists[current_pl_idx]
            return "Playlist selecionada: " .. pl.name .. " (" .. #(pl.songs or {}) .. " faixas)"
        else
            local query = string.lower(param)
            for idx, pl in ipairs(playlists) do
                if string.find(string.lower(pl.name), query, 1, true) then
                    current_pl_idx = idx
                    current_song_idx = 1
                    history = {}
                    view_mode = "queue"
                    save_state()
                    return "Playlist selecionada: " .. pl.name
                end
            end
            return "Playlist '" .. param .. "' não encontrada."
        end
    end

    if cmd == "view" then
        local mode = tokens[2] or "player"
        if mode == "queue" or mode == "playlists" or mode == "player" then
            view_mode = mode
            save_state()
            return "Modo: " .. mode
        end
    end

    if cmd == "scan" then
        rescan_library()
        return string.format("Biblioteca re-escaneada: %d playlists encontradas.", #playlists)
    end

    return "Comando desconhecido. Digite 'p help' para ver os comandos."
end

-- ── Renderização do Card GUI ──

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
    elseif total_songs == 0 then
        progress_str = "Nenhum arquivo em /sdcard/Music"
    end

    local card_title = song and song.title or "Nenhuma música selecionada"
    local status_icon = is_curr_playing and "▶ " or "❚❚ "
    local card_subtitle = string.format("%s%s • [%d/%d]", status_icon, (pl and pl.name or "Geral"), current_song_idx, total_songs)
    local cover_img = pl and pl.cover or nil

    -- Ações de Controle
    local actions = {
        { label = "Ant", cmd = "p prev" },
        { label = "Toggle", cmd = "p toggle" },
        { label = "Próx", cmd = "p next" },
        { label = "Shuf", cmd = "p shuf" },
        { label = "Loop", cmd = "p loop" },
        { label = (view_mode == "queue") and "Fechar" or "Fila", cmd = "p view " .. ((view_mode == "queue") and "player" or "queue") },
        { label = (view_mode == "playlists") and "Fechar" or "Pastas", cmd = "p view " .. ((view_mode == "playlists") and "player" or "playlists") }
    }

    local items = {}

    if view_mode == "queue" and pl and pl.songs then
        for idx, s in ipairs(pl.songs) do
            local is_this_active = (idx == current_song_idx)
            local is_this_playing = is_this_active and is_curr_playing
            table.insert(items, {
                label = string.format("%d. %s", idx, s.title),
                sublabel = is_this_playing and "TOCANDO" or nil,
                cmd = "p play " .. idx,
                active = is_this_active
            })
        end
    elseif view_mode == "playlists" then
        for idx, p in ipairs(playlists) do
            local count = (p.songs and #p.songs) or 0
            table.insert(items, {
                label = p.name,
                sublabel = string.format("%d faixas", count),
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

-- ── Autocomplete Aprimorado ──

function M.autocomplete(args)
    local query = string.lower(string.gsub(args or "", "^%s*(.-)%s*$", "%1"))
    local base_cmds = {
        "play", "pause", "resume", "stop", "next", "prev",
        "ff", "rw", "seek ", "loop", "shuf", "queue", "pl",
        "find ", "scan", "help"
    }

    local results = {}

    -- Sugestões de faixas da playlist atual quando digita "play "
    if query:sub(1, 5) == "play " then
        local q_song = query:sub(6)
        local pl = get_current_playlist()
        if pl and pl.songs then
            for idx, s in ipairs(pl.songs) do
                if q_song == "" or string.find(string.lower(s.title), q_song, 1, true) then
                    table.insert(results, {
                        command = "p play " .. idx,
                        cmd = "play " .. idx,
                        label = string.format("p play %d (%s)", idx, s.title),
                        executable = true
                    })
                end
            end
        end
        return results
    end

    -- Sugestões de playlists quando digita "pl "
    if query:sub(1, 3) == "pl " then
        local q_pl = query:sub(4)
        for idx, p in ipairs(playlists) do
            if q_pl == "" or string.find(string.lower(p.name), q_pl, 1, true) then
                table.insert(results, {
                    command = "p pl " .. idx,
                    cmd = "pl " .. idx,
                    label = string.format("p pl %d (%s)", idx, p.name),
                    executable = true
                })
            end
        end
        return results
    end

    for _, c in ipairs(base_cmds) do
        if query == "" or string.find(c, query, 1, true) then
            local is_exec = not c:match("%s$")
            table.insert(results, {
                command = "p " .. c,
                cmd = c,
                label = "p " .. c,
                executable = is_exec
            })
        end
    end
    return results
end

return M
