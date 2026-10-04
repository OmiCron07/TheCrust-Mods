-- Blueprint library persistence: a single Lua-literal file loaded in an empty sandbox environment.

local Storage = {}

local function IsArray(T)
    local N = #T
    for K in pairs(T) do
        if type(K) ~= "number" or K < 1 or K > N or K % 1 ~= 0 then return false end
    end
    return true
end

-- Serializes plain data (tables, strings, numbers, booleans) to a Lua literal with stable key order.
function Storage.Serialize(V, Indent)
    Indent = Indent or ""
    local T = type(V)
    if T == "string" then return string.format("%q", V) end
    if T == "number" then
        if V % 1 == 0 and math.abs(V) < 2 ^ 53 then return string.format("%d", V) end
        return string.format("%.17g", V)
    end
    if T == "boolean" then return tostring(V) end
    if T ~= "table" then error("cannot serialize " .. T) end

    local Inner = Indent .. "  "
    local Parts = {}
    if IsArray(V) then
        -- Short arrays of scalars stay on one line to keep files compact and diffable.
        local Flat = true
        for _, X in ipairs(V) do if type(X) == "table" then Flat = false break end end
        for _, X in ipairs(V) do Parts[#Parts + 1] = Storage.Serialize(X, Inner) end
        if Flat then return "{" .. table.concat(Parts, ", ") .. "}" end
        if #Parts == 0 then return "{}" end
        return "{\n" .. Inner .. table.concat(Parts, ",\n" .. Inner) .. "\n" .. Indent .. "}"
    end

    local Keys = {}
    for K in pairs(V) do Keys[#Keys + 1] = K end
    table.sort(Keys, function(A, B) return tostring(A) < tostring(B) end)
    for _, K in ipairs(Keys) do
        local KS = (type(K) == "string" and K:match("^[%a_][%w_]*$")) and K or ("[" .. Storage.Serialize(K) .. "]")
        Parts[#Parts + 1] = KS .. " = " .. Storage.Serialize(V[K], Inner)
    end
    if #Parts == 0 then return "{}" end
    return "{\n" .. Inner .. table.concat(Parts, ",\n" .. Inner) .. "\n" .. Indent .. "}"
end

function Storage.Deserialize(Text)
    local Chunk, Err = load("return " .. Text, "=blueprints", "t", {})
    if not Chunk then return nil, Err end
    local Ok, Value = pcall(Chunk)
    if not Ok then return nil, Value end
    return Value
end

-- File = absolute path of the library file. Returns array of blueprints (empty on missing file).
function Storage.Load(File)
    local F = io.open(File, "r")
    if not F then return {} end
    local Text = F:read("a")
    F:close()
    local Data, Err = Storage.Deserialize(Text)
    if type(Data) ~= "table" then
        -- Keep the unreadable file aside instead of overwriting the user's library on next save.
        os.rename(File, File .. ".corrupt-" .. os.time())
        print("[Blueprints] Library unreadable, moved aside: " .. tostring(Err) .. "\n")
        return {}
    end
    return Data.Blueprints or {}
end

function Storage.Save(File, Blueprints)
    local Tmp = File .. ".tmp"
    local F = assert(io.open(Tmp, "w"))
    F:write(Storage.Serialize({ Version = 1, Blueprints = Blueprints }))
    F:close()
    os.remove(File)
    assert(os.rename(Tmp, File))
end

return Storage
