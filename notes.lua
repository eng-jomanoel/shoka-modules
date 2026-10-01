-- ============================================================
-- notes.lua — Bloco de Notas simples para Shoka
-- Prefixo: n
-- ============================================================
local M = {}
M.id = "notes"
M.name = "Notas"
M.prefix = "n"
M.help = "n <texto>  → Adiciona anotação\nn clear    → Limpa o bloco de notas"

-- ── Estado ──
local content = ""
local DATA_FILE_TXT = "notes.txt"
local DATA_FILE_JSON = "notes.json"

-- ── Helpers de Persistência ──
local function save_state()
    Engine.files.write(DATA_FILE_TXT, content)
    -- Mantém JSON sincronizado para compatibilidade
    Engine.files.write(DATA_FILE_JSON, Engine.json.encode({ content = content }))
end

local function load_state()
    -- Tenta carregar do arquivo de texto simples primeiro
    local txt = Engine.files.read(DATA_FILE_TXT)
    if txt and txt ~= "" then
        content = txt
        return
    end

    -- Migração/Fallback de versão anterior (JSON)
    local raw = Engine.files.read(DATA_FILE_JSON)
    if raw and raw ~= "" then
        local ok, data = pcall(function() return Engine.json.decode(raw) end)
        if not ok or not data then
            ok, data = pcall(function() return Engine.json.parse(raw) end)
        end
        if ok and type(data) == "table" then
            if type(data.content) == "string" then
                content = data.content
            elseif type(data.notes) == "table" then
                local lines = {}
                for _, n in ipairs(data.notes) do
                    if type(n) == "table" and n.text then
                        table.insert(lines, n.text)
                    elseif type(n) == "string" then
                        table.insert(lines, n)
                    end
                end
                content = table.concat(lines, "\n")
            end
        elseif type(raw) == "string" and not raw:match("^{") then
            content = raw
        end
    end
end

-- ── Inicialização ──
load_state()

-- ── Render ──
function M.render()
    return {
        type = "notes",
        title = "Notas",
        content = content
    }
end

-- ── Comandos ──
function M.on_command(args)
    local raw = args or ""

    -- Se vazio, mostra o conteúdo atual
    if raw:match("^%s*$") then
        if content == "" then
            return "Bloco de notas vazio."
        else
            return content
        end
    end

    local first_token = raw:match("^(%S+)")
    local first_lower = (first_token or ""):lower()

    -- Comando para limpar
    if first_lower == "clear" or first_lower == "limpar" or first_lower == "cls" then
        content = ""
        save_state()
        return "Bloco de notas limpo."
    end

    -- Comando interno de salvar todo o texto editado na UI
    if first_lower == "set" then
        local new_content = raw:sub(#first_token + 1)
        new_content = new_content:gsub("^%s", "") -- remove apenas o primeiro espaço separador
        content = new_content
        save_state()
        return "Bloco de notas salvo."
    end

    -- Qualquer outro texto: anota no bloco (adiciona linha)
    local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if content == "" then
        content = trimmed
    else
        content = content .. "\n" .. trimmed
    end
    save_state()
    return "Anotado: " .. trimmed
end

-- ── Autocomplete ──
function M.autocomplete(args)
    local suggestions = {}
    local raw = args or ""
    local cmd = raw:match("^(%S+)") or ""

    if cmd == "" then
        table.insert(suggestions, { command = "n ", label = "Anotar no bloco de notas", executable = false })
        if content ~= "" then
            table.insert(suggestions, { command = "n clear", label = "Limpar bloco de notas", executable = true })
        end
    end

    return suggestions
end

return M
