--[[
    Peex HUB | FireflyTopia
    Fitur:
      1) Noclip lewat sistem GHOST bawaan game (atribut "StaffGhost")
      2) Auto Farm kotak 5x5 di sekitar posisimu (kotak tengah = kamu)
         - tap kotak: merah = dilewati, hijau = dikerjakan
         - tile dideteksi otomatis: kosong -> place, isinya item pilihanmu -> break
         - delay break bisa sampai 0.03 detik
         - pilih item dari inventory (ada tombol Refresh Inventory)

    Cara kerja (dibaca dari script game):
      Break : Events.PunchTile:FireServer(x, y, layer, worldEpoch, true, ulangi, false)
      Place : Events.PlaceTile:FireServer(x, y, layer, itemId, worldEpoch)
      Tile  : TileIndex.At(layer, x, y)  -> Instance dengan atribut ItemId
      Posisi: TileMath.WorldToGrid(HumanoidRootPart.Position)  (y naik = ke atas)
      Ghost : Player:SetAttribute("StaffGhost", true); naik = lompat, turun = tombol Down
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Eksekusi ulang = bersihkan versi lama dulu
local genv = (getgenv and getgenv()) or _G
if type(genv.FireflyPeexCleanup) == "function" then
    pcall(genv.FireflyPeexCleanup)
end

----------------------------------------------------------------------
-- MODUL GAME (ReplicatedStorage.Shared) + REMOTE
----------------------------------------------------------------------
local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
local Events = ReplicatedStorage:WaitForChild("Events", 15)

local function Req(name)
    if not Shared then
        return nil
    end
    local mod = Shared:WaitForChild(name, 10)
    if not mod then
        return nil
    end
    local ok, result = pcall(require, mod)
    if ok then
        return result
    end
    return nil
end

local TileConfig = Req("TileConfig")
local TileMath = Req("TileMath")
local TileIndex = Req("TileIndex")
local ItemAtlas = Req("ItemAtlas")
local InvConfig = Req("InventoryConfig")
local Rings = Req("Rings")
local PunchRange = Req("PunchRange")

local PunchTile = Events and Events:WaitForChild("PunchTile", 10)
local PlaceTile = Events and Events:WaitForChild("PlaceTile", 10)

local FARM_READY = TileConfig ~= nil and TileMath ~= nil and TileIndex ~= nil
    and ItemAtlas ~= nil and InvConfig ~= nil and PunchTile ~= nil and PlaceTile ~= nil

local LAYER_FG = TileConfig and TileConfig.Layers and TileConfig.Layers.FOREGROUND

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG_FILE = "Fireflytopia_Peex.json"
local Config = {
    itemId = 0,
    breakDelay = 0.03,
    placeDelay = 0.05,
    grid = { ["1,0"] = true },
}

pcall(function()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        for key, value in pairs(data) do
            if Config[key] ~= nil and type(value) == type(Config[key]) then
                Config[key] = value
            end
        end
    end
end)

local function SaveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

----------------------------------------------------------------------
-- UTIL TILE / POSISI
----------------------------------------------------------------------
local function GetChar()
    return Player.Character
end

local function GetHRP()
    local char = GetChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetEpoch()
    local char = GetChar()
    return char and char:GetAttribute("WorldEpoch")
end

-- Kotak grid tempat player berdiri (x ke kanan, y ke ATAS)
local function PlayerCell()
    local hrp = GetHRP()
    if not hrp or not TileMath then
        return nil
    end
    local ok, gx, gy = pcall(TileMath.WorldToGrid, hrp.Position)
    if ok and type(gx) == "number" and type(gy) == "number" then
        return gx, gy
    end
    return nil
end

local function InWorld()
    if not TileIndex then
        return false
    end
    local ok, current = pcall(TileIndex.Current)
    return ok and current ~= nil
end

local function TileAt(layer, x, y)
    local ok, tile = pcall(TileIndex.At, layer, x, y)
    if ok then
        return tile
    end
    return nil
end

local function TileItem(tile)
    if not tile then
        return nil
    end
    local id = tile:GetAttribute("ItemId")
    if typeof(id) == "number" then
        return id
    end
    return nil
end

local function ItemName(id)
    local def = ItemAtlas and ItemAtlas[id]
    if type(def) == "table" and type(def.name) == "string" then
        return def.name
    end
    return "?"
end

local function CountOf(id)
    local ok, count = pcall(InvConfig.Count, Player, id)
    if ok and type(count) == "number" then
        return count
    end
    return 0
end

local function LayerOf(id)
    local ok, layer = pcall(TileConfig.GetPlacementLayer, id)
    if ok then
        return layer
    end
    return nil
end

-- Jangkauan: sama persis dengan rumus di script game
local function ReachBase()
    local char = GetChar()
    if Rings and char then
        local ok, value = pcall(Rings.Reach, char)
        if ok and type(value) == "number" then
            return value
        end
    end
    return 0
end

local function InPlaceRange(x, y)
    local hrp = GetHRP()
    if not (hrp and TileMath and TileMath.IsInPlacementRange) then
        return true
    end
    local ok, result = pcall(TileMath.IsInPlacementRange, hrp.Position, x, y, ReachBase())
    if ok then
        return result == true
    end
    return true
end

local function InPunchRange(x, y)
    local hrp = GetHRP()
    if not (hrp and TileMath and TileMath.IsInPunchRange) then
        return true
    end
    local reach = ReachBase()
    local char = GetChar()
    if PunchRange and char then
        local okB, bonus = pcall(PunchRange.Bonus, char)
        if okB and type(bonus) == "number" then
            reach += bonus
        end
    end
    local ok, result = pcall(TileMath.IsInPunchRange, hrp.Position, x, y, reach)
    if ok then
        return result == true
    end
    return true
end

----------------------------------------------------------------------
-- NOCLIP (sistem GHOST bawaan game)
-- Game membaca atribut "StaffGhost" di Player: kalau true, kontrol terbang
-- (naik = lompat, turun = tombol Down) aktif dan prediksi gerak mengabaikan tile.
-- Server tetap pemegang keputusan akhir; kalau server menolak, posisi
-- akan dikoreksi balik.
----------------------------------------------------------------------
local Noclip = { on = false, original = nil, conn = nil }

local function StopNoclip()
    if not Noclip.on then
        return false
    end
    Noclip.on = false
    if Noclip.conn then
        Noclip.conn:Disconnect()
        Noclip.conn = nil
    end
    Player:SetAttribute("StaffGhost", Noclip.original)
    return true
end

local function StartNoclip()
    if Noclip.on then
        return true
    end
    Noclip.original = Player:GetAttribute("StaffGhost")
    Noclip.on = true
    Player:SetAttribute("StaffGhost", true)
    Noclip.conn = RunService.Heartbeat:Connect(function()
        if Player:GetAttribute("StaffGhost") ~= true then
            Player:SetAttribute("StaffGhost", true) -- game bisa mereset atributnya
        end
    end)
    return true
end

----------------------------------------------------------------------
-- INVENTORY: kumpulkan item yang bisa di-place
-- Kita tanya langsung ke InventoryConfig.Count(player, id) untuk setiap id
-- di ItemAtlas, jadi tidak tergantung bentuk penyimpanan inventory.
----------------------------------------------------------------------
local Inventory = {}

local function ScanInventory()
    local list = {}
    if not FARM_READY then
        return list
    end
    local ids = {}
    for id, def in pairs(ItemAtlas) do
        if type(id) == "number" and type(def) == "table" then
            table.insert(ids, id)
        end
    end
    if #ids == 0 then
        -- ItemAtlas tidak bisa di-iterasi: coba index langsung
        for id = 1, 20000 do
            if type(ItemAtlas[id]) == "table" then
                table.insert(ids, id)
            end
        end
    end
    for _, id in ipairs(ids) do
        local def = ItemAtlas[id]
        local count = CountOf(id)
        if count > 0 and def.seed == nil then
            local layer = LayerOf(id)
            local okC, consumable = pcall(TileConfig.IsConsumable, id)
            if layer ~= nil and not (okC and consumable) then
                table.insert(list, {
                    id = id,
                    name = type(def.name) == "string" and def.name or ("#" .. id),
                    count = count,
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    Inventory = list
    return list
end

----------------------------------------------------------------------
-- AUTO FARM
-- Per siklus: (1) place di kotak hijau yang kosong, (2) break kotak hijau
-- yang berisi item pilihan. Kotak yang berisi item lain dibiarkan.
-- Break meniru game: pukulan beruntun ke tile yang sama = flag "ulangi".
----------------------------------------------------------------------
local Farm = {
    on = false, token = 0, status = "Mati",
    placed = 0, broken = 0, failed = 0, cycles = 0, outOfRange = 0,
}
local lastPunchKey = nil

local function GridCells(gx, gy)
    local cells = {}
    for key, on in pairs(Config.grid) do
        local dx, dy = tostring(key):match("^(-?%d+),(-?%d+)$")
        dx, dy = tonumber(dx), tonumber(dy)
        if on and dx and dy and math.abs(dx) <= 2 and math.abs(dy) <= 2 and not (dx == 0 and dy == 0) then
            table.insert(cells, { x = gx + dx, y = gy + dy })
        end
    end
    -- atas ke bawah, kiri ke kanan (y naik = ke atas)
    table.sort(cells, function(a, b)
        if a.y ~= b.y then
            return a.y > b.y
        end
        return a.x < b.x
    end)
    return cells
end

local function PlaceCell(cell, itemId, layer)
    local epoch = GetEpoch()
    if not epoch then
        return false
    end
    pcall(PlaceTile.FireServer, PlaceTile, cell.x, cell.y, layer, itemId, epoch)
    local started = os.clock()
    while os.clock() - started < 0.6 do
        if TileAt(layer, cell.x, cell.y) ~= nil then
            return true
        end
        task.wait(0.03)
    end
    return false
end

local function BreakCell(cell, itemId, layer, token)
    local started = os.clock()
    while Farm.token == token do
        local tile = TileAt(layer, cell.x, cell.y)
        if tile == nil then
            return true -- sudah hancur
        end
        if TileItem(tile) ~= itemId then
            return false -- bukan item kita
        end
        if os.clock() - started > 10 then
            return false
        end
        local epoch = GetEpoch()
        if not epoch then
            return false
        end
        local key = epoch .. ":" .. cell.x .. ":" .. cell.y
        local again = (key == lastPunchKey)
        lastPunchKey = key
        pcall(PunchTile.FireServer, PunchTile, cell.x, cell.y, layer, epoch, true, again, false)
        task.wait(math.max(0.03, Config.breakDelay))
    end
    return false
end

local function FarmLoop(token)
    local itemId = Config.itemId
    local layer = LayerOf(itemId)
    local startEpoch = GetEpoch()
    while Farm.token == token do
        if not InWorld() or not GetHRP() then
            Farm.status = "Menunggu world / karakter..."
            task.wait(0.5)
            continue
        end
        if GetEpoch() ~= startEpoch then
            Farm.status = "World berubah, farm berhenti"
            return
        end
        local gx, gy = PlayerCell()
        if not gx then
            Farm.status = "Posisi tidak terdeteksi"
            task.wait(0.5)
            continue
        end
        local cells = GridCells(gx, gy)
        if #cells == 0 then
            Farm.status = "Tidak ada kotak hijau"
            return
        end

        -- 1) PLACE
        Farm.status = "Place " .. ItemName(itemId)
        local have = CountOf(itemId)
        for _, cell in ipairs(cells) do
            if Farm.token ~= token then
                return
            end
            if have > 0 and TileAt(layer, cell.x, cell.y) == nil then
                if InPlaceRange(cell.x, cell.y) then
                    if PlaceCell(cell, itemId, layer) then
                        Farm.placed += 1
                        have -= 1
                    else
                        Farm.failed += 1
                    end
                    task.wait(math.max(0.03, Config.placeDelay))
                else
                    Farm.outOfRange += 1
                end
            end
        end

        -- 2) BREAK
        Farm.status = "Break " .. ItemName(itemId)
        local didSomething = false
        for _, cell in ipairs(cells) do
            if Farm.token ~= token then
                return
            end
            local tile = TileAt(layer, cell.x, cell.y)
            if tile ~= nil and TileItem(tile) == itemId then
                if InPunchRange(cell.x, cell.y) then
                    didSomething = true
                    if BreakCell(cell, itemId, layer, token) then
                        Farm.broken += 1
                    else
                        Farm.failed += 1
                    end
                else
                    Farm.outOfRange += 1
                end
            end
        end

        Farm.cycles += 1
        if not didSomething and CountOf(itemId) <= 0 then
            Farm.status = "Item habis"
            return
        end
        task.wait(0.05)
    end
end

local function StopFarm()
    if not Farm.on then
        return false
    end
    Farm.token += 1
    Farm.on = false
    Farm.status = "Dihentikan"
    return true
end

local Notify -- diisi bagian GUI

local function StartFarm()
    if Farm.on then
        return true
    end
    if not FARM_READY then
        Notify("Modul game tidak lengkap, Auto Farm tidak bisa jalan.")
        return false
    end
    local itemId = Config.itemId
    if type(itemId) ~= "number" or itemId <= 0 or LayerOf(itemId) == nil then
        Notify("Pilih item dulu (tekan Refresh Inventory).")
        return false
    end
    if not InWorld() or not GetEpoch() then
        Notify("Masuk ke world dulu.")
        return false
    end
    local green = 0
    for _, on in pairs(Config.grid) do
        if on then
            green += 1
        end
    end
    if green < 1 then
        Notify("Tap minimal 1 kotak sampai hijau.")
        return false
    end
    Farm.token += 1
    local token = Farm.token
    Farm.on = true
    Farm.status = "Mulai"
    Farm.placed, Farm.broken, Farm.failed, Farm.cycles, Farm.outOfRange = 0, 0, 0, 0, 0
    lastPunchKey = nil
    task.spawn(function()
        local ok, err = pcall(FarmLoop, token)
        if not ok then
            warn(err)
            Farm.status = "Error: " .. tostring(err)
        end
        if Farm.token == token then
            Farm.on = false
        end
    end)
    return true
end

----------------------------------------------------------------------
-- GUI (tema cartoon)
----------------------------------------------------------------------
local C = {
    ink = Color3.fromRGB(58, 36, 72),
    window = Color3.fromRGB(255, 205, 96),
    panel = Color3.fromRGB(255, 246, 223),
    card = Color3.fromRGB(255, 255, 255),
    cardHi = Color3.fromRGB(255, 229, 160),
    accent = Color3.fromRGB(255, 96, 144),
    accent2 = Color3.fromRGB(38, 150, 236),
    mute = Color3.fromRGB(128, 100, 148),
    ok = Color3.fromRGB(84, 212, 116),
    bad = Color3.fromRGB(255, 84, 84),
    white = Color3.fromRGB(255, 255, 255),
    off = Color3.fromRGB(210, 198, 224),
    font = Enum.Font.FredokaOne,
}

local function New(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function Corner(obj, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, math.floor(radius * 1.4 + 0.5)) }, obj)
end

local function Stroke(obj, color, thickness)
    return New("UIStroke", {
        Color = color or C.ink,
        Thickness = thickness or 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function Tween(obj, duration, props)
    TweenService:Create(obj, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), props):Play()
end

local function Label(parent, props)
    local p = {
        BackgroundTransparency = 1,
        TextColor3 = C.ink,
        Font = C.font,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }
    for key, value in pairs(props) do
        p[key] = value
    end
    return New("TextLabel", p, parent)
end

local gui = New("ScreenGui", {
    Name = "FireflyPeexHub",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
}, nil)
do
    local okParent = pcall(function()
        gui.Parent = (gethui and gethui()) or PlayerGui
    end)
    if not okParent or not gui.Parent then
        gui.Parent = PlayerGui
    end
end

-- Toast ------------------------------------------------------------
local toastHolder = New("Frame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(0, 240, 1, -70),
    Position = UDim2.new(1, -252, 0, 58),
    ZIndex = 100,
}, gui)
New("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, toastHolder)
local toastCounter = 0

Notify = function(message)
    toastCounter += 1
    local toast = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = toastCounter,
        ZIndex = 100,
    }, toastHolder)
    Corner(toast, 10)
    Stroke(toast, C.ink, 2)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    }, toast)
    Label(toast, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(message),
        TextSize = 12,
        ZIndex = 101,
    })
    task.delay(3.5, function()
        if toast.Parent then
            toast:Destroy()
        end
    end)
end

-- Komponen -----------------------------------------------------------
local orders = setmetatable({}, { __mode = "k" })
local function NextOrder(parent)
    local n = (orders[parent] or 0) + 1
    orders[parent] = n
    return n
end

local refreshers = {}
local conns = {} -- koneksi global yang harus diputus saat cleanup

local function AddCard(page, height)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(page),
    }, page)
    Corner(card, 10)
    Stroke(card, C.ink, 2)
    return card
end

local function AddSection(page, text)
    local pill = Label(page, {
        Size = UDim2.new(1, 0, 0, 26),
        Text = string.upper(text),
        TextColor3 = C.white,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        BackgroundTransparency = 0,
        BackgroundColor3 = C.accent2,
        TextStrokeColor3 = C.ink,
        TextStrokeTransparency = 0.35,
        LayoutOrder = NextOrder(page),
    })
    Corner(pill, 9)
    Stroke(pill, C.ink, 2)
    return pill
end

local function AddNote(page, text)
    return Label(page, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = text,
        TextColor3 = C.mute,
        TextSize = 12,
        LayoutOrder = NextOrder(page),
    })
end

local function MakeButton(parent, text, style, props)
    local base, hover, colored
    if style == "primary" then
        base, hover, colored = C.accent, Color3.fromRGB(255, 132, 168), true
    elseif style == "danger" then
        base, hover, colored = C.bad, Color3.fromRGB(255, 124, 124), true
    elseif style == "ok" then
        base, hover, colored = C.ok, Color3.fromRGB(128, 230, 152), true
    else
        base, hover, colored = C.cardHi, Color3.fromRGB(255, 240, 198), false
    end
    local p = {
        Size = UDim2.new(1, 0, 0, 36),
        Text = text,
        TextColor3 = colored and C.white or C.ink,
        TextStrokeColor3 = C.ink,
        TextStrokeTransparency = colored and 0.35 or 1,
        Font = C.font,
        TextSize = 13,
        BorderSizePixel = 0,
        BackgroundColor3 = base,
        AutoButtonColor = false,
    }
    for key, value in pairs(props or {}) do
        p[key] = value
    end
    local button = New("TextButton", p, parent)
    Corner(button, 8)
    Stroke(button, C.ink, 2)
    local scale = New("UIScale", { Scale = 1 }, button)
    button.MouseEnter:Connect(function()
        Tween(button, 0.12, { BackgroundColor3 = hover })
    end)
    button.MouseLeave:Connect(function()
        Tween(button, 0.12, { BackgroundColor3 = base })
        Tween(scale, 0.12, { Scale = 1 })
    end)
    button.MouseButton1Down:Connect(function()
        Tween(scale, 0.08, { Scale = 0.93 })
    end)
    button.MouseButton1Up:Connect(function()
        Tween(scale, 0.18, { Scale = 1 })
    end)
    return button
end

local function AddSwitchCard(page, title, subtitle, getState, onToggle)
    local card = AddCard(page, 64)
    Label(card, {
        Text = title,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -84, 0, 18),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 11,
        Position = UDim2.fromOffset(12, 28),
        Size = UDim2.new(1, -84, 0, 32),
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local track = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(52, 28),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, card)
    Corner(track, 14)
    Stroke(track, C.ink, 2)
    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = C.white,
        BorderSizePixel = 0,
    }, track)
    Corner(knob, 10)
    Stroke(knob, C.ink, 2)
    local hit = New("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, card)
    local function Refresh()
        local on = getState()
        Tween(track, 0.18, { BackgroundColor3 = on and C.ok or C.off })
        Tween(knob, 0.18, { Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
    end
    hit.MouseButton1Click:Connect(function()
        onToggle(not getState())
        Refresh()
    end)
    table.insert(refreshers, Refresh)
    Refresh()
end

local function AddInputCard(page, title, subtitle, value, onCommit)
    local card = AddCard(page, 62)
    Label(card, {
        Text = title,
        TextSize = 12,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -130, 0, 16),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 10,
        Position = UDim2.fromOffset(12, 26),
        Size = UDim2.new(1, -130, 0, 32),
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local box = New("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(96, 34),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = tostring(value),
        TextColor3 = C.ink,
        Font = C.font,
        TextSize = 14,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, card)
    Corner(box, 8)
    local boxStroke = Stroke(box, C.ink, 2)
    box.Focused:Connect(function()
        boxStroke.Color = C.accent
    end)
    box.FocusLost:Connect(function()
        boxStroke.Color = C.ink
        onCommit(box.Text, box)
    end)
    return box
end

local function AutoCard(page)
    local card = AddCard(page, 40)
    card.AutomaticSize = Enum.AutomaticSize.Y
    New("UIPadding", { PaddingBottom = UDim.new(0, 10) }, card)
    return card
end

local function StatusLabel(card)
    return Label(card, {
        Position = UDim2.fromOffset(12, 9),
        Size = UDim2.new(1, -24, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = "...",
        TextSize = 12,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
end

-- Jendela -----------------------------------------------------------
local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
local width = math.clamp(viewport.X - 20, 300, 440)
local height = math.clamp(viewport.Y - 40, 320, 540)

local frame = New("Frame", {
    Name = "Hub",
    Size = UDim2.fromOffset(width, height),
    Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
    BackgroundColor3 = C.window,
    BorderSizePixel = 0,
    Active = true,
    Visible = true,
}, gui)
Corner(frame, 14)
Stroke(frame, C.ink, 4)
local frameScale = New("UIScale", { Scale = 0.88 }, frame)
Tween(frameScale, 0.3, { Scale = 1 })

local header = New("Frame", {
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundTransparency = 1,
}, frame)
for _, d in ipairs({ { 0.56, 9, 16 }, { 0.63, 25, 10 }, { 0.5, 24, 12 } }) do
    local dot = New("Frame", {
        Position = UDim2.new(d[1], 0, 0, d[2]),
        Size = UDim2.fromOffset(d[3], d[3]),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
    }, header)
    Corner(dot, d[3])
end
Label(header, {
    Text = "FIREFLY HUB",
    TextSize = 22,
    TextColor3 = C.white,
    TextStrokeColor3 = C.ink,
    TextStrokeTransparency = 0,
    Position = UDim2.fromOffset(14, 2),
    Size = UDim2.fromOffset(170, 44),
    TextWrapped = false,
    Rotation = -3,
})

local closeButton = MakeButton(header, "X", "danger", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    TextSize = 13,
})
closeButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 15)

local minimizeButton = MakeButton(header, "-", "ghost", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -48, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    TextSize = 16,
})
minimizeButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 15)

-- geser jendela lewat header
do
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    table.insert(conns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

local divider = New("Frame", {
    Position = UDim2.new(0, 12, 0, 47),
    Size = UDim2.new(1, -24, 0, 3),
    BackgroundColor3 = C.ink,
    BorderSizePixel = 0,
}, frame)
Corner(divider, 1)

-- Tab
local tabBar = New("Frame", {
    Position = UDim2.fromOffset(12, 58),
    Size = UDim2.new(1, -24, 0, 34),
    BackgroundTransparency = 1,
}, frame)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local panel = New("Frame", {
    Position = UDim2.fromOffset(12, 100),
    Size = UDim2.new(1, -24, 1, -112),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
}, frame)
Corner(panel, 12)
Stroke(panel, C.ink, 3)

local pages, tabs = {}, {}
local function SwitchTab(id)
    for tabId, page in pairs(pages) do
        page.Visible = (tabId == id)
    end
    for tabId, tab in pairs(tabs) do
        local active = (tabId == id)
        Tween(tab.button, 0.18, { BackgroundTransparency = active and 0 or 0.55 })
        tab.button.TextColor3 = active and C.white or C.ink
        tab.button.TextStrokeTransparency = active and 0.35 or 1
    end
end

local function MakePage(id, label, color, order)
    local button = New("TextButton", {
        Size = UDim2.new(0.5, -4, 1, 0),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = label,
        TextColor3 = C.ink,
        TextStrokeColor3 = C.ink,
        TextStrokeTransparency = 1,
        Font = C.font,
        TextSize = 14,
        LayoutOrder = order,
    }, tabBar)
    Corner(button, 8)
    Stroke(button, C.ink, 2)
    button.MouseButton1Click:Connect(function()
        SwitchTab(id)
    end)
    tabs[id] = { button = button }

    local page = New("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = C.accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, panel)
    New("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
    }, page)
    pages[id] = page
    return page
end

----------------------------------------------------------------------
-- HALAMAN: AUTO FARM
----------------------------------------------------------------------
local farmPage = MakePage("farm", "Auto Farm", C.ok, 1)

local statusLabel = StatusLabel(AutoCard(farmPage))

local toggleButton = MakeButton(farmPage, "MULAI FARM", "ok", {
    Size = UDim2.new(1, 0, 0, 42),
    TextSize = 16,
    LayoutOrder = NextOrder(farmPage),
})
toggleButton.MouseButton1Click:Connect(function()
    if Farm.on then
        StopFarm()
    else
        StartFarm()
    end
end)

AddSection(farmPage, "Delay")
AddInputCard(farmPage, "Delay break", "Jeda antar pukulan (detik). Minimum 0.03.", Config.breakDelay, function(text, box)
    local value = tonumber(text)
    if value and value >= 0.03 and value <= 5 then
        Config.breakDelay = value
        SaveConfig()
    else
        box.Text = tostring(Config.breakDelay)
        Notify("Isi angka 0.03 sampai 5.")
    end
end)
AddInputCard(farmPage, "Delay place", "Jeda antar place (detik). Minimum 0.03.", Config.placeDelay, function(text, box)
    local value = tonumber(text)
    if value and value >= 0.03 and value <= 5 then
        Config.placeDelay = value
        SaveConfig()
    else
        box.Text = tostring(Config.placeDelay)
        Notify("Isi angka 0.03 sampai 5.")
    end
end)

AddSection(farmPage, "Pilih item")
local refreshButton = MakeButton(farmPage, "Refresh Inventory", "primary", {
    LayoutOrder = NextOrder(farmPage),
})

local searchCard = AddCard(farmPage, 40)
local searchBox = New("TextBox", {
    Position = UDim2.fromOffset(8, 5),
    Size = UDim2.new(1, -16, 1, -10),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Cari nama item...",
    PlaceholderColor3 = C.mute,
    TextColor3 = C.ink,
    Font = C.font,
    TextSize = 13,
    ClearTextOnFocus = false,
}, searchCard)
Corner(searchBox, 8)
New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, searchBox)

local invList = New("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = NextOrder(farmPage),
}, farmPage)
New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, invList)

local function RenderInventory()
    for _, child in ipairs(invList:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end
    if #Inventory == 0 then
        Label(invList, {
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Belum ada item. Tekan Refresh Inventory.",
            TextColor3 = C.mute,
            TextSize = 11,
        })
        return
    end
    local query = searchBox.Text:lower()
    local shown = 0
    for index, entry in ipairs(Inventory) do
        if query == "" or entry.name:lower():find(query, 1, true) then
            shown += 1
            if shown > 60 then
                Label(invList, {
                    Size = UDim2.new(1, 0, 0, 20),
                    Text = "Daftar dipotong 60 item, pakai pencarian.",
                    TextColor3 = C.mute,
                    TextSize = 11,
                    LayoutOrder = index,
                })
                break
            end
            local selected = Config.itemId == entry.id
            local row = MakeButton(invList,
                string.format("%s   x%d%s", entry.name, entry.count, selected and "   (dipilih)" or ""),
                selected and "ok" or "ghost", {
                    Size = UDim2.new(1, 0, 0, 30),
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = index,
                })
            New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
            row.MouseButton1Click:Connect(function()
                Config.itemId = entry.id
                SaveConfig()
                Notify("Item: " .. entry.name)
                RenderInventory()
            end)
        end
    end
    if shown == 0 then
        Label(invList, {
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Tidak ada hasil.",
            TextColor3 = C.mute,
            TextSize = 11,
        })
    end
end

refreshButton.MouseButton1Click:Connect(function()
    local list = ScanInventory()
    RenderInventory()
    Notify(#list .. " item bisa di-place di inventory.")
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(RenderInventory)

AddSection(farmPage, "Kotak 5x5")
AddNote(farmPage, "Kotak biru = posisimu. Tap sampai HIJAU = dikerjakan, MERAH = dilewati. Tulisan di kotak = isi tile yang terdeteksi.")

local gridCard = AddCard(farmPage, 5 * 46 + 4 * 6 + 18)
local gridFrame = New("Frame", {
    Position = UDim2.fromOffset(9, 9),
    Size = UDim2.new(1, -18, 1, -18),
    BackgroundTransparency = 1,
}, gridCard)
New("UIGridLayout", {
    CellSize = UDim2.new(0.2, -5, 0, 46),
    CellPadding = UDim2.fromOffset(6, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, gridFrame)

local gridButtons = {}
local centerLabel = nil

local function PaintCell(key)
    local cell = gridButtons[key]
    if cell then
        cell.BackgroundColor3 = Config.grid[key] == true and C.ok or C.bad
    end
end

-- baris atas = dy +2 (ke atas di game)
for dy = 2, -2, -1 do
    for dx = -2, 2 do
        local key = dx .. "," .. dy
        local order = (2 - dy) * 5 + (dx + 2)
        if dx == 0 and dy == 0 then
            centerLabel = New("TextLabel", {
                BorderSizePixel = 0,
                BackgroundColor3 = C.accent2,
                Text = "KAMU",
                TextColor3 = C.white,
                TextStrokeColor3 = C.ink,
                TextStrokeTransparency = 0.35,
                Font = C.font,
                TextSize = 12,
                TextWrapped = true,
                LayoutOrder = order,
            }, gridFrame)
            Corner(centerLabel, 8)
            Stroke(centerLabel, C.ink, 2)
        else
            local cell = New("TextButton", {
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                TextColor3 = C.white,
                TextStrokeColor3 = C.ink,
                TextStrokeTransparency = 0.4,
                Font = C.font,
                TextSize = 10,
                TextWrapped = true,
                LayoutOrder = order,
            }, gridFrame)
            Corner(cell, 8)
            Stroke(cell, C.ink, 2)
            local pop = New("UIScale", { Scale = 1 }, cell)
            gridButtons[key] = cell
            PaintCell(key)
            cell.MouseButton1Click:Connect(function()
                Config.grid[key] = (not Config.grid[key]) or nil
                SaveConfig()
                PaintCell(key)
                pop.Scale = 0.75
                Tween(pop, 0.25, { Scale = 1 })
            end)
        end
    end
end

local rowButtons = New("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundTransparency = 1,
    LayoutOrder = NextOrder(farmPage),
}, farmPage)
local fillAll = MakeButton(rowButtons, "Hijau semua", "ok", { Size = UDim2.new(0.5, -4, 1, 0) })
local clearAll = MakeButton(rowButtons, "Merah semua", "danger", {
    Size = UDim2.new(0.5, -4, 1, 0),
    Position = UDim2.new(0.5, 4, 0, 0),
})
fillAll.MouseButton1Click:Connect(function()
    for dy = -2, 2 do
        for dx = -2, 2 do
            if not (dx == 0 and dy == 0) then
                Config.grid[dx .. "," .. dy] = true
            end
        end
    end
    SaveConfig()
    for key in pairs(gridButtons) do
        PaintCell(key)
    end
end)
clearAll.MouseButton1Click:Connect(function()
    Config.grid = {}
    SaveConfig()
    for key in pairs(gridButtons) do
        PaintCell(key)
    end
end)

----------------------------------------------------------------------
-- HALAMAN: NOCLIP
----------------------------------------------------------------------
local noclipPage = MakePage("noclip", "Noclip", C.accent, 2)
AddSwitchCard(noclipPage, "Noclip (Ghost)", "Mengaktifkan mode ghost bawaan game: terbang menembus tile.",
    function() return Noclip.on end,
    function(on)
        if on then
            StartNoclip()
            Notify("Ghost aktif. Naik: tahan lompat. Turun: tombol Down.")
        else
            StopNoclip()
            Notify("Ghost dimatikan.")
        end
    end)
AddNote(noclipPage, "Cara pakai: kiri/kanan = gerak, tahan tombol lompat = naik, tombol Down = turun. "
    .. "Di HP, panah bawah akan muncul sendiri saat ghost aktif.")
AddNote(noclipPage, "Catatan: game ini memakai ghost sebagai fitur staff, jadi server yang menentukan. "
    .. "Kalau server menolak, posisimu dikembalikan otomatis. Nonaktifkan ghost sebelum ganti world.")

----------------------------------------------------------------------
-- UPDATE LIVE
----------------------------------------------------------------------
local function Abbrev(name)
    name = tostring(name)
    if #name > 6 then
        return name:sub(1, 5) .. "."
    end
    return name
end

local liveConn
do
    local acc = 0
    liveConn = RunService.Heartbeat:Connect(function(dt)
        acc += dt
        if acc < 0.3 then
            return
        end
        acc = 0

        -- status farm
        local id = Config.itemId
        local itemText = (type(id) == "number" and id > 0) and (ItemName(id) .. " x" .. CountOf(id)) or "belum dipilih"
        local green = 0
        for _, on in pairs(Config.grid) do
            if on then
                green += 1
            end
        end
        local text = string.format(
            "Status: %s\nItem: %s\nKotak hijau: %d%s\nPlace %d   Break %d   Gagal %d   Siklus %d",
            Farm.status, itemText, green,
            FARM_READY and "" or "\n(Modul game tidak lengkap!)",
            Farm.placed, Farm.broken, Farm.failed, Farm.cycles)
        if Farm.outOfRange > 0 then
            text ..= "\nDi luar jangkauan: " .. Farm.outOfRange .. " (dekati tile / pakai kotak lebih dekat)"
        end
        statusLabel.Text = text
        toggleButton.Text = Farm.on and "STOP FARM" or "MULAI FARM"
        toggleButton.BackgroundColor3 = Farm.on and C.bad or C.ok

        -- deteksi tile di grid
        if FARM_READY and InWorld() then
            local gx, gy = PlayerCell()
            if gx then
                local layer = (type(id) == "number" and id > 0 and LayerOf(id)) or LAYER_FG
                for key, cell in pairs(gridButtons) do
                    local dx, dy = key:match("^(-?%d+),(-?%d+)$")
                    local tile = TileAt(layer, gx + tonumber(dx), gy + tonumber(dy))
                    local tid = TileItem(tile)
                    if tid then
                        cell.Text = Abbrev(ItemName(tid))
                    elseif tile then
                        cell.Text = "?"
                    else
                        cell.Text = ""
                    end
                end
                if centerLabel then
                    centerLabel.Text = "KAMU\n" .. gx .. "," .. gy
                end
            end
        end
        for _, refresh in ipairs(refreshers) do
            pcall(refresh)
        end
    end)
end

----------------------------------------------------------------------
-- TOMBOL PELUNCUR + TUTUP/KECILKAN
----------------------------------------------------------------------
local minimized = false
minimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    panel.Visible = not minimized
    tabBar.Visible = not minimized
    minimizeButton.Text = minimized and "+" or "-"
    Tween(frame, 0.22, { Size = UDim2.fromOffset(width, minimized and 52 or height) })
end)

local launcher = New("Frame", {
    Name = "Launcher",
    Size = UDim2.fromOffset(48, 48),
    Position = UDim2.new(0, 12, 0.5, -24),
    BackgroundColor3 = C.accent,
    BorderSizePixel = 0,
    ZIndex = 50,
}, gui)
Corner(launcher, 24)
Stroke(launcher, C.ink, 3)
local launcherButton = New("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "F",
    TextColor3 = C.white,
    TextStrokeColor3 = C.ink,
    TextStrokeTransparency = 0,
    Font = C.font,
    TextSize = 26,
    ZIndex = 51,
}, launcher)

local function SetHubVisible(visible)
    frame.Visible = visible
    if visible then
        frameScale.Scale = 0.88
        Tween(frameScale, 0.3, { Scale = 1 })
    end
end

closeButton.MouseButton1Click:Connect(function()
    SetHubVisible(false)
end)

do
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    launcherButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = input.Position
            startPos = launcher.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved then
                        SetHubVisible(not frame.Visible)
                    end
                end
            end)
        end
    end)
    table.insert(conns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then
                moved = true
            end
            if moved then
                launcher.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end))
end

----------------------------------------------------------------------
-- MULAI
----------------------------------------------------------------------
genv.FireflyPeexCleanup = function()
    StopFarm()
    StopNoclip()
    if liveConn then
        liveConn:Disconnect()
    end
    for _, conn in ipairs(conns) do
        conn:Disconnect()
    end
    if gui then
        gui:Destroy()
    end
    genv.FireflyPeexCleanup = nil
end

SwitchTab("farm")
RenderInventory()
if FARM_READY then
    task.spawn(function()
        task.wait(1)
        ScanInventory()
        RenderInventory()
    end)
    Notify("Firefly Hub siap. Tekan Refresh Inventory lalu pilih item.")
else
    Notify("Sebagian modul game tidak ditemukan. Noclip tetap bisa dipakai.")
end
