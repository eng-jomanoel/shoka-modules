-- ============================================================
-- agenda.lua — Calendário & Tarefas Offline (Modo Semana Horizontal)
-- Prefixo: a
-- ============================================================
local M = {}
M.id = "agenda"
M.name = "Agenda Offline"
M.prefix = "a"

local DATA_FILE = "agenda_offline.json"

local state = {
    is_open = true,
    selected_str = "2026-10-01",
    view_center_ts = nil, -- Timestamp base do carrossel semanal
    items = {} -- { ["2026-10-01"] = { tasks = {}, events = {} } }
}

-- ── Funções de Data e Utilitários ──

local function get_today_str()
    return Engine.time.date("yyyy-MM-dd", Engine.time.now())
end

local function parse_ymd(str)
    local y, m, d = str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y and m and d then
        return tonumber(y), tonumber(m), tonumber(d)
    end
    return nil, nil, nil
end

local function date_to_ts(y, m, d)
    return os.time({ year = y, month = m, day = d, hour = 12 })
end

local function ts_to_date_str(ts)
    local dy = tonumber(os.date("%Y", ts))
    local dm = tonumber(os.date("%m", ts))
    local dd = tonumber(os.date("%d", ts))
    return string.format("%04d-%02d-%02d", dy, dm, dd)
end

local function format_display_date(str)
    local y, m, d = parse_ymd(str)
    if y and m and d then
        local wdays = { "Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado" }
        local ts = date_to_ts(y, m, d)
        local w = (tonumber(os.date("%w", ts)) or 0) + 1
        return string.format("%s, %02d/%02d/%04d", wdays[w] or "", d, m, y)
    end
    return str
end

local function get_wday_short(ts)
    local wdays = { "DOM", "SEG", "TER", "QUA", "QUI", "SEX", "SÁB" }
    local w = (tonumber(os.date("%w", ts)) or 0) + 1
    return wdays[w] or "---"
end

-- ── Persistência ──

local function save_data()
    local to_save = {
        is_open = state.is_open,
        items = state.items
    }
    Engine.files.write(DATA_FILE, Engine.json.encode(to_save))
end

local function load_data()
    local today_str = get_today_str()
    state.selected_str = today_str
    local ty, tm, td = parse_ymd(today_str)
    state.view_center_ts = date_to_ts(ty or 2026, tm or 10, td or 1)

    local raw = Engine.files.read(DATA_FILE)
    if raw and raw ~= "" then
        local data = Engine.json.parse(raw)
        if type(data) == "table" then
            if data.is_open ~= nil then state.is_open = data.is_open end
            if type(data.items) == "table" then state.items = data.items end

            -- Migração de dados legados
            if data.tasks or data.events then
                if not state.items[today_str] then
                    state.items[today_str] = { tasks = {}, events = {} }
                end
                if data.tasks then
                    for _, t in ipairs(data.tasks) do
                        table.insert(state.items[today_str].tasks, t)
                    end
                end
                if data.events then
                    for _, e in ipairs(data.events) do
                        table.insert(state.items[today_str].events, e)
                    end
                end
                save_data()
            end
        end
    end
end

load_data()

local function get_day_items(date_str)
    if not state.items[date_str] then
        state.items[date_str] = { tasks = {}, events = {} }
    end
    if not state.items[date_str].tasks then state.items[date_str].tasks = {} end
    if not state.items[date_str].events then state.items[date_str].events = {} end
    return state.items[date_str]
end

-- ── Renderização ──

function M.render()
    local today_str = get_today_str()
    local sel_str = state.selected_str or today_str
    local sel_items = get_day_items(sel_str)

    if not state.view_center_ts then
        local sy, sm, sd = parse_ymd(sel_str)
        state.view_center_ts = date_to_ts(sy or 2026, sm or 10, sd or 1)
    end

    -- Cria carrossel contínuo de 15 dias centralizado em view_center_ts (-7 a +7 dias)
    local days_ui = {}
    local center_ts = state.view_center_ts

    local meses = {
        "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    }

    local start_m = tonumber(os.date("%m", center_ts - (7 * 86400))) or 1
    local end_m = tonumber(os.date("%m", center_ts + (7 * 86400))) or 1
    local c_year = tonumber(os.date("%Y", center_ts)) or 2026

    local month_label = meses[start_m] or ""
    if start_m ~= end_m then
        month_label = month_label .. " / " .. (meses[end_m] or "") .. " " .. c_year
    else
        month_label = month_label .. " " .. c_year
    end

    for offset = -7, 7 do
        local d_ts = center_ts + (offset * 86400)
        local d_str = ts_to_date_str(d_ts)
        local _, _, day_num = parse_ymd(d_str)
        local its = state.items[d_str]

        table.insert(days_ui, {
            day = day_num or 1,
            wday_label = get_wday_short(d_ts),
            date_str = d_str,
            is_today = (d_str == today_str),
            is_selected = (d_str == sel_str),
            has_tasks = (its and #its.tasks > 0) or false,
            has_events = (its and #its.events > 0) or false,
            cmd = "a sel " .. d_str
        })
    end

    -- Eventos do dia selecionado
    local ui_events = {}
    for i, ev in ipairs(sel_items.events) do
        table.insert(ui_events, {
            id = tostring(i),
            title = ev.title,
            time_label = ev.time_label or "",
            location = ev.location or "",
            color = ev.color or "",
            delete_cmd = "a del_evt " .. i
        })
    end

    -- Tarefas do dia selecionado
    local ui_tasks = {}
    local has_checked = false
    for i, t in ipairs(sel_items.tasks) do
        table.insert(ui_tasks, {
            id = i,
            text = t.text,
            is_checklist = (t.checklist ~= false),
            is_checked = (t.checked == true),
            toggle_cmd = "a toggle " .. i,
            delete_cmd = "a del " .. i
        })
        if t.checked then has_checked = true end
    end

    -- Botões de Ação
    local actions = {}
    table.insert(actions, { label = "Hoje", cmd = "a today" })
    table.insert(actions, { label = "< Ant", cmd = "a prev" })
    table.insert(actions, { label = "Próx >", cmd = "a next" })

    if has_checked then
        table.insert(actions, { label = "Limpar Feitas", cmd = "a clear" })
    end

    if #sel_items.events > 0 then
        table.insert(actions, { label = "Limpar Eventos", cmd = "a clear_evt" })
    end

    table.insert(actions, {
        label = (state.is_open and "Ocultar" or "Mostrar"),
        cmd = (state.is_open and "a close" or "a open")
    })

    local subtitle = format_display_date(sel_str)
    if sel_str == today_str then
        subtitle = subtitle .. " (Hoje)"
    end

    local _, sm_sel, sd_sel = parse_ymd(sel_str)
    local short_date = string.format("%02d/%02d", sd_sel or 1, sm_sel or 1)

    return {
        type = "agenda",
        title = "Agenda",
        subtitle = subtitle,
        is_open = state.is_open,
        month_label = month_label,
        days = days_ui,
        events = ui_events,
        tasks = ui_tasks,
        actions = actions,
        input_hint = "Nova tarefa em " .. short_date .. "...",
        input_cmd = "a"
    }
end

-- ── Execução de Comandos ──

function M.on_command(args)
    if not args or args:match("^%s*$") then
        return {
            success = true,
            message = "Agenda: toque em um dia ou use 'a [] <tarefa>' / 'a evt <hora> <titulo>'"
        }
    end

    local cmd = args:match("^%s*(%S+)")
    local rest = args:match("^%s*%S+%s+(.*)")

    if not cmd then return nil end
    local cmd_lower = cmd:lower()

    if cmd_lower == "open" then
        state.is_open = true
        save_data()
        return { success = true }
    elseif cmd_lower == "close" then
        state.is_open = false
        save_data()
        return { success = true }
    elseif cmd_lower == "today" or cmd_lower == "hoje" then
        local today_str = get_today_str()
        state.selected_str = today_str
        local ty, tm, td = parse_ymd(today_str)
        state.view_center_ts = date_to_ts(ty, tm, td)
        return { success = true, message = "Visualizando hoje (" .. format_display_date(today_str) .. ")" }
    elseif cmd_lower == "prev" then
        -- Retrocede 7 dias no carrossel
        state.view_center_ts = (state.view_center_ts or os.time()) - (7 * 86400)
        state.selected_str = ts_to_date_str(state.view_center_ts)
        return { success = true }
    elseif cmd_lower == "next" then
        -- Avança 7 dias no carrossel
        state.view_center_ts = (state.view_center_ts or os.time()) + (7 * 86400)
        state.selected_str = ts_to_date_str(state.view_center_ts)
        return { success = true }
    elseif cmd_lower == "sel" and rest then
        -- Suporta 'yyyy-MM-dd' ou número do dia
        local y, m, d = parse_ymd(rest:match("%S+"))
        if y and m and d then
            state.selected_str = string.format("%04d-%02d-%02d", y, m, d)
            state.view_center_ts = date_to_ts(y, m, d)
            return { success = true }
        end
        local d_num = tonumber(rest:match("%S+"))
        if d_num then
            local cy = tonumber(os.date("%Y", state.view_center_ts))
            local cm = tonumber(os.date("%m", state.view_center_ts))
            state.selected_str = string.format("%04d-%02d-%02d", cy, cm, d_num)
            state.view_center_ts = date_to_ts(cy, cm, d_num)
            return { success = true }
        end
    elseif cmd_lower == "toggle" and rest then
        local idx = tonumber(rest:match("%S+"))
        local its = get_day_items(state.selected_str)
        if idx and its.tasks[idx] then
            its.tasks[idx].checked = not its.tasks[idx].checked
            save_data()
            return { success = true }
        end
    elseif cmd_lower == "del" and rest then
        local idx = tonumber(rest:match("%S+"))
        local its = get_day_items(state.selected_str)
        if idx and its.tasks[idx] then
            local rem = table.remove(its.tasks, idx)
            save_data()
            return { success = true, message = "Tarefa removida: " .. (rem.text or "") }
        end
    elseif cmd_lower == "del_evt" and rest then
        local idx = tonumber(rest:match("%S+"))
        local its = get_day_items(state.selected_str)
        if idx and its.events[idx] then
            local rem = table.remove(its.events, idx)
            save_data()
            return { success = true, message = "Evento removido: " .. (rem.title or "") }
        end
    elseif cmd_lower == "clear" then
        local its = get_day_items(state.selected_str)
        local remaining = {}
        for _, t in ipairs(its.tasks) do
            if not t.checked then table.insert(remaining, t) end
        end
        its.tasks = remaining
        save_data()
        return { success = true, message = "Tarefas concluídas removidas." }
    elseif cmd_lower == "clear_evt" then
        local its = get_day_items(state.selected_str)
        its.events = {}
        save_data()
        return { success = true, message = "Eventos do dia removidos." }
    elseif (cmd_lower == "[]" or cmd_lower == "todo" or cmd_lower == "tarefa" or cmd_lower == "task" or cmd_lower == "add") and rest then
        local task_text = rest:match("^%s*(.-)%s*$")
        if task_text and task_text ~= "" then
            table.insert(get_day_items(state.selected_str).tasks, {
                text = task_text,
                checklist = true,
                checked = false
            })
            save_data()
            return { success = true, message = "Tarefa adicionada: " .. task_text }
        end
    elseif cmd_lower == "evt" and rest then
        local hora, cor, titulo = rest:match("^(%S+)%s+(#[%x%X]+)%s+(.+)")
        if not hora then
            hora, titulo = rest:match("^(%S+)%s+(.+)")
        end
        if hora and titulo then
            local localizacao = nil
            local clean_titulo, loc = titulo:match("^(.-)%s*@%s*(.+)$")
            if clean_titulo and loc then
                titulo = clean_titulo
                localizacao = loc
            end

            table.insert(get_day_items(state.selected_str).events, {
                title = titulo,
                time_label = hora,
                location = localizacao,
                color = cor or ""
            })
            save_data()
            return { success = true, message = "Evento criado: " .. hora .. " " .. titulo }
        else
            return { success = false, message = "Uso: a evt <hora> <titulo> [@local] [#cor]" }
        end
    elseif cmd_lower == "help" or cmd_lower == "?" then
        return {
            success = true,
            message = "AGENDA (Semana):\n" ..
                      "• a <texto> : Nova tarefa no dia selecionado\n" ..
                      "• a [] <texto> : Tarefa com checkbox\n" ..
                      "• a evt <hora> <titulo> [@local] [#cor] : Novo evento\n" ..
                      "• a today / a hoje : Volta para hoje\n" ..
                      "• a sel <dia|data> : Seleciona data no carrossel\n" ..
                      "• a prev / a next : Navega pelas semanas\n" ..
                      "• a clear : Limpa tarefas concluídas\n" ..
                      "• a clear_evt : Limpa eventos do dia"
        }
    else
        -- Fallback: texto direto cria tarefa no dia selecionado
        local text = args:match("^%s*(.-)%s*$")
        if text and text ~= "" then
            table.insert(get_day_items(state.selected_str).tasks, {
                text = text,
                checklist = true,
                checked = false
            })
            save_data()
            return { success = true, message = "Tarefa adicionada: " .. text }
        end
    end

    return nil
end

-- ── Autocomplete ──

function M.autocomplete(args)
    local sub = args:match("^%s*(.*)") or ""
    local cmds = {
        "today", "hoje",
        "next", "prev",
        "[] ", "todo ", "add ", "evt ",
        "sel ", "clear", "clear_evt",
        "open", "close", "help"
    }

    local res = {}
    for _, c in ipairs(cmds) do
        if c:sub(1, #sub):lower() == sub:lower() then
            local is_exec = not c:match("%s$")
            table.insert(res, {
                command = c,
                cmd = c,
                label = "a " .. c,
                executable = is_exec
            })
        end
    end
    return res
end

M.help = "a <texto> -> Adiciona tarefa no dia selecionado\n" ..
         "a [] <texto> -> Tarefa com checkbox\n" ..
         "a evt <hora> <titulo> [@local] [#cor] -> Evento com horário\n" ..
         "a today / a hoje -> Centraliza hoje\n" ..
         "a sel <data> -> Seleciona dia\n" ..
         "a prev / a next -> Navega semanas\n" ..
         "a clear -> Limpa tarefas concluídas\n" ..
         "a clear_evt -> Limpa eventos do dia"

return M
