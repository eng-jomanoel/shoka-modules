-- ============================================================
-- agenda.lua — Calendário Google + Tarefas Locais
-- Prefixo: a
-- ============================================================
local M = {}
M.id = "agenda"
M.name = "Agenda"
M.prefix = "a"
M.help = "a <texto> -> Nova tarefa\na [] <texto> -> Nova tarefa c/ checkbox\na toggle <id> -> Marcar tarefa\na del <id> -> Apagar tarefa\na clear -> Limpar concluidas\na open/close -> Ocultar bloco\na sync -> Forçar sync Google Calendar"

local DATA_FILE = "tarefas.json"
local is_open = true
local tasks = {}
local cached_events = {}
local last_sync = 0

-- Helpers para Tarefas
local function save_tasks()
    Engine.files.write(DATA_FILE, Engine.json.encode({ tasks = tasks, is_open = is_open }))
end

local function load_tasks()
    local raw = Engine.files.read(DATA_FILE)
    if raw and raw ~= "" then
        local data = Engine.json.parse(raw)
        if type(data) == "table" then
            tasks = data.tasks or {}
            if data.is_open ~= nil then is_open = data.is_open end
        end
    end
end

-- Helpers para Calendário
local function format_time(ts)
    return Engine.time.date("HH:mm", ts)
end

local function sync_calendar()
    if not Engine.calendar.has_permission() then
        return false
    end
    
    local now = Engine.time.now()
    -- Start of today
    local date_str = Engine.time.date("yyyy-MM-dd", now)
    
    -- Simplificação: buscamos eventos das últimas 2 horas até as próximas 24 horas
    -- Para evitar cálculos complexos de timezone em Lua, pegamos uma janela razoável
    local start_ms = now - (2 * 60 * 60 * 1000)
    local end_ms = now + (24 * 60 * 60 * 1000)
    
    cached_events = Engine.calendar.get_events(start_ms, end_ms)
    last_sync = now
    return true
end

-- Init
load_tasks()

function M.render()
    local now = Engine.time.now()
    
    -- Sync automático a cada 15 min
    if is_open and (now - last_sync > 15 * 60 * 1000) then
        if Engine.calendar.has_permission() then
            sync_calendar()
        end
    end
    
    local ui_events = {}
    local ui_tasks = {}
    local actions = {}
    
    if Engine.calendar.has_permission() then
        if #cached_events > 0 then
            for _, ev in ipairs(cached_events) do
                local t_label = "Dia Todo"
                if not ev.all_day then
                    t_label = format_time(ev.start_time) .. " - " .. format_time(ev.end_time)
                end
                
                table.insert(ui_events, {
                    id = ev.id,
                    title = ev.title,
                    time_label = t_label,
                    location = ev.location,
                    color = tostring(ev.color)
                })
            end
        else
            table.insert(ui_events, {
                id = "no_events",
                title = "Nenhum evento hoje",
                time_label = "",
                color = ""
            })
        end
        table.insert(actions, { label = "↻ Sync", cmd = "a sync" })
    else
        table.insert(actions, { label = "Autorizar Calendário", cmd = "a auth" })
    end
    
    -- Construir Tasks
    local has_checked = false
    for i, t in ipairs(tasks) do
        table.insert(ui_tasks, {
            id = i,
            text = t.text,
            is_checklist = t.checklist,
            is_checked = t.checked,
            toggle_cmd = "a toggle " .. i,
            delete_cmd = "a del " .. i
        })
        if t.checked then has_checked = true end
    end
    
    if has_checked then
        table.insert(actions, { label = "🗑 Limpar feitas", cmd = "a clear" })
    end
    
    table.insert(actions, { label = (is_open and "✕ Fechar" or "▽ Abrir"), cmd = (is_open and "a close" or "a open") })

    local subtitle = nil
    if #tasks > 0 then
        subtitle = #tasks .. " tarefa" .. (#tasks > 1 and "s" or "")
    end
    
    return {
        type = "agenda",
        title = "📅 Agenda",
        subtitle = subtitle,
        is_open = is_open,
        events = ui_events,
        tasks = ui_tasks,
        actions = actions
    }
end

function M.on_command(args)
    local cmd = args:match("^%s*(%S+)")
    local rest = args:match("^%s*%S+%s+(.*)")

    if not cmd then return nil end
    cmd = cmd:lower()

    if cmd == "open" then
        is_open = true
        save_tasks()
        return { success = true, msg = "Agenda aberta." }
    elseif cmd == "close" then
        is_open = false
        save_tasks()
        return { success = true, msg = "Agenda fechada." }
    elseif cmd == "auth" then
        Engine.calendar.request_permission()
        return { success = true, msg = "Solicitando acesso ao Calendário..." }
    elseif cmd == "sync" then
        if sync_calendar() then
            return { success = true, msg = "Calendário sincronizado." }
        else
            return { success = false, msg = "Falta permissão. Digite 'a auth'." }
        end
    elseif cmd == "toggle" and rest then
        local idx = tonumber(rest)
        if idx and tasks[idx] then
            tasks[idx].checked = not tasks[idx].checked
            save_tasks()
            return { success = true }
        end
    elseif cmd == "del" and rest then
        local idx = tonumber(rest)
        if idx and tasks[idx] then
            table.remove(tasks, idx)
            save_tasks()
            return { success = true }
        end
    elseif cmd == "clear" then
        local new_tasks = {}
        for _, t in ipairs(tasks) do
            if not (t.checklist and t.checked) then
                table.insert(new_tasks, t)
            end
        end
        tasks = new_tasks
        save_tasks()
        return { success = true, msg = "Tarefas limpas." }
    elseif cmd == "[]" and rest then
        table.insert(tasks, { text = rest, checklist = true, checked = false })
        save_tasks()
        return { success = true }
    else
        -- Novo item simples se nao casou com nada
        if args and args ~= "" then
            table.insert(tasks, { text = args, checklist = false, checked = false })
            save_tasks()
            return { success = true }
        end
    end

    return nil
end

function M.autocomplete(args)
    local cmds = { "open", "close", "auth", "sync", "toggle", "del", "clear", "[]" }
    local res = {}
    for _, c in ipairs(cmds) do
        if c:sub(1, #args) == args then
            table.insert(res, { cmd = c, label = c, executable = (c == "open" or c == "close" or c == "auth" or c == "sync" or c == "clear") })
        end
    end
    return res
end

return M
