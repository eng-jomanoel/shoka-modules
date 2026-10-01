-- ============================================================
-- notes.lua — Módulo de Anotações e Checklist para Shoka
-- Prefixo: n
-- ============================================================
local M = {}
M.id = "notes"
M.name = "Notas"
M.prefix = "n"
M.help = "n <texto>         → Adiciona nota\nn [] <texto>      → Adiciona checklist\nn toggle <id>     → Marca/desmarca\nn del <id>        → Remove item\nn clear           → Limpa finalizados\nn open / n close  → Mostra/oculta card"

-- ── Estado ──
local is_open = false
local notes = {}    -- { {id=1, text="...", checklist=false, checked=false}, ... }
local next_id = 1
local DATA_FILE = "notes.json"

-- ── Helpers ──
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
        if ok and data then
            notes = data.notes or {}
            next_id = data.next_id or 1
            is_open = data.is_open or false
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
    if not is_open then return nil end

    local items = {}
    for _, note in ipairs(notes) do
        table.insert(items, {
            id = note.id,
            text = note.text,
            is_checklist = note.checklist,
            is_checked = note.checked,
            toggle_cmd = note.checklist and ("n toggle " .. note.id) or nil,
            delete_cmd = "n del " .. note.id
        })
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
    table.insert(actions, { label = "✕ Fechar", cmd = "n close" })

    return {
        type = "notes",
        title = "📝 Notas",
        subtitle = subtitle,
        is_open = true,
        items = items,
        actions = actions
    }
end

-- ── Comandos ──
function M.on_command(args)
    local raw = args or ""
    local cmd = raw:match("^(%S+)")

    if not cmd or cmd == "" then
        -- Sem argumentos: toggle abrir/fechar
        is_open = not is_open
        save_state()
        return is_open and "Notas abertas" or "Notas fechadas"
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
        return "Notas fechadas"
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
    if cmd == "[]" or cmd == "[" then
        local text = raw:match("^%S+%s+(.*)")
        -- Se cmd foi "[", pode ter "]" no inicio do texto
        if cmd == "[" then
            text = raw:match("^%[%]?%s*(.*)")
        end
        if not text or text == "" then return "Uso: n [] <texto>" end
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

    -- ── Adicionar nota simples (qualquer outro texto) ──
    -- Se chegou aqui, o comando inteiro é o texto da nota
    local text = raw
    local is_checklist = false

    -- Detecta prefixo [] no texto
    if text:match("^%[%]%s") then
        text = text:match("^%[%]%s+(.*)")
        is_checklist = true
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
        return "☐ Adicionado: " .. text
    else
        return "📝 Adicionado: " .. text
    end
end

-- ── Autocomplete ──
function M.autocomplete(args)
    local suggestions = {}
    local raw = args or ""
    local cmd = raw:match("^(%S+)") or ""

    if cmd == "" then
        -- Sugestões iniciais
        table.insert(suggestions, { command = "n open", label = "Abrir notas", executable = true })
        table.insert(suggestions, { command = "n close", label = "Fechar notas", executable = true })
        table.insert(suggestions, { command = "n [] ", label = "Nova tarefa", executable = false })
        table.insert(suggestions, { command = "n ", label = "Nova nota", executable = false })
        if #notes > 0 then
            table.insert(suggestions, { command = "n clear", label = "Limpar feitos", executable = true })
            table.insert(suggestions, { command = "n clearall", label = "Limpar tudo", executable = true })
        end
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
