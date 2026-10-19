-- Share strings: one blueprint as "TCBP1:" + base64url(raw DEFLATE(positional Lua literal payload)).
-- Pure Lua (no game calls). Decode input comes from strangers: it is parsed by a literal reader
-- (never load), every field is validated, and any failure returns nil, message.
--
-- Payload: { Name, Layer, Classes, Modules, Belts, Undergrounds, Links, Distributors }
--   Classes      : class paths without "/Game/" and the ".<Leaf>_C" object suffix
--   Module       : { ClassIndex, DR, DC, Turns, Mirrored (0/1), Recipe, Cells, IO }
--                  Cells = flat { dr, dc, ... }, or 0 = the Cells of the first earlier module with the
--                  same (Class, Turns, Mirrored) translated by the (DR, DC) delta
--                  IO = 0 (none) or list of 0 (invalid IO cell) / { Agency, Lock | Overflow << 1, Filter }
--   Belt path    : { R, C, Letters } one letter per cell = char(97 + Dir * 4 + Move), Move = direction
--                  to the next cell (last cell: Dir); or flat { r, c, dir, ... } (dir -1 = none) when a
--                  path has a missing direction or a non-adjacent step
--   Underground  : { R1, C1, R2, C2, Dir }
--   Links        : flat { A, B, ... }
--   Distributor  : { DR, DC, Outputs, Inputs }, Output = { Dir, Level, Bits, Types } with Bits =
--                  Blocked | HandTuned << 1 | Locked << 2 | Priority << 3, Input = { Dir, Level }
--                  (Level -1 = none)
-- Summary, Created and Skipped are not shared: the importer rebuilds them.

local Deflate = require("deflate")
local Storage = require("storage")

local Share = {}

Share.Prefix = "TCBP1:"
local MaxString, MaxPayload = 256 * 1024, 1024 * 1024
local MaxCoord, MaxName = 400, 64

local Step = { [0] = { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }

local function MoveDir(DR, DC)
    for D = 0, 3 do
        if Step[D][1] == DR and Step[D][2] == DC then return D end
    end
end

---------------------------------------------------------------------------------------------------
-- base64url (RFC 4648 section 5, no padding)

local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local Index = {}
for i = 1, 64 do Index[Alphabet:byte(i)] = i - 1 end

local function B64Encode(Str)
    local Out = {}
    for i = 1, #Str, 3 do
        local A, B, C = Str:byte(i, i + 2)
        local V = (A << 16) | ((B or 0) << 8) | (C or 0)
        local Chars = C and 4 or (B and 3 or 2)
        for k = 1, Chars do
            local X = (V >> (18 - 6 * (k - 1))) & 63
            Out[#Out + 1] = Alphabet:sub(X + 1, X + 1)
        end
    end
    return table.concat(Out)
end

local function B64Decode(Str)
    if #Str % 4 == 1 then return nil, "share string is incomplete" end
    local Out = {}
    for i = 1, #Str, 4 do
        local V, Chars = 0, 0
        for j = i, math.min(i + 3, #Str) do
            local X = Index[Str:byte(j)]
            if not X then return nil, "share string has an invalid character at position " .. j end
            V, Chars = (V << 6) | X, Chars + 1
        end
        V = V << (6 * (4 - Chars))
        Out[#Out + 1] = string.char((V >> 16) & 255)
        if Chars > 2 then Out[#Out + 1] = string.char((V >> 8) & 255) end
        if Chars > 3 then Out[#Out + 1] = string.char(V & 255) end
    end
    return table.concat(Out)
end

---------------------------------------------------------------------------------------------------
-- Safe literal reader: tables of positional values, %q strings, numbers, true / false. Nothing else.

local MaxDepth, MaxElements, MaxStringLen = 6, 200000, 256
local Escapes = { n = "\n", r = "\r", t = "\t", ["\\"] = "\\", ['"'] = '"', ["\n"] = "\n" }

local function ReadLiteral(Text)
    local Pos, Elements = 1, 0

    local function Fail(Why) error({ Literal = "bad share data (" .. Why .. " at " .. Pos .. ")" }) end

    local function Value(Depth)
        local C = Text:sub(Pos, Pos)
        if C == "{" then
            if Depth >= MaxDepth then Fail("nesting too deep") end
            Pos = Pos + 1
            local T = {}
            while Text:sub(Pos, Pos) ~= "}" do
                Elements = Elements + 1
                if Elements > MaxElements then Fail("too many values") end
                T[#T + 1] = Value(Depth + 1)
                local Sep = Text:sub(Pos, Pos)
                if Sep == "," then Pos = Pos + 1
                elseif Sep ~= "}" then Fail("expected , or }") end
            end
            Pos = Pos + 1
            return T
        elseif C == '"' then
            Pos = Pos + 1
            local Parts, Len = {}, 0
            while true do
                local Ch = Text:sub(Pos, Pos)
                if Ch == "" then Fail("unterminated string") end
                Pos = Pos + 1
                if Ch == '"' then break end
                if Ch == "\\" then
                    local E = Text:sub(Pos, Pos)
                    local Digits = Text:match("^%d%d?%d?", Pos)
                    if Digits then
                        local Code = tonumber(Digits)
                        if Code > 255 then Fail("bad escape") end
                        Ch, Pos = string.char(Code), Pos + #Digits
                    elseif Escapes[E] then
                        Ch, Pos = Escapes[E], Pos + 1
                    else
                        Fail("bad escape")
                    end
                end
                Len = Len + 1
                if Len > MaxStringLen then Fail("string too long") end
                Parts[Len] = Ch
            end
            return table.concat(Parts)
        elseif Text:match("^true", Pos) then
            Pos = Pos + 4
            return true
        elseif Text:match("^false", Pos) then
            Pos = Pos + 5
            return false
        end
        local Num = Text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", Pos)
        local V = Num and tonumber(Num)
        if not V then Fail("unexpected character") end
        Pos = Pos + #Num
        return V
    end

    local Ok, Result = pcall(Value, 0)
    if not Ok then
        return nil, type(Result) == "table" and Result.Literal or "bad share data"
    end
    if Pos <= #Text then return nil, "bad share data (trailing characters)" end
    return Result
end

---------------------------------------------------------------------------------------------------
-- Blueprint -> payload

local function ShortClass(Path)
    local P, Obj = Path:match("^/Game/([%w_/]+)%.([%w_]+)$")
    if not P then error("class cannot be shared: " .. tostring(Path)) end
    if Obj == P:match("([%w_]+)$") .. "_C" then return P end
    return P .. "." .. Obj
end

local function FullClass(Short)
    if Short:find(".", 1, true) then return "/Game/" .. Short end
    return "/Game/" .. Short .. "." .. Short:match("([%w_]+)$") .. "_C"
end

local function SameCells(A, ADR, ADC, B, BDR, BDC)
    if #A ~= #B then return false end
    local DR, DC = BDR - ADR, BDC - ADC
    for i = 1, #A do
        if A[i][1] + DR ~= B[i][1] or A[i][2] + DC ~= B[i][2] then return false end
    end
    return true
end

local function BeltLetters(Path)
    local Letters = {}
    for i, Cell in ipairs(Path) do
        local Dir, Next = Cell[3], Path[i + 1]
        if not Dir then return nil end
        local Move = Dir
        if Next then
            Move = MoveDir(Next[1] - Cell[1], Next[2] - Cell[2])
            if not Move then return nil end
        end
        Letters[i] = string.char(97 + Dir * 4 + Move)
    end
    return Letters[1] and table.concat(Letters)
end

local function CleanName(Name)
    Name = Name:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    Name = Name:sub(1, MaxName)
    while #Name > 0 and not utf8.len(Name) do Name = Name:sub(1, -2) end
    return Name ~= "" and Name or "Imported blueprint"
end

local function Bit(B, Shift) return B and (1 << Shift) or 0 end

function Share.ToPayload(BP)
    local Classes, ClassIndex, First = {}, {}, {}
    local Modules = {}
    for i, M in ipairs(BP.Modules) do
        local Short = ShortClass(M.Class)
        if not ClassIndex[Short] then
            Classes[#Classes + 1] = Short
            ClassIndex[Short] = #Classes
        end
        local Key = M.Class .. "|" .. M.Turns .. "|" .. tostring(M.Mirrored == true)
        local F = First[Key]
        local Cells
        if F and SameCells(F.Cells, F.DR, F.DC, M.Cells, M.DR, M.DC) then
            Cells = 0
        else
            First[Key] = First[Key] or M
            Cells = {}
            for _, C in ipairs(M.Cells) do Cells[#Cells + 1] = C[1]; Cells[#Cells + 1] = C[2] end
        end
        local IO = 0
        if M.IO then
            IO = {}
            for j, E in ipairs(M.IO) do
                IO[j] = E and { E.Agency or "", Bit(E.Lock, 0) | Bit(E.Overflow, 1), E.Filter or {} } or 0
            end
        end
        Modules[i] = { ClassIndex[Short], M.DR, M.DC, M.Turns, M.Mirrored and 1 or 0, M.Recipe or "", Cells, IO }
    end

    local Belts = {}
    for i, Path in ipairs(BP.Belts) do
        local Letters = BeltLetters(Path)
        if Letters then
            Belts[i] = { Path[1][1], Path[1][2], Letters }
        else
            local Flat = {}
            for _, C in ipairs(Path) do
                Flat[#Flat + 1] = C[1]; Flat[#Flat + 1] = C[2]; Flat[#Flat + 1] = C[3] or -1
            end
            Belts[i] = Flat
        end
    end

    local Undergrounds = {}
    for i, U in ipairs(BP.Undergrounds or {}) do Undergrounds[i] = { U[1][1], U[1][2], U[2][1], U[2][2], U[3] } end

    local Links = {}
    for _, L in ipairs(BP.Links or {}) do Links[#Links + 1] = L[1]; Links[#Links + 1] = L[2] end

    local Distributors = {}
    for i, D in ipairs(BP.Distributors or {}) do
        local Outputs, Inputs = {}, {}
        for j, O in ipairs(D.Outputs or {}) do
            local Bits = Bit(O.Blocked, 0) | Bit(O.HandTuned, 1) | Bit(O.Locked, 2) | Bit(O.Priority, 3)
            Outputs[j] = { O.Dir, O.Level or -1, Bits, O.Types or {} }
        end
        for j, In in ipairs(D.Inputs or {}) do Inputs[j] = { In.Dir, In.Level or -1 } end
        Distributors[i] = { D.DR, D.DC, Outputs, Inputs }
    end

    return { CleanName(BP.Name or ""), BP.Layer, Classes, Modules, Belts, Undergrounds, Links, Distributors }
end

---------------------------------------------------------------------------------------------------
-- Payload -> blueprint, with validation

local function Check(Cond, Why)
    if not Cond then error({ Share = Why }) end
end

local function List(V, Max, What)
    Check(type(V) == "table", What .. " must be a list")
    Check(#V <= Max, "too many " .. What)
    return V
end

local function Int(V, Lo, Hi, What)
    Check(math.type(V) == "integer" and V >= Lo and V <= Hi, What .. " out of range")
    return V
end

-- Cell offset or module location: integer or half-integer within the map.
local function Coord(V, What)
    Check(type(V) == "number" and math.abs(V) <= MaxCoord and (V * 2) % 1 == 0, What .. " out of range")
    return math.type(V) == "float" and V % 1 == 0 and math.tointeger(V) or V
end

local function Str(V, Pattern, What)
    Check(type(V) == "string" and V:match(Pattern), "bad " .. What)
    return V
end

local function Ints(V, Max, Lo, Hi, What)
    local T = {}
    for i, X in ipairs(List(V, Max, What)) do T[i] = Int(X, Lo, Hi, What) end
    return T
end

function Share.FromPayload(P)
    List(P, 8, "payload fields")
    local BP = {}
    BP.Name = CleanName(Str(P[1], "^.*$", "name"))
    BP.Layer = Int(P[2], 0, 2, "layer")
    Check(BP.Layer ~= 1, "layer out of range")

    local Classes = {}
    for i, C in ipairs(List(P[3], 64, "classes")) do
        Str(C, "^[%w_/%.]+$", "class")
        local Path = C:match("^(.-)%.[%w_]+$") or C
        Check(Path:match("^[%w_]+[%w_/]*[%w_]$") and not Path:find("//", 1, true), "bad class")
        Classes[i] = FullClass(C)
    end

    local First = {}
    BP.Modules = {}
    for i, E in ipairs(List(P[4], 2000, "modules")) do
        List(E, 8, "module fields")
        local M = {
            Class = Classes[Int(E[1], 1, #Classes, "module class")],
            DR = Coord(E[2], "module row"), DC = Coord(E[3], "module column"),
            Turns = Int(E[4], 0, 3, "module turns"), Mirrored = Int(E[5], 0, 1, "module mirror") == 1,
            Recipe = Str(E[6], "^[%w_]*$", "recipe"),
        }
        local Key = M.Class .. "|" .. M.Turns .. "|" .. tostring(M.Mirrored)
        M.Cells = {}
        if E[7] == 0 then
            local F = First[Key]
            Check(F, "module footprint missing")
            local DR, DC = M.DR - F.DR, M.DC - F.DC
            for j, C in ipairs(F.Cells) do M.Cells[j] = { Coord(C[1] + DR, "module cell"), Coord(C[2] + DC, "module cell") } end
        else
            local Flat = List(E[7], 128, "module cells")
            Check(#Flat % 2 == 0, "bad module cells")
            for j = 1, #Flat, 2 do M.Cells[#M.Cells + 1] = { Int(Flat[j], -MaxCoord, MaxCoord, "module cell"), Int(Flat[j + 1], -MaxCoord, MaxCoord, "module cell") } end
            First[Key] = First[Key] or M
        end
        if E[8] ~= 0 then
            M.IO = {}
            for j, IO in ipairs(List(E[8], 32, "IO cells")) do
                if IO == 0 then
                    M.IO[j] = false
                else
                    List(IO, 3, "IO fields")
                    local Bits = Int(IO[2], 0, 3, "IO flags")
                    M.IO[j] = {
                        Agency = Str(IO[1], "^[%w_]*$", "IO agency"),
                        Lock = Bits & 1 ~= 0, Overflow = Bits & 2 ~= 0,
                        Filter = Ints(IO[3], 64, 0, 255, "IO filter"),
                    }
                end
            end
        end
        BP.Modules[i] = M
    end

    BP.Belts = {}
    local Cells = 0
    for i, E in ipairs(List(P[5], 5000, "belt paths")) do
        local Path = {}
        if type(E[3]) == "string" then
            List(E, 3, "belt fields")
            local R, C = Int(E[1], -MaxCoord, MaxCoord, "belt cell"), Int(E[2], -MaxCoord, MaxCoord, "belt cell")
            local Letters = Str(E[3], "^[a-p]+$", "belt path")
            for j = 1, #Letters do
                local X = Letters:byte(j) - 97
                local Dir, Move = X // 4, X % 4
                Check(math.abs(R) <= MaxCoord and math.abs(C) <= MaxCoord, "belt cell out of range")
                Path[j] = { R, C, Dir }
                R, C = R + Step[Move][1], C + Step[Move][2]
            end
        else
            List(E, 3 * 1000, "belt cells")
            Check(#E % 3 == 0 and #E > 0, "bad belt path")
            for j = 1, #E, 3 do
                local Dir = Int(E[j + 2], -1, 3, "belt direction")
                Path[#Path + 1] = { Int(E[j], -MaxCoord, MaxCoord, "belt cell"), Int(E[j + 1], -MaxCoord, MaxCoord, "belt cell"), Dir >= 0 and Dir or nil }
            end
        end
        Cells = Cells + #Path
        Check(Cells <= 50000, "too many belt cells")
        BP.Belts[i] = Path
    end

    BP.Undergrounds = {}
    for i, U in ipairs(List(P[6], 2000, "undergrounds")) do
        local V = Ints(U, 5, -MaxCoord, MaxCoord, "underground")
        Check(#V == 5 and V[5] >= 0 and V[5] <= 3, "bad underground")
        BP.Undergrounds[i] = { { V[1], V[2] }, { V[3], V[4] }, V[5] }
    end

    BP.Links = {}
    local L = Ints(P[7], 20000, 1, #BP.Modules, "wire")
    Check(#L % 2 == 0, "bad wires")
    for j = 1, #L, 2 do
        Check(L[j] ~= L[j + 1], "bad wire")
        BP.Links[#BP.Links + 1] = { L[j], L[j + 1] }
    end

    BP.Distributors = {}
    for i, D in ipairs(List(P[8], 2000, "distributors")) do
        List(D, 4, "distributor fields")
        local Out = { DR = Int(D[1], -MaxCoord, MaxCoord, "distributor"), DC = Int(D[2], -MaxCoord, MaxCoord, "distributor"), Outputs = {}, Inputs = {} }
        for j, O in ipairs(List(D[3], 4, "distributor outputs")) do
            List(O, 4, "distributor output fields")
            local Level, Bits = Int(O[2], -1, 100, "output level"), Int(O[3], 0, 15, "output flags")
            Out.Outputs[j] = {
                Dir = Int(O[1], 0, 3, "output direction"), Level = Level >= 0 and Level or nil,
                Blocked = Bits & 1 ~= 0, HandTuned = Bits & 2 ~= 0, Locked = Bits & 4 ~= 0, Priority = Bits & 8 ~= 0,
                Types = Ints(O[4], 64, 0, 255, "output resources"),
            }
        end
        for j, In in ipairs(List(D[4], 4, "distributor inputs")) do
            local V = Ints(In, 2, -1, 100, "distributor input")
            Check(#V == 2 and V[1] >= 0 and V[1] <= 3, "bad distributor input")
            Out.Inputs[j] = { Dir = V[1], Level = V[2] >= 0 and V[2] or nil }
        end
        BP.Distributors[i] = Out
    end
    return BP
end

---------------------------------------------------------------------------------------------------

-- Payload literal text -> share string.
function Share.Pack(Text)
    return Share.Prefix .. B64Encode(Deflate.Compress(Text))
end

function Share.Encode(BP)
    return Share.Pack(Storage.Serialize(Share.ToPayload(BP), nil, true))
end

-- Str = pasted text (whitespace ignored). Returns blueprint (without Summary / Created) or nil, error.
function Share.Decode(Str)
    if type(Str) ~= "string" then return nil, "no share string" end
    Str = Str:gsub("%s+", "")
    if #Str > MaxString then return nil, "share string too long" end
    local Version = Str:match("^TCBP(%d+):")
    if not Version then return nil, "not a blueprint share string (it must start with " .. Share.Prefix .. ")" end
    if Version ~= "1" then return nil, "share string made by a newer Blueprints version (TCBP" .. Version .. ")" end
    local Bytes, Err = B64Decode(Str:sub(#Share.Prefix + 1))
    if not Bytes then return nil, Err end
    local Ok, Text = pcall(Deflate.Inflate, Bytes, MaxPayload)
    if not Ok then return nil, "share string is damaged (" .. tostring(Text):gsub("^.-:%d+: ", "") .. ")" end
    local Payload, PErr = ReadLiteral(Text)
    if not Payload then return nil, PErr end
    local VOk, BP = pcall(Share.FromPayload, Payload)
    if not VOk then
        if type(BP) == "table" and BP.Share then return nil, "invalid blueprint: " .. BP.Share end
        return nil, "invalid blueprint: " .. tostring(BP)
    end
    return BP
end

-- Exposed for selftest.
Share.ReadLiteral = ReadLiteral

return Share
