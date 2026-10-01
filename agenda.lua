-- ============================================================
-- agenda.lua — Calendário & Tarefas Offline
-- Prefixo: a
-- ============================================================
local M = {}
M.id = "agenda"
M.name = "Agenda Offline"
M.prefix = "a"
M.help = "a <texto> -> Nova tarefa\na [] <texto> -> Nova tarefa c/ checkbox\na evt <hora> <titulo> -> Novo evento hoje\na toggle <id> -> Marcar tarefa\na del <id> -> Apagar tarefa\na clear -> Limpar concluidas/eventos\na open/close -> Ocultar bloco"

local DATA_FILE = "agenda_offline.json"
local is_open = true
local tasks = {}
local events = {}

-- Helpers
local function save_data()
    Engine.files.write(DATA_FILE, Engine.json.encode({ tasks = tasks, events = events, is_open = is_open }))
end

local function load_data()
    local raw = Engine.files.read(DATA_FILE)
    if raw and raw ~= "" then
        local data = Engine.json.parse(raw)
        if type(data) == "table" then
            tasks = data.tasks or {}
            events = data.events or {}
            if data.is_open ~= nil then is_open = data.is_open end
        end
    end
end

-- Init
load_data()

function M.render()
    local ui_events = {}
    local ui_tasks = {}
    local actions = {}
    
    -- Construir Eventos
    for i, ev in ipairs(events) do
        table.insert(ui_events, {
            id = tostring(i),
            title = ev.title,
            time_label = ev.time_label,
            color = ev.color or "",
            cmd = "a del_evt " .. i
        })
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
        table.insert(actions, { label = "🗑 Limpar Feitas", cmd = "a clear" })
    end
    
    if #events > 0 then
        table.insert(actions, { label = "🧹 Limpar Eventos", cmd = "a clear_evt" })
    end
    
    table.insert(actions, { label = (is_open and "✕ Fechar" or "▽ Abrir"), cmd = (is_open and "a close" or "a open") })

    local subtitle = nil
    if #tasks > 0 or #events > 0 then
        subtitle = #events .. " evento(s) | " .. #tasks .. " tarefa(s)"
    end
    
    -- Construir Grid do Calendario para o Mes Atual
    local now_ts = Engine.time.now()
    local y = tonumber(Engine.time.date("yyyy", now_ts))
    local m = tonumber(Engine.time.date("MM", now_ts))
    local current_day = tonumber(Engine.time.date("dd", now_ts))
    
    -- Em vez de os.time, podemos so montar um grid aproximado usando os.date do dia 1.
    -- Como JsePlatform.standardGlobals nem sempre tem TZ certo no Android p/ os.time,
    -- vamos usar os.time com cuidado
    local t1 = os.time({year=y, month=m, day=1})
    local wday = tonumber(os.date("%w", t1)) -- 0 = Domingo, 1 = Seg ...
    
    local d_in_m = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)) then d_in_m[2] = 29 end
    local max_d = d_in_m[m]
    
    local days = {}
    -- padding inicial (wday 0-6: D-S)
    for i = 1, wday do
        table.insert(days, { day = -1 })
    end
    -- dias
    for d = 1, max_d do
        local has_t = false
        local has_e = false
        if d == current_day then
            has_t = (#tasks > 0)
            has_e = (#events > 0)
        end
        table.insert(days, {
            day = d,
            is_today = (d == current_day),
            is_selected = (d == current_day),
            has_tasks = has_t,
            has_events = has_e
        })
    end
    
    local meses = {"Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"}
    local month_label = meses[m] .. " " .. y
    
    return {
        type = "agenda",
        title = "📅 Agenda",
        subtitle = subtitle,
        is_open = is_open,
        month_label = month_label,
        days = days,
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
        save_data()
        return { success = true, msg = "Agenda aberta." }
    elseif cmd == "close" then
        is_open = false
        save_data()
        return { success = true, msg = "Agenda fechada." }
    elseif cmd == "toggle" and rest then
        local idx = tonumber(rest)
        if idx and tasks[idx] then
            tasks[idx].checked = not tasks[idx].checked
            save_data()
            return { success = true }
        end
    elseif cmd == "del" and rest then
        local idx = tonumber(rest)
        if idx and tasks[idx] then
            table.remove(tasks, idx)
            save_data()
            return { success = true }
        end
    elseif cmd == "del_evt" and rest then
        local idx = tonumber(rest)
        if idx and events[idx] then
            table.remove(events, idx)
            save_data()
            return { success = true, msg = "Evento apagado." }
        end
    elseif cmd == "clear" then
        local new_tasks = {}
        for _, t in ipairs(tasks) do
            if not (t.checklist and t.checked) then
                table.insert(new_tasks, t)
            end
        end
        tasks = new_tasks
        save_data()
        return { success = true, msg = "Tarefas limpas." }
    elseif cmd == "clear_evt" then
        events = {}
        save_data()
        return { success = true, msg = "Eventos limpos." }
    elseif cmd == "[]" and rest then
        table.insert(tasks, { text = rest, checklist = true, checked = false })
        save_data()
        return { success = true }
    elseif cmd == "evt" and rest then
        local hora, titulo = rest:match("^(%S+)%s+(.+)")
        if hora and titulo then
            table.insert(events, { title = titulo, time_label = hora })
            save_data()
            return { success = true, msg = "Evento criado!" }
        else
            return { success = false, msg = "Uso: a evt 14:00 Reunião" }
        end
    else
        -- Novo item simples
        if args and args ~= "" then
            table.insert(tasks, { text = args, checklist = false, checked = false })
            save_data()
            return { success = true }
        end
    end

    return nil
end

function M.autocomplete(args)
    local cmds = { "open", "close", "toggle", "del", "del_evt", "clear", "clear_evt", "[]", "evt" }
    local res = {}
    for _, c in ipairs(cmds) do
        if c:sub(1, #args) == args then
            table.insert(res, { cmd = c, label = c, executable = (c == "open" or c == "close" or c == "clear" or c == "clear_evt") })
        end
    end
    return res
end

return M
