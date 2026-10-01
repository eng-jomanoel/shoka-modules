-- ============================================================
-- DIET / NUTRITION MODULE (dieta.lua)
-- Gerenciador de Dieta e Nutrição Offline para Shoka
-- Compatível com JSON de dietas gerados por IA
-- Prefixo: d
-- ============================================================

local M = {}

M.id = "diet"
M.name = "Dieta"
M.prefix = "d"
M.help = "d check | d next | d prev | d +250 | d +500 | d day [A|B] | d file [nome] | d list | d reset"

-- ── Estado Interno ──
local plan = nil
local active_file = "dieta.json"
local active_day_id = "A"
local current_meal_idx = 1
local show_meal_list = false
local show_file_list = false
local last_auto_date = ""
local user_override_date = ""

-- Progresso Diário (persistido por data)
local water_consumed = 0
local completed_meals = {} -- { [meal_id] = true }

-- ── Helpers de Data e Dia da Semana ──
local function get_today_info()
    local day_num = 1
    local date_str = ""
    if Engine and Engine.time and Engine.time.date then
        local u_val = tonumber(Engine.time.date("u"))
        if u_val then day_num = u_val end
        date_str = Engine.time.date("yyyy-MM-dd")
    end
    if date_str == "" and os and os.date then
        local w = tonumber(os.date("%w"))
        if w then day_num = (w == 0) and 7 or w end
        date_str = os.date("%Y-%m-%d")
    end
    return day_num, date_str
end

local WEEKDAY_MAP = {
    [1] = { "seg", "segunda", "segunda-feira", "mon", "monday", "1", 1 },
    [2] = { "ter", "terca", "terça", "terca-feira", "terça-feira", "tue", "tuesday", "2", 2 },
    [3] = { "qua", "quarta", "quarta-feira", "wed", "wednesday", "3", 3 },
    [4] = { "qui", "quinta", "quinta-feira", "thu", "thursday", "4", 4 },
    [5] = { "sex", "sexta", "sexta-feira", "fri", "friday", "5", 5 },
    [6] = { "sab", "sabado", "sábado", "sat", "saturday", "6", 6 },
    [7] = { "dom", "domingo", "sun", "sunday", "7", 7 }
}

local function routine_matches_weekday(routine, target_weekday_num)
    if not routine or not routine.weekdays then return false end
    local valid_aliases = WEEKDAY_MAP[target_weekday_num] or {}
    local lookup = {}
    for _, a in ipairs(valid_aliases) do
        lookup[string.lower(tostring(a))] = true
    end

    if type(routine.weekdays) == "table" then
        for _, day in ipairs(routine.weekdays) do
            if lookup[string.lower(tostring(day))] then
                return true
            end
        end
    elseif type(routine.weekdays) == "string" then
        if lookup[string.lower(routine.weekdays)] then
            return true
        end
    end
    return false
end

-- ── Plano Padrão de Fallback ──
local function get_default_plan()
    return {
        version = 1,
        title = "Dieta Hipertrofia 2400kcal",
        target_water_ml = 3000,
        active_day = "A",
        routines = {
            {
                day_id = "A",
                name = "Dia de Treino",
                weekdays = { "seg", "ter", "qua", "qui", "sex", "sab" },
                target_calories = 2400,
                target_protein = 165,
                target_carbs = 280,
                target_fats = 65,
                meals = {
                    {
                        id = "cafe",
                        name = "Café da Manhã",
                        time = "07:30",
                        calories = 500,
                        protein = 32,
                        carbs = 60,
                        fats = 14,
                        items = {
                            { name = "Ovos mexidos", amount = "3 unidades" },
                            { name = "Pão integral", amount = "2 fatias (50g)" },
                            { name = "Queijo cottage ou minas", amount = "30g" },
                            { name = "Café preto sem açúcar", amount = "200ml" }
                        },
                        notes = "Tomar creatina e multivitamínico"
                    },
                    {
                        id = "almoco",
                        name = "Almoço",
                        time = "12:30",
                        calories = 750,
                        protein = 52,
                        carbs = 95,
                        fats = 18,
                        items = {
                            { name = "Arroz branco ou integral", amount = "200g" },
                            { name = "Feijão carioca", amount = "100g" },
                            { name = "Peito de frango grelhado", amount = "160g" },
                            { name = "Azeite de oliva", amount = "1 colher de sobremesa" },
                            { name = "Salada verde", amount = "À vontade" }
                        }
                    },
                    {
                        id = "lanche",
                        name = "Lanche da Tarde",
                        time = "16:00",
                        calories = 420,
                        protein = 28,
                        carbs = 58,
                        fats = 8,
                        items = {
                            { name = "Whey protein concentrado", amount = "30g" },
                            { name = "Banana prata", amount = "2 unidades" },
                            { name = "Aveia em flocos", amount = "35g" }
                        }
                    },
                    {
                        id = "jantar",
                        name = "Jantar",
                        time = "20:00",
                        calories = 550,
                        protein = 42,
                        carbs = 65,
                        fats = 13,
                        items = {
                            { name = "Patinho moído ou filé de tilápia", amount = "150g" },
                            { name = "Batata inglesa cozida", amount = "220g" },
                            { name = "Legumes no vapor", amount = "120g" }
                        }
                    },
                    {
                        id = "ceia",
                        name = "Ceia",
                        time = "22:30",
                        calories = 180,
                        protein = 11,
                        carbs = 8,
                        fats = 12,
                        items = {
                            { name = "Iogurte natural desnatado", amount = "170g" },
                            { name = "Castanhas do Pará", amount = "3 unidades (15g)" }
                        }
                    }
                }
            }
        }
    }
end

-- ── Persistência de Estado ──
local function save_state()
    local _, today_date = get_today_info()
    local data = {
        date = today_date,
        active_file = active_file,
        active_day_id = active_day_id,
        current_meal_idx = current_meal_idx,
        last_auto_date = last_auto_date,
        user_override_date = user_override_date,
        water_consumed = water_consumed,
        completed_meals = completed_meals
    }
    if Engine and Engine.json and Engine.files then
        Engine.files.write("dieta_state.json", Engine.json.encode(data))
    end
end

local function load_state()
    local _, today_date = get_today_info()
    if Engine and Engine.files and Engine.files.exists("dieta_state.json") then
        local raw = Engine.files.read("dieta_state.json")
        if raw and Engine.json then
            local ok, parsed = pcall(function() return Engine.json.parse(raw) end)
            if ok and parsed then
                if parsed.active_file then active_file = parsed.active_file end
                if parsed.active_day_id then active_day_id = parsed.active_day_id end
                if parsed.current_meal_idx then current_meal_idx = parsed.current_meal_idx end
                if parsed.last_auto_date then last_auto_date = parsed.last_auto_date end
                if parsed.user_override_date then user_override_date = parsed.user_override_date end

                -- Reset diário automático: se mudou a data, zera água e refeições concluídas
                if parsed.date == today_date then
                    water_consumed = parsed.water_consumed or 0
                    completed_meals = parsed.completed_meals or {}
                else
                    water_consumed = 0
                    completed_meals = {}
                end
            end
        end
    end
end

local function get_available_diet_files()
    local files = {}
    if Engine and Engine.files and Engine.files.list then
        local list = Engine.files.list()
        if list then
            for _, fname in ipairs(list) do
                local lower = string.lower(fname)
                if string.match(lower, "dieta.*%.json$") and lower ~= "dieta_state.json" then
                    table.insert(files, fname)
                end
            end
        end
    end
    table.sort(files)
    return files
end

-- ── Carregar Plano da Dieta (JSON) ──
local function load_plan_from_file(filename)
    filename = filename or active_file or "dieta.json"
    if Engine and Engine.files and Engine.files.exists(filename) then
        local content = Engine.files.read(filename)
        if content and Engine.json then
            local ok, parsed = pcall(function() return Engine.json.parse(content) end)
            if ok and parsed then
                -- Suporte tanto a formato com 'routines' quanto direto com 'meals'
                if parsed.meals and not parsed.routines then
                    parsed.routines = {
                        {
                            day_id = "A",
                            name = parsed.title or "Dieta Diária",
                            weekdays = { "seg", "ter", "qua", "qui", "sex", "sab", "dom" },
                            target_calories = parsed.target_calories or 2000,
                            target_protein = parsed.target_protein or 150,
                            target_carbs = parsed.target_carbs or 200,
                            target_fats = parsed.target_fats or 60,
                            meals = parsed.meals
                        }
                    }
                end

                if parsed.routines and #parsed.routines > 0 then
                    plan = parsed
                    active_file = filename
                    if parsed.active_day and parsed.active_day ~= "auto" then
                        active_day_id = parsed.active_day
                    end
                    return true, "Dieta carregada com sucesso de " .. filename
                end
            end
        end
    end

    -- Tenta dieta_exemplo.json se existir
    if filename ~= "dieta_exemplo.json" and Engine and Engine.files and Engine.files.exists("dieta_exemplo.json") then
        local content = Engine.files.read("dieta_exemplo.json")
        if content and Engine.json then
            local ok, parsed = pcall(function() return Engine.json.parse(content) end)
            if ok and parsed and parsed.routines and #parsed.routines > 0 then
                plan = parsed
                active_file = "dieta_exemplo.json"
                if parsed.active_day and parsed.active_day ~= "auto" then
                    active_day_id = parsed.active_day
                end
                return true, "Dieta carregada de dieta_exemplo.json"
            end
        end
    end

    -- Fallback default
    plan = get_default_plan()
    return false, "Usando plano de dieta padrão"
end

local function check_auto_day_switch(force)
    local today_num, today_date = get_today_info()
    if not plan or not plan.routines then return end

    if not force and user_override_date == today_date then
        return
    end

    if force or last_auto_date ~= today_date then
        for _, rot in ipairs(plan.routines) do
            if routine_matches_weekday(rot, today_num) then
                active_day_id = rot.day_id
                current_meal_idx = 1
                last_auto_date = today_date
                save_state()
                return
            end
        end
        last_auto_date = today_date
    end
end

-- ── Helpers de Rotina e Refeição Ativa ──
local function get_active_routine()
    if not plan or not plan.routines then return nil end
    for _, rot in ipairs(plan.routines) do
        if rot.day_id == active_day_id then
            return rot
        end
    end
    return plan.routines[1]
end

local function get_current_meal(rot)
    rot = rot or get_active_routine()
    if not rot or not rot.meals or #rot.meals == 0 then return nil end
    if current_meal_idx < 1 then current_meal_idx = 1 end
    if current_meal_idx > #rot.meals then current_meal_idx = #rot.meals end
    return rot.meals[current_meal_idx]
end

-- ── Inicialização ──
load_state()
load_plan_from_file(active_file)
check_auto_day_switch(false)

-- ── Render GUI ──
function M.render()
    check_auto_day_switch(false)
    local rot = get_active_routine()

    if not rot or not rot.meals or #rot.meals == 0 then
        return {
            type = "diet",
            title = "Dieta",
            plan_name = "Nenhum Plano Carregado",
            day_name = "Importe um plano com 'd file'",
            actions = {
                { label = "Carregar Exemplo", cmd = "d file dieta_exemplo.json" }
            }
        }
    end

    local meal = get_current_meal(rot)
    local total_meals = #rot.meals
    local is_curr_completed = meal and (completed_meals[meal.id] == true) or false

    -- Calcula Macros Consumidos Hoje com base nas refeições marcadas
    local cal_consumed = 0
    local p_consumed = 0
    local c_consumed = 0
    local f_consumed = 0

    for _, m in ipairs(rot.meals) do
        if completed_meals[m.id] then
            cal_consumed = cal_consumed + (m.calories or 0)
            p_consumed = p_consumed + (m.protein or 0)
            c_consumed = c_consumed + (m.carbs or 0)
            f_consumed = f_consumed + (m.fats or 0)
        end
    end

    -- Itens de Refeição para o Bloco em Destaque
    local current_items = {}
    if meal and meal.items then
        for _, it in ipairs(meal.items) do
            table.insert(current_items, {
                name = it.name or "",
                amount = it.amount or ""
            })
        end
    end

    -- Lista Completa de Refeições
    local ui_meals = {}
    for i, m in ipairs(rot.meals) do
        table.insert(ui_meals, {
            id = m.id,
            name = m.name or ("Refeição " .. i),
            time = m.time or "",
            calories = m.calories or 0,
            completed = (completed_meals[m.id] == true),
            current = (i == current_meal_idx),
            cmd = "d meal " .. i
        })
    end

    -- Lista de Dias/Rotinas disponíveis
    local today_num = get_today_info()
    local ui_days = {}
    for _, r in ipairs(plan.routines) do
        local is_today = routine_matches_weekday(r, today_num)
        table.insert(ui_days, {
            day_id = r.day_id,
            label = r.day_id .. (is_today and " (Hoje)" or ""),
            is_current = (r.day_id == active_day_id),
            is_today = is_today,
            cmd = "d day " .. r.day_id
        })
    end

    -- Lista de Arquivos de Dieta disponíveis
    local ui_files = {}
    if show_file_list then
        local files = get_available_diet_files()
        for _, fname in ipairs(files) do
            table.insert(ui_files, {
                name = fname,
                is_active = (fname == active_file),
                cmd = "d file " .. fname
            })
        end
    end

    -- Macros textuais da refeição atual
    local current_macros = ""
    if meal then
        local parts = {}
        if meal.protein then table.insert(parts, "P: " .. meal.protein .. "g") end
        if meal.carbs then table.insert(parts, "C: " .. meal.carbs .. "g") end
        if meal.fats then table.insert(parts, "G: " .. meal.fats .. "g") end
        current_macros = table.concat(parts, " | ")
    end

    -- Ações contextuais do rodapé
    local actions = {}
    table.insert(actions, { label = show_meal_list and "Ocultar Lista" or "Refeições", cmd = "d list" })
    table.insert(actions, { label = show_file_list and "Ocultar Fichas" or "Fichas", cmd = "d files" })
    table.insert(actions, { label = "Resetar Dia", cmd = "d reset" })

    return {
        type = "diet",
        title = "Dieta",
        plan_name = plan.title or "Plano Alimentar",
        day_name = rot.name or ("Dia " .. active_day_id),
        calories_consumed = cal_consumed,
        calories_target = rot.target_calories or 2000,
        protein_consumed = p_consumed,
        protein_target = rot.target_protein or 150,
        carbs_consumed = c_consumed,
        carbs_target = rot.target_carbs or 200,
        fats_consumed = f_consumed,
        fats_target = rot.target_fats or 60,
        water_consumed = water_consumed,
        water_target = plan.target_water_ml or 2500,
        current_meal_index = current_meal_idx,
        total_meals = total_meals,
        current_meal_name = meal and meal.name or "",
        current_meal_time = meal and meal.time or "",
        current_meal_calories = meal and meal.calories or 0,
        current_meal_macros = current_macros,
        current_meal_notes = meal and meal.notes or nil,
        current_meal_items = current_items,
        current_meal_completed = is_curr_completed,
        check_cmd = meal and ("d check " .. meal.id) or "d check",
        next_cmd = (current_meal_idx < total_meals) and "d next" or nil,
        prev_cmd = (current_meal_idx > 1) and "d prev" or nil,
        add_water_250_cmd = "d +250",
        add_water_500_cmd = "d +500",
        meals = ui_meals,
        show_meal_list = show_meal_list,
        toggle_list_cmd = "d list",
        days = ui_days,
        files = ui_files,
        show_file_list = show_file_list,
        toggle_files_cmd = "d files",
        actions = actions
    }
end

-- ── Comandos CLI ──
function M.on_command(args)
    local raw = args or ""
    local trimmed = raw:match("^%s*(.-)%s*$") or ""

    if trimmed == "" or trimmed == "help" or trimmed == "-h" then
        return "Comandos da Dieta:\n" ..
               "• d check [id]   : Conclui/desmarca refeição atual\n" ..
               "• d next / prev  : Navega entre refeições\n" ..
               "• d +250 / +500  : Adiciona 250ml ou 500ml de água\n" ..
               "• d water <ml>   : Registra quantidade exata de água\n" ..
               "• d day [A|B]    : Troca o dia/rotina ativa\n" ..
               "• d meal <num>   : Seleciona refeição pelo número\n" ..
               "• d file [nome]  : Carrega outro arquivo JSON de dieta\n" ..
               "• d list         : Alterna lista de refeições\n" ..
               "• d reset        : Reseta o consumo de água e refeições de hoje"
    end

    local tokens = {}
    for token in string.gmatch(trimmed, "%S+") do
        table.insert(tokens, token)
    end
    local cmd = string.lower(tokens[1] or "")

    -- ── Água: atalhos rápidos +250, +500, +X ──
    if cmd:match("^%+(%d+)$") then
        local ml = tonumber(cmd:match("^%+(%d+)$")) or 250
        water_consumed = water_consumed + ml
        save_state()
        if Engine and Engine.system and Engine.system.vibrate then
            Engine.system.vibrate(30)
        end
        return string.format("+%dml registrados. Total hoje: %dml", ml, water_consumed)
    end

    if cmd == "water" or cmd == "agua" or cmd == "água" then
        local param = tokens[2]
        if not param then
            return string.format("Consumo de água hoje: %dml", water_consumed)
        end
        local ml = tonumber(param)
        if ml then
            if param:sub(1,1) == "+" then
                water_consumed = water_consumed + ml
            else
                water_consumed = ml
            end
            save_state()
            return string.format("Água hoje: %dml", water_consumed)
        else
            return "Uso: d water <ml> (ex: d water 250 ou d +250)"
        end
    end

    if cmd == "water-" or cmd == "-water" then
        local ml = tonumber(tokens[2] or "250") or 250
        water_consumed = math.max(0, water_consumed - ml)
        save_state()
        return string.format("-%dml removidos. Total hoje: %dml", ml, water_consumed)
    end

    -- ── Check / Concluir Refeição ──
    if cmd == "check" or cmd == "c" or cmd == "done" or cmd == "comer" then
        local rot = get_active_routine()
        if not rot or not rot.meals or #rot.meals == 0 then
            return "Nenhuma refeição disponível."
        end

        local target_meal = nil
        local param = tokens[2]

        if param then
            -- Tenta achar por ID ou número
            local num = tonumber(param)
            if num and rot.meals[num] then
                target_meal = rot.meals[num]
                current_meal_idx = num
            else
                for _, m in ipairs(rot.meals) do
                    if string.lower(m.id) == string.lower(param) then
                        target_meal = m
                        break
                    end
                end
            end
        end

        if not target_meal then
            target_meal = get_current_meal(rot)
        end

        if target_meal then
            local is_done = completed_meals[target_meal.id] == true
            completed_meals[target_meal.id] = not is_done
            save_state()

            if Engine and Engine.system and Engine.system.vibrate then
                Engine.system.vibrate(40)
            end

            local status = completed_meals[target_meal.id] and "concluída" or "desmarcada"
            
            -- Se concluiu e não é a última refeição, avança automaticamente
            if completed_meals[target_meal.id] and current_meal_idx < #rot.meals then
                current_meal_idx = current_meal_idx + 1
                save_state()
            end

            return string.format("Refeição '%s' %s!", target_meal.name, status)
        end
        return "Refeição não encontrada."
    end

    -- ── Navegação entre refeições ──
    if cmd == "next" or cmd == "n" then
        local rot = get_active_routine()
        if rot and rot.meals and current_meal_idx < #rot.meals then
            current_meal_idx = current_meal_idx + 1
            save_state()
            local m = rot.meals[current_meal_idx]
            return string.format("Refeição %d/%d: %s (%s)", current_meal_idx, #rot.meals, m.name, m.time or "")
        else
            return "Você já está na última refeição."
        end
    end

    if cmd == "prev" or cmd == "p" then
        local rot = get_active_routine()
        if rot and rot.meals and current_meal_idx > 1 then
            current_meal_idx = current_meal_idx - 1
            save_state()
            local m = rot.meals[current_meal_idx]
            return string.format("Refeição %d/%d: %s (%s)", current_meal_idx, #rot.meals, m.name, m.time or "")
        else
            return "Você já está na primeira refeição."
        end
    end

    if cmd == "meal" or cmd == "m" then
        local num = tonumber(tokens[2])
        local rot = get_active_routine()
        if num and rot and rot.meals and num >= 1 and num <= #rot.meals then
            current_meal_idx = num
            save_state()
            local m = rot.meals[num]
            return string.format("Refeição %d: %s", num, m.name)
        else
            return "Número de refeição inválido."
        end
    end

    -- ── Trocar Dia / Rotina ──
    if cmd == "day" or cmd == "dia" then
        local target_day = tokens[2]
        if not target_day then
            return "Dia atual: " .. active_day_id .. ". Uso: d day [A|B|...]"
        end
        target_day = string.upper(target_day)
        if plan and plan.routines then
            for _, r in ipairs(plan.routines) do
                if string.upper(r.day_id) == target_day then
                    active_day_id = r.day_id
                    current_meal_idx = 1
                    local _, today_date = get_today_info()
                    user_override_date = today_date
                    save_state()
                    return string.format("Dia alterado para: %s (%s)", r.day_id, r.name)
                end
            end
        end
        return "Dia '" .. target_day .. "' não encontrado no plano."
    end

    -- ── Alternar Visualizações ──
    if cmd == "list" or cmd == "refeicoes" then
        show_meal_list = not show_meal_list
        return show_meal_list and "Lista de refeições exibida." or "Lista de refeições ocultada."
    end

    if cmd == "files" or cmd == "fichas" then
        show_file_list = not show_file_list
        return show_file_list and "Lista de arquivos exibida." or "Lista de arquivos ocultada."
    end

    -- ── Carregar Arquivo de Dieta ──
    if cmd == "file" or cmd == "load" or cmd == "import" then
        local fname = tokens[2]
        if not fname then
            local files = get_available_diet_files()
            return "Arquivo ativo: " .. active_file .. "\nDisponíveis: " .. table.concat(files, ", ")
        end
        if not string.match(fname, "%.json$") then
            fname = fname .. ".json"
        end
        local ok, msg = load_plan_from_file(fname)
        if ok then
            current_meal_idx = 1
            save_state()
            return "Sucesso: " .. msg
        else
            return "Erro: " .. msg
        end
    end

    -- ── Resetar Dia ──
    if cmd == "reset" then
        completed_meals = {}
        water_consumed = 0
        current_meal_idx = 1
        save_state()
        return "Progresso diário resetado."
    end

    return "Comando desconhecido. Digite 'd help' para ajuda."
end

-- ── Autocomplete ──
function M.autocomplete(args)
    local suggestions = {}
    local raw = args or ""
    local cmd = raw:match("^(%S+)") or ""

    if cmd == "" then
        table.insert(suggestions, { command = "d check", label = "Concluir refeição atual", executable = true })
        table.insert(suggestions, { command = "d +250", label = "+250ml de água", executable = true })
        table.insert(suggestions, { command = "d +500", label = "+500ml de água", executable = true })
        table.insert(suggestions, { command = "d next", label = "Próxima refeição", executable = true })
        table.insert(suggestions, { command = "d prev", label = "Refeição anterior", executable = true })
        table.insert(suggestions, { command = "d list", label = "Alternar lista de refeições", executable = true })
        table.insert(suggestions, { command = "d reset", label = "Resetar dia", executable = true })
    end

    return suggestions
end

return M
