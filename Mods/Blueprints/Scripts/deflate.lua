-- Raw DEFLATE (RFC 1951) for share strings: LZ77 + fixed Huffman codes on compress, stored and
-- fixed-Huffman blocks on inflate (dynamic blocks are rejected: share strings never use them).
-- Inflate input is untrusted: every malformed stream ends in error(), never a hang or overflow.

local Deflate = {}

local LenBase = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LenExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DistBase = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DistExtra = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }

local Window, MinMatch, MaxMatch, MaxChain = 32768, 3, 258, 128

local function Reverse(Code, Len)
    local R = 0
    for _ = 1, Len do
        R = (R << 1) | (Code & 1)
        Code = Code >> 1
    end
    return R
end

-- Fixed literal / length code of symbol S -> code bits already reversed for LSB-first output, length.
local FixedLit = {}
for S = 0, 287 do
    local Code, Len
    if S < 144 then Code, Len = 0x30 + S, 8
    elseif S < 256 then Code, Len = 0x190 + S - 144, 9
    elseif S < 280 then Code, Len = S - 256, 7
    else Code, Len = 0xC0 + S - 280, 8 end
    FixedLit[S] = { Reverse(Code, Len), Len }
end

local function Writer()
    local Out, Acc, N = {}, 0, 0
    local W = {}
    function W.Bits(V, Len)
        Acc = Acc | (V << N)
        N = N + Len
        while N >= 8 do
            Out[#Out + 1] = string.char(Acc & 0xFF)
            Acc, N = Acc >> 8, N - 8
        end
    end
    function W.Finish()
        if N > 0 then Out[#Out + 1] = string.char(Acc & 0xFF) end
        return table.concat(Out)
    end
    return W
end

local function Slot(Base, Value)
    local i = #Base
    while Base[i] > Value do i = i - 1 end
    return i
end

function Deflate.Compress(Str)
    local W = Writer()
    W.Bits(1, 1) -- BFINAL
    W.Bits(1, 2) -- BTYPE 01 = fixed Huffman
    local function Lit(S) W.Bits(FixedLit[S][1], FixedLit[S][2]) end

    local N = #Str
    local Head, Prev = {}, {}
    local function Insert(i)
        if i + 2 > N then return end
        local H = Str:sub(i, i + 2)
        Prev[i] = Head[H]
        Head[H] = i
    end

    local i = 1
    while i <= N do
        local BestLen, BestDist = 0, 0
        if i + 2 <= N then
            local Cand, Chain = Head[Str:sub(i, i + 2)], 0
            local Limit = math.min(MaxMatch, N - i + 1)
            while Cand and i - Cand <= Window and Chain < MaxChain do
                local L = 3
                while L < Limit and Str:byte(Cand + L) == Str:byte(i + L) do L = L + 1 end
                if L > BestLen then BestLen, BestDist = L, i - Cand end
                if L == Limit then break end
                Cand, Chain = Prev[Cand], Chain + 1
            end
        end
        if BestLen >= MinMatch then
            local LS = Slot(LenBase, BestLen)
            Lit(256 + LS)
            if LenExtra[LS] > 0 then W.Bits(BestLen - LenBase[LS], LenExtra[LS]) end
            local DS = Slot(DistBase, BestDist)
            W.Bits(Reverse(DS - 1, 5), 5)
            if DistExtra[DS] > 0 then W.Bits(BestDist - DistBase[DS], DistExtra[DS]) end
            for j = i, i + BestLen - 1 do Insert(j) end
            i = i + BestLen
        else
            Lit(Str:byte(i))
            Insert(i)
            i = i + 1
        end
    end
    Lit(256)
    return W.Finish()
end

-- Canonical Huffman table from code lengths (index 0-based symbols), decoded bit by bit (puff style).
local function Table(Lengths, Count)
    local H = { Count = {}, Symbol = {} }
    for L = 0, 15 do H.Count[L] = 0 end
    for S = 0, Count - 1 do H.Count[Lengths[S]] = H.Count[Lengths[S]] + 1 end
    local Offs = { [1] = 0 }
    for L = 1, 14 do Offs[L + 1] = Offs[L] + H.Count[L] end
    for S = 0, Count - 1 do
        local L = Lengths[S]
        if L ~= 0 then
            H.Symbol[Offs[L]] = S
            Offs[L] = Offs[L] + 1
        end
    end
    return H
end

local FixedLitTable, FixedDistTable
do
    local L = {}
    for S = 0, 287 do L[S] = FixedLit[S][2] end
    FixedLitTable = Table(L, 288)
    local D = {}
    for S = 0, 29 do D[S] = 5 end
    FixedDistTable = Table(D, 30)
end

-- Str = raw DEFLATE stream, MaxOut = output size cap. Returns the inflated string; errors on bad input.
function Deflate.Inflate(Str, MaxOut)
    local Pos, Acc, N = 1, 0, 0
    local Out, Count = {}, 0

    local function Bits(Len)
        while N < Len do
            local B = Str:byte(Pos)
            if not B then error("data ends early") end
            Acc, N, Pos = Acc | (B << N), N + 8, Pos + 1
        end
        local V = Acc & ((1 << Len) - 1)
        Acc, N = Acc >> Len, N - Len
        return V
    end

    local function Decode(H)
        local Code, First, Index = 0, 0, 0
        for L = 1, 15 do
            Code = Code | Bits(1)
            local C = H.Count[L]
            if Code - C < First then return H.Symbol[Index + Code - First] end
            Index, First = Index + C, (First + C) << 1
            Code = Code << 1
        end
        error("bad Huffman code")
    end

    local function Put(B)
        Count = Count + 1
        if Count > MaxOut then error("share string expands too much") end
        Out[Count] = B
    end

    repeat
        local Final = Bits(1)
        local Type = Bits(2)
        if Type == 0 then
            Acc, N = 0, 0 -- skip to the byte boundary
            local A, B, C, D = Str:byte(Pos, Pos + 3)
            if not D then error("data ends early") end
            local Len, NLen = A | (B << 8), C | (D << 8)
            if Len ~ NLen ~= 0xFFFF then error("bad stored block") end
            Pos = Pos + 4
            if Pos + Len - 1 > #Str then error("data ends early") end
            for j = Pos, Pos + Len - 1 do Put(Str:byte(j)) end
            Pos = Pos + Len
        elseif Type == 1 then
            while true do
                local S = Decode(FixedLitTable)
                if S < 256 then
                    Put(S)
                elseif S == 256 then
                    break
                else
                    local LS = S - 256
                    if LS > 29 or LS < 1 then error("bad length code") end
                    local Len = LenBase[LS] + Bits(LenExtra[LS])
                    local DS = Decode(FixedDistTable) + 1
                    local Dist = DistBase[DS] + Bits(DistExtra[DS])
                    if Dist > Count then error("bad distance") end
                    for _ = 1, Len do Put(Out[Count - Dist + 1]) end
                end
            end
        else
            error("unsupported block type " .. Type)
        end
    until Final == 1

    local Parts = {}
    for j = 1, Count, 4096 do Parts[#Parts + 1] = string.char(table.unpack(Out, j, math.min(j + 4095, Count))) end
    return table.concat(Parts)
end

return Deflate
