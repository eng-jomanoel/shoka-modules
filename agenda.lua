-- ============================================================
-- agenda.lua — Calendário & Tarefas Offline
-- Prefixo: a
-- ============================================================
local M = {}
M.id = "agenda"
M.name = "Agenda Offline"
M.prefix = "a"

local DATA_FILE = "agenda_offline.json"

local state = {
    is_open = true,
    view_mode = "month", -- "month", "week", "day"
    view_ts = nil,
    selected_ts = nil,
    items = {} -- { ["2026-10-01"] = { tasks = {}, events = {} } }
}

-- Funções utilitárias de Data
local function get_today_ts()
    local now = Engine.time.now()
    local y = tonumber(Engine.time.date("yyyy", now))
    local m = tonumber(Engine.time.date("MM", now))
    local d = tonumber(Engine.time.date("dd", now))
    return os.time({year=y, month=m, day=d, hour=12})
end

local function ts_to_str(ts)
    return Engine.time.date("yyyy-MM-dd", ts * 1000)
end

local function add_days(ts, days)
    return ts + (days * 24 * 60 * 60)
end

-- Persistência
local function save_data()
    -- Não salvamos view_ts e selected_ts para não travar num dia velho ao reabrir o app
    local to_save = {
        is_open = state.is_open,
        view_mode = state.view_mode,
        items = state.items
    }
    Engine.files.write(DATA_FILE, Engine.json.encode(to_save))
end

local function load_data()
    local raw = Engine.files.read(DATA_FILE)
    if raw and raw ~= "" then
        local data = Engine.json.parse(raw)
        if type(data) == "table" then
            if data.is_open ~= nil then state.is_open = data.is_open end
            if data.view_mode then state.view_mode = data.view_mode end
            if data.items then state.items = data.items end
            
            -- Migração do formato antigo (tarefas/eventos globais)
            if data.tasks or data.events then
                local today_str = ts_to_str(get_today_ts())
                if not state.items[today_str] then
                    state.items[today_str] = { tasks = {}, events = {} }
                end
                if data.tasks then
                    for _, t in ipairs(data.tasks) do table.insert(state.items[today_str].tasks, t) end
                end
                if data.events then
                    for _, e in ipairs(data.events) do table.insert(state.items[today_str].events, e) end
                end
                save_data()
            end
        end
    end
    
    state.view_ts = get_today_ts()
    state.selected_ts = get_today_ts()
end

load_data()

local function get_selected_str()
    return ts_to_str(state.selected_ts)
end

local function get_day_items(ts_str)
    if not state.items[ts_str] then
        state.items[ts_str] = { tasks = {}, events = {} }
    end
    return state.items[ts_str]
end

-- Renderização
function M.render()
    local today_ts = get_today_ts()
    
    -- Ajustar timezone ou resetar view se for nulo
    if not state.view_ts then state.view_ts = today_ts end
    if not state.selected_ts then state.selected_ts = today_ts end
    
    local v_year = tonumber(Engine.time.date("yyyy", state.view_ts * 1000))
    local v_month = tonumber(Engine.time.date("MM", state.view_ts * 1000))
    
    local meses = {"Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"}
    local month_label = meses[v_month] .. " " .. v_year
    
    local days_ui = {}
    
    -- Lógica de Grid dependendo do view_mode
    if state.view_mode == "month" then
        local first_day_ts = os.time({year=v_year, month=v_month, day=1, hour=12})
        local wday = tonumber(Engine.time.date("e", first_day_ts * 1000)) or tonumber(os.date("%w", first_day_ts))
        -- Se "e" der 1=Domingo, então wday ajustado para 0-6. Vamos assumir os.date("%w") para 0=Dom.
        wday = tonumber(os.date("%w", first_day_ts))
        
        local d_in_m = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
        if v_month == 2 and ((v_year % 4 == 0 and v_year % 100 ~= 0) or (v_year % 400 == 0)) then d_in_m[2] = 29 end
        local max_d = d_in_m[v_month]
        
        for i = 1, wday do table.insert(days_ui, { day = -1 }) end
        
        for d = 1, max_d do
            local d_ts = os.time({year=v_year, month=v_month, day=d, hour=12})
            local d_str = ts_to_str(d_ts)
            local its = state.items[d_str]
            table.insert(days_ui, {
                day = d,
                is_today = (d_str == ts_to_str(today_ts)),
                is_selected = (d_str == ts_to_str(state.selected_ts)),
                has_tasks = its and (#its.tasks > 0) or false,
                has_events = its and (#its.events > 0) or false,
                cmd = "a sel " .. d
            })
        end
    elseif state.view_mode == "week" then
        -- Encontrar o domingo da semana atual de view_ts
        local wday = tonumber(os.date("%w", state.view_ts))
        local start_ts = add_days(state.view_ts, -wday)
        
        for i = 0, 6 do
            local d_ts = add_days(start_ts, i)
            local d_str = ts_to_str(d_ts)
            local its = state.items[d_str]
            local d = tonumber(os.date("%d", d_ts))
            table.insert(days_ui, {
                day = d,
                is_today = (d_str == ts_to_str(today_ts)),
                is_selected = (d_str == ts_to_str(state.selected_ts)),
                has_tasks = its and (#its.tasks > 0) or false,
                has_events = its and (#its.events > 0) or false,
                cmd = "a sel " .. d
            })
        end
    end
    -- Se view_mode for "day", não enviamos days_ui. O Card oculta o grid e mostra só os itens.

    -- Itens do dia selecionado
    local sel_str = get_selected_str()
    local sel_items = get_day_items(sel_str)
    
    local ui_events = {}
    local ui_tasks = {}
    local actions = {}
    
    for i, ev in ipairs(sel_items.events) do
        table.insert(ui_events, {
            id = tostring(i),
            title = ev.title,
            time_label = ev.time_label,
            color = ev.color or "",
            cmd = "a del_evt " .. i
        })
    end
    
    local has_checked = false
    for i, t in ipairs(sel_items.tasks) do
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
    
    -- Botões
    if state.view_mode == "month" then
        table.insert(actions, { label = "[Semana]", cmd = "a vw week" })
    elseif state.view_mode == "week" then
        table.insert(actions, { label = "[Dia]", cmd = "a vw day" })
    else
        table.insert(actions, { label = "[Mes]", cmd = "a vw month" })
    end
    
    table.insert(actions, { label = "< Ant", cmd = "a prev" })
    table.insert(actions, { label = "Prox >", cmd = "a next" })
    
    if has_checked then
        table.insert(actions, { label = "Limpar Feitas", cmd = "a clear" })
    end
    
    if #sel_items.events > 0 then
        table.insert(actions, { label = "Limpar Eventos", cmd = "a clear_evt" })
    end
    
    table.insert(actions, { label = (state.is_open and "Ocultar" or "Mostrar"), cmd = (state.is_open and "a close" or "a open") })

    local subtitle = "Mostrando: " .. Engine.time.date("dd/MM/yyyy", state.selected_ts * 1000)
    
    return {
        type = "agenda",
        title = "Agenda", -- Removido emoji que causava erro visual (FS sla)
        subtitle = subtitle,
        is_open = state.is_open,
        month_label = month_label,
        days = days_ui,
        events = ui_events,
        tasks = ui_tasks,
        actions = actions,
        input_hint = "Nova tarefa no dia selecionado...",
        input_cmd = "a"
    }
end

function M.on_command(args)
    local cmd = args:match("^%s*(%S+)")
    local rest = args:match("^%s*%S+%s+(.*)")

    if not cmd then return nil end
    cmd = cmd:lower()

    if cmd == "open" then
        state.is_open = true
        save_data()
        return { success = true }
    elseif cmd == "close" then
        state.is_open = false
        save_data()
        return { success = true }
    elseif cmd == "vw" and rest then
        if rest == "month" or rest == "week" or rest == "day" then
            state.view_mode = rest
            save_data()
            return { success = true }
        end
    elseif cmd == "prev" then
        if state.view_mode == "month" then
            local y = tonumber(os.date("%Y", state.view_ts))
            local m = tonumber(os.date("%m", state.view_ts))
            m = m - 1
            if m < 1 then m = 12; y = y - 1 end
            state.view_ts = os.time({year=y, month=m, day=1, hour=12})
        elseif state.view_mode == "week" then
            state.view_ts = add_days(state.view_ts, -7)
        else
            state.view_ts = add_days(state.view_ts, -1)
            state.selected_ts = state.view_ts
        end
        return { success = true }
    elseif cmd == "next" then
        if state.view_mode == "month" then
            local y = tonumber(os.date("%Y", state.view_ts))
            local m = tonumber(os.date("%m", state.view_ts))
            m = m + 1
            if m > 12 then m = 1; y = y + 1 end
            state.view_ts = os.time({year=y, month=m, day=1, hour=12})
        elseif state.view_mode == "week" then
            state.view_ts = add_days(state.view_ts, 7)
        else
            state.view_ts = add_days(state.view_ts, 1)
            state.selected_ts = state.view_ts
        end
        return { success = true }
    elseif cmd == "sel" and rest then
        local d = tonumber(rest)
        if d then
            local y = tonumber(os.date("%Y", state.view_ts))
            local m = tonumber(os.date("%m", state.view_ts))
            state.selected_ts = os.time({year=y, month=m, day=d, hour=12})
            return { success = true }
        end
    elseif cmd == "toggle" and rest then
        local idx = tonumber(rest)
        local its = get_day_items(get_selected_str())
        if idx and its.tasks[idx] then
            its.tasks[idx].checked = not its.tasks[idx].checked
            save_data()
            return { success = true }
        end
    elseif cmd == "del" and rest then
        local idx = tonumber(rest)
        local its = get_day_items(get_selected_str())
        if idx and its.tasks[idx] then
            table.remove(its.tasks, idx)
            save_data()
            return { success = true }
        end
    elseif cmd == "del_evt" and rest then
        local idx = tonumber(rest)
        local its = get_day_items(get_selected_str())
        if idx and its.events[idx] then
            table.remove(its.events, idx)
            save_data()
            return { success = true }
        end
    elseif cmd == "clear" then
        local its = get_day_items(get_selected_str())
        local new_tasks = {}
        for _, t in ipairs(its.tasks) do
            if not (t.checklist and t.checked) then table.insert(new_tasks, t) end
        end
        its.tasks = new_tasks
        save_data()
        return { success = true }
    elseif cmd == "clear_evt" then
        get_day_items(get_selected_str()).events = {}
        save_data()
        return { success = true }
    elseif cmd == "[]" and rest then
        table.insert(get_day_items(get_selected_str()).tasks, { text = rest, checklist = true, checked = false })
        save_data()
        return { success = true }
    elseif cmd == "evt" and rest then
        local hora, titulo = rest:match("^(%S+)%s+(.+)")
        if hora and titulo then
            table.insert(get_day_items(get_selected_str()).events, { title = titulo, time_label = hora })
            save_data()
            return { success = true }
        end
    else
        if args and args ~= "" then
            table.insert(get_day_items(get_selected_str()).tasks, { text = args, checklist = false, checked = false })
            save_data()
            return { success = true }
        end
    end

    return nil
end

function M.autocomplete(args)
    local cmds = { "open", "close", "vw month", "vw week", "vw day", "next", "prev", "clear", "clear_evt", "[]", "evt" }
    local res = {}
    for _, c in ipairs(cmds) do
        if c:sub(1, #args) == args then
            table.insert(res, { cmd = c, label = c, executable = true })
        end
    end
    return res
end

M.help = "a <texto> -> Anotação no dia selecionado\n" ..
         "a [] <texto> -> Tarefa no dia selecionado\n" ..
         "a evt <hora> <titulo> -> Evento no dia\n" ..
         "a vw <month|week|day> -> Muda a visualização\n" ..
         "a prev / a next -> Navega no calendário"

return M
