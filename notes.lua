-- ============================================================
-- notes.lua — Módulo de Anotações Rápidas e Checklist para Shoka
-- Prefixo: n
-- ============================================================
local M = {}
M.id = "notes"
M.name = "Notas"
M.prefix = "n"
M.help = "n <texto>         → Adiciona nota\nn [] <texto>      → Adiciona checklist\nn toggle <id>     → Marca/desmarca tarefa\nn del <id>        → Remove item\nn clear           → Limpa itens finalizados\nn clearall        → Limpa todas as notas\nn open / n close  → Expande/recolhe card"

-- ── Estado ──
local is_open = true
local notes = {}    -- { {id=1, text="...", checklist=false, checked=false}, ... }
local next_id = 1
local DATA_FILE = "notes.json"

-- ── Helpers de Persistência ──
local function save_state()
    local data = Engine.json.encode({
        notes = notes,
        next_id = next_id,
        is_open = is_open
    })
    Engine.files.write(DATA_FILE, data)
end

local function load_state()
    local raw = Engine.files.read(DATA_FILE)
    if raw and raw ~= "" then
        local ok, data = pcall(function() return Engine.json.decode(raw) end)
        if not ok or not data then
            ok, data = pcall(function() return Engine.json.parse(raw) end)
        end
        if ok and type(data) == "table" then
            notes = data.notes or {}
            next_id = data.next_id or 1
            if data.is_open ~= nil then
                is_open = data.is_open
            else
                is_open = true
            end
        end
    end
end

local function find_note(id)
    for i, note in ipairs(notes) do
        if note.id == id then return i, note end
    end
    return nil, nil
end

-- ── Inicialização ──
load_state()

-- ── Render ──
function M.render()
    local items = {}
    if is_open then
        for _, note in ipairs(notes) do
            table.insert(items, {
                id = note.id,
                text = note.text,
                is_checklist = note.checklist or false,
                is_checked = note.checked or false,
                toggle_cmd = note.checklist and ("n toggle " .. note.id) or nil,
                delete_cmd = "n del " .. note.id
            })
        end
    end

    -- Contagem para subtitle
    local total = #notes
    local checked_count = 0
    for _, n in ipairs(notes) do
        if n.checklist and n.checked then checked_count = checked_count + 1 end
    end

    local subtitle = nil
    if total > 0 then
        subtitle = total .. " nota" .. (total > 1 and "s" or "")
    end

    local actions = {}
    if is_open then
        local has_checked = false
        for _, n in ipairs(notes) do
            if n.checklist and n.checked then has_checked = true break end
        end
        if has_checked then
            table.insert(actions, { label = "🗑 Limpar feitos", cmd = "n clear" })
        end
        if #notes > 0 then
            table.insert(actions, { label = "📋 Limpar tudo", cmd = "n clearall" })
        end
        table.insert(actions, { label = "✕ Recolher", cmd = "n close" })
    else
        table.insert(actions, { label = "Abrir", cmd = "n open" })
    end

    return {
        type = "notes",
        title = "📝 Notas",
        subtitle = subtitle,
        is_open = is_open,
        input_hint = is_open and "Anotação rápida ou [] tarefa..." or nil,
        input_cmd = is_open and "n" or nil,
        items = items,
        actions = actions
    }
end

-- ── Comandos ──
function M.on_command(args)
    local raw = args or ""
    local cmd = raw:match("^(%S+)")

    if not cmd or cmd == "" then
        -- Sem argumentos: inverte expandir/recolher
        is_open = not is_open
        save_state()
        return is_open and "Notas expandidas" or "Notas recolhidas"
    end

    cmd = cmd:lower()

    -- ── Abrir / Fechar ──
    if cmd == "open" or cmd == "abrir" then
        is_open = true
        save_state()
        return "Notas abertas"
    end

    if cmd == "close" or cmd == "fechar" then
        is_open = false
        save_state()
        return "Notas recolhidas"
    end

    -- ── Toggle check ──
    if cmd == "toggle" or cmd == "t" then
        local id_str = raw:match("^%S+%s+(%d+)")
        if not id_str then return "Uso: n toggle <id>" end
        local id = tonumber(id_str)
        local idx, note = find_note(id)
        if not note then return "Nota #" .. id .. " não encontrada" end
        if not note.checklist then return "Nota #" .. id .. " não é checklist" end
        note.checked = not note.checked
        save_state()
        return (note.checked and "✓" or "○") .. " " .. note.text
    end

    -- ── Deletar ──
    if cmd == "del" or cmd == "rm" or cmd == "delete" then
        local id_str = raw:match("^%S+%s+(%d+)")
        if not id_str then return "Uso: n del <id>" end
        local id = tonumber(id_str)
        local idx, note = find_note(id)
        if not note then return "Nota #" .. id .. " não encontrada" end
        table.remove(notes, idx)
        save_state()
        return "Removido: " .. note.text
    end

    -- ── Limpar finalizados ──
    if cmd == "clear" then
        local removed = 0
        for i = #notes, 1, -1 do
            if notes[i].checklist and notes[i].checked then
                table.remove(notes, i)
                removed = removed + 1
            end
        end
        save_state()
        return removed .. " item(ns) finalizado(s) removido(s)"
    end

    -- ── Limpar tudo ──
    if cmd == "clearall" then
        local count = #notes
        notes = {}
        save_state()
        return count .. " nota(s) removida(s)"
    end

    -- ── Adicionar checklist ([] prefixo) ──
    if cmd == "[]" or cmd == "[" or cmd == "[ ]" then
        local text = raw:match("^%S+%s+(.*)")
        if cmd == "[" then
            text = raw:match("^%[%]?%s*(.*)")
        end
        if not text or text:match("^%s*$") then return "Uso: n [] <texto>" end
        local note = {
            id = next_id,
            text = text,
            checklist = true,
            checked = false
        }
        table.insert(notes, note)
        next_id = next_id + 1
        is_open = true
        save_state()
        return "☐ Adicionado: " .. text
    end

    -- ── Adicionar nota simples ou tarefa (se iniciar com []) ──
    local text = raw
    local is_checklist = false

    -- Detecta se texto começa com [] ou [ ]
    if text:match("^%[%]%s*") then
        text = text:gsub("^%[%]%s*", "")
        is_checklist = true
    elseif text:match("^%[%s*%]%s*") then
        text = text:gsub("^%[%s*%]%s*", "")
        is_checklist = true
    end

    if text:match("^%s*$") then
        return "Anotação vazia ignorada"
    end

    local note = {
        id = next_id,
        text = text,
        checklist = is_checklist,
        checked = false
    }
    table.insert(notes, note)
    next_id = next_id + 1
    is_open = true
    save_state()

    if is_checklist then
        return "☐ Tarefa adicionada: " .. text
    else
        return "📝 Anotação salva: " .. text
    end
end

-- ── Autocomplete ──
function M.autocomplete(args)
    local suggestions = {}
    local raw = args or ""
    local cmd = raw:match("^(%S+)") or ""

    if cmd == "" then
        table.insert(suggestions, { command = "n ", label = "📝 Nova anotação rápida", executable = false })
        table.insert(suggestions, { command = "n [] ", label = "☐ Nova tarefa checklist", executable = false })
        if #notes > 0 then
            table.insert(suggestions, { command = "n clear", label = "🗑 Limpar feitos", executable = true })
            table.insert(suggestions, { command = "n clearall", label = "📋 Limpar todas", executable = true })
        end
        table.insert(suggestions, { command = "n open", label = "Expandir notas", executable = true })
        table.insert(suggestions, { command = "n close", label = "Recolher notas", executable = true })
    elseif cmd == "toggle" or cmd == "t" then
        for _, note in ipairs(notes) do
            if note.checklist then
                local status = note.checked and "✓" or "○"
                table.insert(suggestions, {
                    command = "n toggle " .. note.id,
                    label = status .. " " .. note.text,
                    executable = true
                })
            end
        end
    elseif cmd == "del" or cmd == "rm" then
        for _, note in ipairs(notes) do
            table.insert(suggestions, {
                command = "n del " .. note.id,
                label = "🗑 " .. note.text,
                executable = true
            })
        end
    end

    return suggestions
end

return M
