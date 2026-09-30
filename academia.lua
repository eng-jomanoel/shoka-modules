-- GYM / WORKOUT TRACKER MODULE (academia.lua)
-- Offline workout manager supporting JSON routine import, weight/reps tracking,
-- synchronized rest countdown timer, haptic vibration feedback, GUI & CLI.

local M = {}

M.id = "gym"
M.name = "Gym Tracker"
M.prefix = "g"
M.help = "g check | g skip | g <kg> [reps] | g +2.5 | g -2.5 | g next | g prev | g day [A|B|C] | g list | g import [file] | g reset"

-- Internal State
local plan = nil
local active_day_id = "A"
local current_ex_idx = 1
local show_exercise_list = false

-- Rest Timer State
local is_timer_active = false
local timer_end = 0
local timer_total = 60

-- Exercise Progress Tracking (keyed by exercise id)
local exercise_states = {}

-- Fallback Default Workout Plan
local function get_default_plan()
    return {
        version = 1,
        active_day = "A",
        routines = {
            {
                day_id = "A",
                name = "Treino A - Peito, Tríceps & Ombro",
                exercises = {
                    { id = "supino_reto", name = "Supino Reto com Barra", target_sets = 4, target_reps = "8-12", default_weight = 80.0, rest_seconds = 90, notes = "Controle na descida" },
                    { id = "supino_inclinado", name = "Supino Inclinado com Halteres", target_sets = 3, target_reps = "10-12", default_weight = 26.0, rest_seconds = 60, notes = "Banco a 30 graus" },
                    { id = "crucifixo_polia", name = "Crucifixo na Polia Média", target_sets = 3, target_reps = "12-15", default_weight = 15.0, rest_seconds = 60, notes = "Contração de 1s" },
                    { id = "elevacao_lateral", name = "Elevação Lateral", target_sets = 4, target_reps = "12-15", default_weight = 12.0, rest_seconds = 45, notes = "Sem embalo" },
                    { id = "triceps_corda", name = "Tríceps Corda na Polia", target_sets = 4, target_reps = "10-12", default_weight = 25.0, rest_seconds = 45, notes = "Abrir no final" }
                }
            },
            {
                day_id = "B",
                name = "Treino B - Costas & Bíceps",
                exercises = {
                    { id = "puxada_alta", name = "Puxada Alta Frontal", target_sets = 4, target_reps = "8-12", default_weight = 60.0, rest_seconds = 90, notes = "Puxar com os cotovelos" },
                    { id = "remada_curvada", name = "Remada Curvada com Barra", target_sets = 4, target_reps = "8-10", default_weight = 65.0, rest_seconds = 90, notes = "Tronco a 45 graus" },
                    { id = "rosca_direta", name = "Rosca Direta Barra W", target_sets = 4, target_reps = "10-12", default_weight = 28.0, rest_seconds = 60, notes = "Sem balanço" }
                }
            },
            {
                day_id = "C",
                name = "Treino C - Pernas & Abdômen",
                exercises = {
                    { id = "agachamento_livre", name = "Agachamento Livre", target_sets = 4, target_reps = "8-10", default_weight = 90.0, rest_seconds = 120, notes = "Profundidade completa" },
                    { id = "leg_press_45", name = "Leg Press 45°", target_sets = 4, target_reps = "10-12", default_weight = 180.0, rest_seconds = 90, notes = "Amplitude total" },
                    { id = "panturrilha_em_pe", name = "Panturrilha em Pé", target_sets = 4, target_reps = "15-20", default_weight = 70.0, rest_seconds = 45, notes = "Pausa no topo" }
                }
            }
        }
    }
end

-- Save / Load State
local function save_state()
    local data = {
        active_day_id = active_day_id,
        current_ex_idx = current_ex_idx,
        states = exercise_states
    }
    if Engine and Engine.json and Engine.files then
        local encoded = Engine.json.encode(data)
        Engine.files.write("treino_state.json", encoded)
    end
end

local function load_state()
    if Engine and Engine.files and Engine.files.exists("treino_state.json") then
        local content = Engine.files.read("treino_state.json")
        if content and Engine.json then
            local parsed = Engine.json.parse(content)
            if parsed then
                if parsed.active_day_id then active_day_id = parsed.active_day_id end
                if parsed.current_ex_idx then current_ex_idx = parsed.current_ex_idx end
                if parsed.states then exercise_states = parsed.states end
            end
        end
    end
end

-- Load Workout Plan from JSON
local function load_plan_from_file(filename)
    filename = filename or "treino.json"
    if Engine and Engine.files and Engine.files.exists(filename) then
        local content = Engine.files.read(filename)
        if content and Engine.json then
            local parsed = Engine.json.parse(content)
            if parsed and parsed.routines and #parsed.routines > 0 then
                plan = parsed
                if parsed.active_day then
                    active_day_id = parsed.active_day
                end
                return true, "Plano carregado com sucesso de " .. filename
            end
        end
    end

    -- Try treino_exemplo.json
    if Engine and Engine.files and Engine.files.exists("treino_exemplo.json") then
        local content = Engine.files.read("treino_exemplo.json")
        if content and Engine.json then
            local parsed = Engine.json.parse(content)
            if parsed and parsed.routines and #parsed.routines > 0 then
                plan = parsed
                if parsed.active_day then
                    active_day_id = parsed.active_day
                end
                return true, "Plano de exemplo carregado de treino_exemplo.json"
            end
        end
    end

    plan = get_default_plan()
    return false, "Usando treino padrão embutido."
end

load_plan_from_file()
load_state()

-- Helper Functions
local function get_current_routine()
    if not plan or not plan.routines then return nil end
    for _, r in ipairs(plan.routines) do
        if r.day_id == active_day_id then
            return r
        end
    end
    return plan.routines[1]
end

local function get_current_exercise()
    local r = get_current_routine()
    if not r or not r.exercises or #r.exercises == 0 then return nil end
    if current_ex_idx < 1 then current_ex_idx = 1 end
    if current_ex_idx > #r.exercises then current_ex_idx = #r.exercises end
    return r.exercises[current_ex_idx]
end

local function get_exercise_state(ex)
    if not ex then return { completed_sets = 0, weight = 0, reps = 10, is_completed = false } end
    local key = active_day_id .. "_" .. (ex.id or ex.name)
    if not exercise_states[key] then
        local initial_reps = 10
        if ex.target_reps then
            local n = tonumber(string.match(ex.target_reps, "(%d+)"))
            if n then initial_reps = n end
        end
        exercise_states[key] = {
            completed_sets = 0,
            weight = ex.default_weight or 0,
            reps = initial_reps,
            is_completed = false
        }
    end
    return exercise_states[key]
end

-- Start Rest Timer
local function start_rest_timer(seconds)
    seconds = seconds or 60
    timer_total = seconds
    timer_end = Engine.time.now() + (seconds * 1000)
    is_timer_active = true
end

local function stop_rest_timer()
    is_timer_active = false
    timer_end = 0
end

-- Render Function called by Launcher Feed
function M.render()
    local r = get_current_routine()
    if not r or not r.exercises or #r.exercises == 0 then
        return {
            type = "workout",
            title = "Gym Tracker",
            day_name = "Nenhum Treino Carregado",
            exercise_name = "Importe um plano com 'g import'",
            current_set = 0,
            total_sets = 0,
            target_reps = "-",
            weight = 0,
            reps_logged = 0,
            actions = {
                { label = "Importar Treino", cmd = "g import" }
            }
        }
    end

    local ex = get_current_exercise()
    local st = get_exercise_state(ex)

    -- Check timer countdown
    local remaining_secs = 0
    if is_timer_active then
        local now = Engine.time.now()
        local diff = math.ceil((timer_end - now) / 1000)
        if diff <= 0 then
            is_timer_active = false
            remaining_secs = 0
            if Engine and Engine.system then
                Engine.system.vibrate(600)
                Engine.system.toast("Descanso concluído! Próxima série!")
            end
        else
            remaining_secs = diff
        end
    end

    -- Calculate completed exercises in routine
    local completed_count = 0
    for _, e in ipairs(r.exercises) do
        local s = get_exercise_state(e)
        if s.is_completed then
            completed_count = completed_count + 1
        end
    end

    -- Build Action buttons
    local actions = {}
    if is_timer_active then
        table.insert(actions, { label = "Pular Timer", cmd = "g skip" })
        table.insert(actions, { label = "+30s", cmd = "g +30" })
        table.insert(actions, { label = show_exercise_list and "Fechar" or "Lista", cmd = "g list" })
    else
        table.insert(actions, { label = "✓ Check", cmd = "g check" })
        table.insert(actions, { label = "-2.5kg", cmd = "g -2.5" })
        table.insert(actions, { label = "+2.5kg", cmd = "g +2.5" })
        table.insert(actions, { label = show_exercise_list and "Fechar" or "Lista", cmd = "g list" })
    end

    -- Build Exercise list
    local exercise_items = {}
    for i, e in ipairs(r.exercises) do
        local s = get_exercise_state(e)
        local info_str = string.format("%dx %s | %s kg", e.target_sets or 4, e.target_reps or "8-12", tostring(s.weight or 0))
        table.insert(exercise_items, {
            index = i,
            name = e.name,
            info = info_str,
            completed = s.is_completed,
            current = (i == current_ex_idx),
            cmd = "g sel " .. i
        })
    end

    local display_set = math.min(st.completed_sets + 1, ex.target_sets or 4)
    if st.is_completed then
        display_set = ex.target_sets or 4
    end

    return {
        type = "workout",
        title = "Gym Tracker",
        day_name = r.name or ("Treino " .. active_day_id),
        exercise_name = ex.name or "Exercício",
        current_set = display_set,
        total_sets = ex.target_sets or 4,
        target_reps = ex.target_reps or "8-12",
        weight = st.weight or 0,
        reps_logged = st.reps or 10,
        is_timer_active = is_timer_active,
        timer_remaining = remaining_secs,
        timer_total = timer_total,
        progress_text = string.format("%d/%d Feitos", completed_count, #r.exercises),
        actions = actions,
        exercises = exercise_items,
        show_list = show_exercise_list
    }
end

-- Command Dispatcher
function M.on_command(args)
    local raw = string.gsub(args or "", "^%s*(.-)%s*$", "%1")
    local tokens = {}
    for word in string.gmatch(raw, "%S+") do
        table.insert(tokens, word)
    end

    local cmd = string.lower(tokens[1] or "")

    if cmd == "-h" or cmd == "--help" then
        return "COMANDOS DE TREINO (g)\n" ..
               "  g               : Status do exercício atual\n" ..
               "  g check / g c   : Conclui a série atual e inicia o descanso\n" ..
               "  g skip / g s    : Pula o cronômetro de descanso\n" ..
               "  g +30 / g -30   : Ajusta o timer de descanso em 30s\n" ..
               "  g <kg> [reps]   : Define carga e repetições (ex: 'g 85 10')\n" ..
               "  g +<kg> / -<kg> : Ajusta carga (ex: 'g +2.5', 'g -5')\n" ..
               "  g next / g prev : Avança ou volta exercício\n" ..
               "  g sel <idx>     : Seleciona exercício pelo número\n" ..
               "  g day [A|B|C]   : Troca o dia/rotina de treino\n" ..
               "  g list / g view : Abre/fecha a lista de exercícios\n" ..
               "  g import [file] : Importa plano JSON de Documents/Shoka/data/\n" ..
               "  g reset         : Reseta o progresso do dia atual"
    end

    local ex = get_current_exercise()
    local st = get_exercise_state(ex)
    local r = get_current_routine()

    -- g check / g c
    if cmd == "check" or cmd == "c" then
        if not ex or not st then return "Nenhum exercício ativo." end

        st.completed_sets = st.completed_sets + 1
        local rest_time = ex.rest_seconds or 60

        if st.completed_sets >= (ex.target_sets or 4) then
            st.is_completed = true
            stop_rest_timer()
            save_state()

            -- Check if all exercises in this routine are done
            local all_done = true
            for _, e in ipairs(r.exercises) do
                local s = get_exercise_state(e)
                if not s.is_completed then all_done = false break end
            end

            if all_done then
                return "🎉 PARABÉNS! Você concluiu todos os exercícios do " .. r.name .. "!"
            else
                -- Advance to next pending exercise
                for i = 1, #r.exercises do
                    local next_idx = ((current_ex_idx + i - 1) % #r.exercises) + 1
                    local s = get_exercise_state(r.exercises[next_idx])
                    if not s.is_completed then
                        current_ex_idx = next_idx
                        break
                    end
                end
                start_rest_timer(rest_time)
                save_state()
                local next_ex = get_current_exercise()
                return string.format("✓ %s finalizado! Descanso de %ds iniciado para: %s", ex.name, rest_time, next_ex.name)
            end
        else
            start_rest_timer(rest_time)
            save_state()
            return string.format("Série %d/%d concluída! Descanso de %ds iniciado.", st.completed_sets, ex.target_sets or 4, rest_time)
        end
    end

    -- g skip / g s
    if cmd == "skip" or cmd == "s" then
        stop_rest_timer()
        return "Descanso finalizado. Pronto para a próxima série!"
    end

    -- g +30 / g -30
    if cmd == "+30" then
        if is_timer_active then
            timer_end = timer_end + 30000
            timer_total = timer_total + 30
            return "+30 segundos adicionados ao descanso."
        else
            start_rest_timer(30)
            return "Descanso de 30s iniciado."
        end
    elseif cmd == "-30" then
        if is_timer_active then
            timer_end = math.max(Engine.time.now(), timer_end - 30000)
            return "-30 segundos reduzidos do descanso."
        end
        return "Nenhum timer ativo."
    end

    -- g next / g prev
    if cmd == "next" then
        if current_ex_idx < #r.exercises then
            current_ex_idx = current_ex_idx + 1
        else
            current_ex_idx = 1
        end
        save_state()
        local next_ex = get_current_exercise()
        return "Exercício selecionado: " .. next_ex.name
    elseif cmd == "prev" then
        if current_ex_idx > 1 then
            current_ex_idx = current_ex_idx - 1
        else
            current_ex_idx = #r.exercises
        end
        save_state()
        local prev_ex = get_current_exercise()
        return "Exercício selecionado: " .. prev_ex.name
    end

    -- g sel <idx>
    if cmd == "sel" then
        local idx = tonumber(tokens[2])
        if idx and idx >= 1 and idx <= #r.exercises then
            current_ex_idx = idx
            save_state()
            local selected = get_current_exercise()
            return "Exercício selecionado: " .. selected.name
        end
        return "Índice de exercício inválido."
    end

    -- g list / g view
    if cmd == "list" or cmd == "view" then
        show_exercise_list = not show_exercise_list
        return show_exercise_list and "Lista de exercícios aberta." or "Lista de exercícios fechada."
    end

    -- g day [A|B|C]
    if cmd == "day" then
        local target = tokens[2] and string.upper(tokens[2])
        if target then
            for _, rot in ipairs(plan.routines) do
                if string.upper(rot.day_id) == target then
                    active_day_id = rot.day_id
                    current_ex_idx = 1
                    save_state()
                    return "Rotina alterada para: " .. rot.name
                end
            end
            return "Dia '" .. target .. "' não encontrado nas rotinas disponíveis."
        else
            -- List available days
            local sb = { "DIAS DISPONÍVEIS:" }
            for _, rot in ipairs(plan.routines) do
                local mark = (rot.day_id == active_day_id) and " [ATIVO]" or ""
                table.insert(sb, string.format("  [%s] %s%s", rot.day_id, rot.name, mark))
            end
            table.insert(sb, "Digite 'g day <letra>' para trocar.")
            return table.concat(sb, "\n")
        end
    end

    -- g import [filename]
    if cmd == "import" then
        local fname = tokens[2] or "treino.json"
        local ok, msg = load_plan_from_file(fname)
        current_ex_idx = 1
        save_state()
        return msg
    end

    -- g reset
    if cmd == "reset" then
        for _, e in ipairs(r.exercises) do
            local key = active_day_id .. "_" .. (e.id or e.name)
            exercise_states[key] = {
                completed_sets = 0,
                weight = e.default_weight or 0,
                reps = 10,
                is_completed = false
            }
        end
        stop_rest_timer()
        save_state()
        return "Progresso do " .. r.name .. " zerado para hoje!"
    end

    -- Numeric load / reps adjustments: e.g. "g 85 10", "g +2.5", "g -5"
    local first_token = tokens[1] or ""
    if string.sub(first_token, 1, 1) == "+" or string.sub(first_token, 1, 1) == "-" then
        local delta = tonumber(first_token)
        if delta and st then
            st.weight = math.max(0, (st.weight or 0) + delta)
            save_state()
            return string.format("Carga de %s ajustada para %.1f kg", ex.name, st.weight)
        end
    end

    local weight_arg = tonumber(first_token)
    if weight_arg and st then
        st.weight = weight_arg
        local reps_arg = tonumber(tokens[2])
        if reps_arg then
            st.reps = reps_arg
            save_state()
            return string.format("Carga de %s definida para %.1f kg x %d reps", ex.name, st.weight, st.reps)
        else
            save_state()
            return string.format("Carga de %s definida para %.1f kg", ex.name, st.weight)
        end
    end

    -- Default: status summary
    if ex and st then
        return string.format("[%s] %s | Série %d/%d | %.1f kg x %d reps",
            r.name, ex.name, math.min(st.completed_sets + 1, ex.target_sets or 4), ex.target_sets or 4, st.weight, st.reps)
    end

    return "Uso: 'g check', 'g skip', 'g <kg> [reps]', 'g day', ou 'g -h' para ajuda."
end

return M
