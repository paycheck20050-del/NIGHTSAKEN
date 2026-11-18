
--========================================================
-- NIGHTSAKEN v0.3
-- FORSAKEN MOBILE OPTIMIZER
-- UI: WINDUI
-- EXECUTOR: DELTA
--========================================================

--========================================================
-- SERVICES
--========================================================

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

--========================================================
-- CONFIGURATION
--========================================================

local CONFIG_FILE = "NIGHTSAKEN_V03.json"

local Settings = {
    LowGraphics = false,
    ExtremelyLow = false,
    OptimizeLighting = false,
    RemoveVegetation = false,
    RemoveDecoration = false,
    OptimizeOutro = false
}

local Palette = {
    Color3.fromHex("#777C72"),
    Color3.fromHex("#A6A49A"),
    Color3.fromHex("#89939B"),
    Color3.fromHex("#66717D")
}

local WindUI = nil
local Window = nil

local BatchSize = 40
local BatchDelay = 0.015

--========================================================
-- STATES
--========================================================

local JobQueue = {}
local JobRunning = false

local GraphicsProcessed = setmetatable({}, {__mode = "k"})
local VegetationProcessed = setmetatable({}, {__mode = "k"})
local DecorationProcessed = setmetatable({}, {__mode = "k"})

local MapSnapshots = setmetatable({}, {__mode = "k"})
local MapVegetationDone = setmetatable({}, {__mode = "k"})
local MapDecorationDone = setmetatable({}, {__mode = "k"})

local CurrentMapReference = nil
local CurrentMapActive = false

local EnqueueJob

--========================================================
-- SETTINGS
--========================================================

local function LoadSettings()
    if type(isfile) ~= "function"
        or type(readfile) ~= "function" then
        return
    end

    local success, data = pcall(function()
        if isfile(CONFIG_FILE) then
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end
    end)

    if success and type(data) == "table" then
        for key in pairs(Settings) do
            if data[key] ~= nil then
                Settings[key] = data[key] == true
            end
        end
    end
end

local function SaveSettings()
    if type(writefile) ~= "function" then
        return
    end

    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(Settings))
    end)
end

LoadSettings()

--========================================================
-- NOTIFICATIONS
--========================================================

local function Notify(title, message)
    if not WindUI then
        print("[NIGHTSAKEN] " .. tostring(message))
        return
    end

    pcall(function()
        WindUI:Notify({
            Title = title,
            Content = message,
            Duration = 4
        })
    end)
end

--========================================================
-- NAME NORMALIZATION
--========================================================

local function NormalizeName(name)
    name = string.lower(tostring(name))
    name = name:gsub("[%s_%-%.]", "")
    return name
end

local function ContainsKeyword(name, keywords)
    name = NormalizeName(name)

    for _, keyword in ipairs(keywords) do
        if string.find(
            name,
            NormalizeName(keyword),
            1,
            true
        ) then
            return true
        end
    end

    return false
end

--========================================================
-- ENGLISH KEYWORDS
--========================================================

local VegetationKeywords = {
    "tree", "trees", "leaf", "leaves",
    "foliage", "branch", "branches",
    "trunk", "stump", "bush", "bushes",
    "shrub", "grass", "flower", "flowers",
    "plant", "plants", "fern", "vine",
    "mushroom", "weed", "log", "logs",
    "vegetation", "pine", "oak", "palm",
    "hedge", "ivy"
}

local DecorationKeywords = {
    "lamp", "lamppost", "lightpole",
    "streetlight", "pumpkin", "pot",
    "vase", "painting", "picture",
    "chair", "chairs", "shelf", "shelves",
    "table", "tables", "sofa", "couch",
    "carpet", "rug", "arcade", "slotmachine",
    "billiard", "pooltable", "television",
    "tv", "mannequin", "statue", "sign",
    "barrel", "crate", "lantern", "candle",
    "computer", "monitor", "bench",
    "foodstand", "decoration", "ornament",
    "poster", "clock", "cabinet",
    "vendingmachine", "trashcan",
    "plantpot", "flowerpot", "furniture",
    "bookshelf", "bookcase", "chandelier",
    "pictureframe", "paintingframe",
    "fireplace", "fountain", "sculpture",
    "mailbox", "trafficcone", "roadbarrier"
}

--========================================================
-- PROTECTED OBJECTS
--========================================================

local ProtectedKeywords = {
    "door", "exit", "spawn", "killer",
    "survivor", "generator", "objective",
    "interact", "prompt", "hitbox",
    "trigger", "collision", "checkpoint",
    "teleport", "shop", "button", "lever",
    "weapon", "tool", "character",
    "player", "npc", "rig", "camera",
    "mapboundary", "invisiblewall",
    "ability", "health", "damage",
    "round", "timer", "outro",
    "stairs", "floor", "ground",
    "wall", "ceiling", "barrier"
}

local function IsCollisionProxy(object)
    local current = object

    while current and current ~= Workspace do
        if current.Name == "NS_CollisionProxy" then
            return true
        end

        current = current.Parent
    end

    return false
end

local function HasInteraction(object)
    if not object:IsA("Model") then
        return false
    end

    for _, item in ipairs(object:GetDescendants()) do
        if item:IsA("ProximityPrompt")
            or item:IsA("ClickDetector")
            or item:IsA("Humanoid")
            or item:IsA("Tool")
            or item:IsA("Seat")
            or item:IsA("VehicleSeat")
            or item:IsA("SpawnLocation") then
            return true
        end
    end

    return false
end

local function IsProtected(object)
    if not object or not object.Parent then
        return true
    end

    if IsCollisionProxy(object) then
        return true
    end

    if Player.Character
        and object:IsDescendantOf(Player.Character) then
        return true
    end

    local current = object

    while current and current ~= Workspace do
        if ContainsKeyword(current.Name, ProtectedKeywords) then
            return true
        end

        current = current.Parent
    end

    if HasInteraction(object) then
        return true
    end

    return false
end

print("[NIGHTSAKEN] Parte 1 cargada")
--========================================================
-- PART 2: GRAPHICS OPTIMIZER
--========================================================

local function OptimizeObject(object)
    if not object or not object.Parent then
        return
    end

    pcall(function()
        if object:IsA("BasePart") then
            local state = GraphicsProcessed[object] or {}

            if not state.Basic then
                object.Material = Enum.Material.SmoothPlastic
                object.CastShadow = false
                state.Basic = true
            end

            if Settings.ExtremelyLow and not state.Extreme then
                object.Color = Palette[
                    math.random(1, #Palette)
                ]
                state.Extreme = true
            end

            GraphicsProcessed[object] = state

        elseif object:IsA("Decal")
            or object:IsA("Texture") then
            object.Transparency = 1

        elseif object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles") then
            object.Enabled = false
        end
    end)
end

local function OptimizeLighting()
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Brightness = 2

        for _, effect in ipairs(Lighting:GetDescendants()) do
            if effect:IsA("PostEffect") then
                effect.Enabled = false
            end
        end
    end)
end

--========================================================
-- PART 2: VEGETATION REMOVER
--========================================================

-- No crea copias de modelos.
-- Oculta únicamente la parte visual y conserva
-- las propiedades de colisión originales.

local function HideVegetation(object)
    if not object or not object.Parent then
        return false
    end

    if IsProtected(object) then
        return false
    end

    local parts = {}

    if object:IsA("BasePart") then
        table.insert(parts, object)
    elseif object:IsA("Model") then
        for _, item in ipairs(object:GetDescendants()) do
            if item:IsA("BasePart") then
                table.insert(parts, item)
            end
        end
    else
        return false
    end

    if #parts == 0 then
        return false
    end

    for index, part in ipairs(parts) do
        pcall(function()
            part.LocalTransparencyModifier = 1
            part.CastShadow = false
        end)

        if index % BatchSize == 0 then
            task.wait(BatchDelay)
        end
    end

    if object:IsA("Model") then
        for _, item in ipairs(object:GetDescendants()) do
            pcall(function()
                if item:IsA("Decal")
                    or item:IsA("Texture") then
                    item.Transparency = 1

                elseif item:IsA("ParticleEmitter")
                    or item:IsA("Trail")
                    or item:IsA("Beam")
                    or item:IsA("Smoke")
                    or item:IsA("Fire")
                    or item:IsA("Sparkles") then
                    item.Enabled = false
                end
            end)
        end
    end

    return true
end

local function FindVegetationCandidates(objects)
    local selected = {}
    local candidates = {}

    for index, object in ipairs(objects) do
        if (object:IsA("Model") or object:IsA("BasePart"))
            and not IsProtected(object)
            and ContainsKeyword(object.Name, VegetationKeywords) then

            selected[object] = true
        end

        if index % BatchSize == 0 then
            task.wait(BatchDelay)
        end
    end

    for object in pairs(selected) do
        local parent = object.Parent
        local hasParent = false

        while parent and parent ~= Workspace do
            if selected[parent] then
                hasParent = true
                break
            end

            parent = parent.Parent
        end

        if not hasParent then
            table.insert(candidates, object)
        end
    end

    return candidates
end

local function RemoveVegetation(objects)
    local candidates = FindVegetationCandidates(objects)
    local hidden = 0

    for index, object in ipairs(candidates) do
        if object.Parent
            and not VegetationProcessed[object] then

            VegetationProcessed[object] = true

            if HideVegetation(object) then
                hidden = hidden + 1
            end
        end

        if index % 10 == 0 then
            task.wait()
        end
    end

    Notify(
        "Vegetation Remover",
        "Vegetación visual ocultada: " .. tostring(hidden)
    )
end

--========================================================
-- PART 2: DECORATION REMOVER
--========================================================

local function RemoveMatchingObjects(objects, keywords)
    local selected = {}
    local candidates = {}
    local removed = 0
    local skipped = 0

    for index, object in ipairs(objects) do
        if (object:IsA("Model") or object:IsA("BasePart"))
            and not IsProtected(object)
            and ContainsKeyword(object.Name, keywords) then

            selected[object] = true
        end

        if index % BatchSize == 0 then
            task.wait(BatchDelay)
        end
    end

    for object in pairs(selected) do
        local parent = object.Parent
        local hasParent = false

        while parent and parent ~= Workspace do
            if selected[parent] then
                hasParent = true
                break
            end

            parent = parent.Parent
        end

        if not hasParent then
            table.insert(candidates, object)
        end
    end

    for index, object in ipairs(candidates) do
        if object.Parent and not IsProtected(object) then
            DecorationProcessed[object] = true

            local success = pcall(function()
                object:Destroy()
            end)

            if success then
                removed = removed + 1
            else
                skipped = skipped + 1
            end
        end

        if index % 10 == 0 then
            task.wait()
        end
    end

    return removed, skipped
end

print("[NIGHTSAKEN] Parte 2 cargada")
--========================================================
-- PART 3: MATCH DETECTION
--========================================================

local LobbyNames = {
    "lobby",
    "mainlobby",
    "waitingroom",
    "intermission",
    "menu"
}

local MapNames = {
    "map",
    "currentmap",
    "activemap",
    "mapfolder",
    "gamemap",
    "current_map",
    "active_map"
}

local MatchMarkers = {
    "RoundActive",
    "InRound",
    "GameStarted",
    "MatchStarted",
    "RoundInProgress",
    "IsPlaying"
}

local function GetMarkerValue(container, markerName)
    if not container then
        return nil
    end

    local attribute = container:GetAttribute(markerName)

    if type(attribute) == "boolean" then
        return attribute
    end

    local value = container:FindFirstChild(markerName)

    if value and (value:IsA("BoolValue")) then
        return value.Value
    end

    return nil
end

local function GetMatchMarker()
    for _, marker in ipairs(MatchMarkers) do
        local value = GetMarkerValue(Workspace, marker)

        if value ~= nil then
            return value
        end

        value = GetMarkerValue(Player, marker)

        if value ~= nil then
            return value
        end
    end

    return nil
end

local function IsLobbyPresent()
    for _, child in ipairs(Workspace:GetChildren()) do
        if ContainsKeyword(child.Name, LobbyNames) then
            return true
        end
    end

    return false
end

local function GetCurrentMapRoot()
    for _, child in ipairs(Workspace:GetChildren()) do
        if ContainsKeyword(child.Name, MapNames) then
            return child
        end
    end

    return nil
end

local function IsMatchActive()
    local marker = GetMatchMarker()

    if marker == false then
        return false
    end

    if marker == true then
        return GetCurrentMapRoot() ~= nil
    end

    if IsLobbyPresent() then
        return false
    end

    -- Sin un indicador confirmado de partida,
    -- los removers permanecen detenidos.
    return false
end

--========================================================
-- PART 3: MAP SNAPSHOT
--========================================================

local function CreateMapSnapshot(mapRoot)
    if not mapRoot or not mapRoot.Parent then
        return {}
    end

    if MapSnapshots[mapRoot] then
        return MapSnapshots[mapRoot]
    end

    local objects = mapRoot:GetDescendants()

    MapSnapshots[mapRoot] = objects

    print(
        "[NIGHTSAKEN] Mapa capturado:",
        mapRoot.Name,
        #objects,
        "objetos"
    )

    return objects
end

--========================================================
-- PART 3: JOB QUEUE
--========================================================

EnqueueJob = function(name, callback)
    table.insert(JobQueue, {
        Name = name,
        Callback = callback
    })

    if JobRunning then
        return
    end

    JobRunning = true

    task.spawn(function()
        while #JobQueue > 0 do
            local job = table.remove(JobQueue, 1)

            local success, err = xpcall(
                job.Callback,
                function(message)
                    return tostring(message)
                end
            )

            if not success then
                warn(
                    "[NIGHTSAKEN] Error en "
                    .. job.Name .. ": " .. tostring(err)
                )

                Notify("NIGHTSAKEN", "Error en " .. job.Name)
            end

            task.wait(0.1)
        end

        JobRunning = false

        -- Si entró otro trabajo al terminar,
        -- iniciar nuevamente la cola sin agregar
        -- trabajos ficticios.
        if #JobQueue > 0 then
            EnqueueJob("Pending Jobs", function() end)
        end
    end)
end

--========================================================
-- PART 3: MAP REMOVERS
--========================================================

local function ProcessMapRemovers(mapRoot)
    if not mapRoot or not IsMatchActive() then
        return
    end

    local objects = CreateMapSnapshot(mapRoot)

    if Settings.RemoveVegetation
        and not MapVegetationDone[mapRoot] then

        MapVegetationDone[mapRoot] = true

        EnqueueJob("Vegetation Remover", function()
            if IsMatchActive() then
                RemoveVegetation(objects)
            end
        end)
    end

    if Settings.RemoveDecoration
        and not MapDecorationDone[mapRoot] then

        MapDecorationDone[mapRoot] = true

        EnqueueJob("Decoration Remover", function()
            if IsMatchActive() then
                local removed, skipped = RemoveMatchingObjects(
                    objects,
                    DecorationKeywords
                )

                Notify(
                    "Decoration Remover",
                    tostring(removed) .. " eliminados; "
                    .. tostring(skipped) .. " omitidos"
                )
            end
        end)
    end
end

print("[NIGHTSAKEN] Parte 3 cargada")
--========================================================
-- PART 4: WINDUI LOADER
--========================================================

local WINDUI_VERSION = "1.6.66"

local WINDUI_URL =
    "https://github.com/Footagesus/WindUI/releases/download/"
    .. WINDUI_VERSION .. "/main.lua"

local fetchSuccess, source = pcall(function()
    return game:HttpGet(WINDUI_URL)
end)

if not fetchSuccess
    or type(source) ~= "string"
    or #source < 1000 then

    warn("[NIGHTSAKEN] Error descargando WindUI")
    return
end

local compileSuccess, compiled = pcall(function()
    return loadstring(source)
end)

if not compileSuccess or type(compiled) ~= "function" then
    warn("[NIGHTSAKEN] Error compilando WindUI")
    return
end

local loadSuccess, loadedWindUI = pcall(compiled)

if not loadSuccess or type(loadedWindUI) ~= "table" then
    warn("[NIGHTSAKEN] Error iniciando WindUI")
    return
end

WindUI = loadedWindUI

--========================================================
-- PART 4: WINDOW
--========================================================

local windowSuccess, createdWindow = pcall(function()
    return WindUI:CreateWindow({
        Title = "NIGHTSAKEN",
        Author = "Forsaken Optimizer",
        Icon = "moon",
        Folder = "NIGHTSAKEN_v03",
        Theme = "Dark",
        Size = UDim2.fromOffset(420, 430),
        MinSize = Vector2.new(300, 350),
        Resizable = true,
        SideBarWidth = 150,
        HideSearchBar = false
    })
end)

if not windowSuccess or not createdWindow then
    warn("[NIGHTSAKEN] Error creando ventana")
    return
end

Window = createdWindow

pcall(function()
    Window:Tag({
        Title = "v0.3",
        Color = Color3.fromHex("#89939B")
    })
end)

local tabsSuccess, tabs = pcall(function()
    return {
        Main = Window:Tab({
            Title = "Optimizer",
            Icon = "zap"
        }),

        Remover = Window:Tab({
            Title = "Remover",
            Icon = "trash-2"
        }),

        Settings = Window:Tab({
            Title = "Settings",
            Icon = "settings"
        }),

        Info = Window:Tab({
            Title = "Info",
            Icon = "info"
        })
    }
end)

if not tabsSuccess or not tabs then
    warn("[NIGHTSAKEN] Error creando pestañas")
    return
end

local MainTab = tabs.Main
local RemoverTab = tabs.Remover
local SettingsTab = tabs.Settings
local InfoTab = tabs.Info

--========================================================
-- PART 4: GRAPHICS CALLBACKS
--========================================================

local function SetLowGraphics(enabled)
    Settings.LowGraphics = enabled
    SaveSettings()

    if not enabled then
        return
    end

    EnqueueJob("Low Graphics", function()
        local objects = Workspace:GetDescendants()

        for index, object in ipairs(objects) do
            if Settings.LowGraphics or Settings.ExtremelyLow then
                OptimizeObject(object)
            end

            if index % BatchSize == 0 then
                task.wait(BatchDelay)
            end
        end
    end)
end

local function SetExtremelyLow(enabled)
    Settings.ExtremelyLow = enabled
    SaveSettings()

    if not enabled then
        return
    end

    EnqueueJob("Extremely Low Graphics", function()
        local objects = Workspace:GetDescendants()

        for index, object in ipairs(objects) do
            if Settings.ExtremelyLow then
                OptimizeObject(object)
            end

            if index % BatchSize == 0 then
                task.wait(BatchDelay)
            end
        end
    end)
end

local function SetOptimizeLighting(enabled)
    Settings.OptimizeLighting = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Optimize Lighting", OptimizeLighting)
    end
end

--========================================================
-- PART 4: REMOVER CALLBACKS
--========================================================

local function SetRemoveVegetation(enabled)
    Settings.RemoveVegetation = enabled
    SaveSettings()

    if not enabled then
        return
    end

    if not IsMatchActive() then
        Notify(
            "Vegetation Remover",
            "Esperando a que comience una partida"
        )
        return
    end

    local mapRoot = GetCurrentMapRoot()

    if mapRoot then
        ProcessMapRemovers(mapRoot)
    end
end

local function SetRemoveDecoration(enabled)
    Settings.RemoveDecoration = enabled
    SaveSettings()

    if not enabled then
        return
    end

    if not IsMatchActive() then
        Notify(
            "Decoration Remover",
            "Esperando a que comience una partida"
        )
        return
    end

    local mapRoot = GetCurrentMapRoot()

    if mapRoot then
        ProcessMapRemovers(mapRoot)
    end
end

--========================================================
-- PART 4: UI CONTROLS
--========================================================

MainTab:Section({
    Title = "Graphics"
})

MainTab:Toggle({
    Title = "Low Graphics",
    Desc = "Reduce materiales y sombras",
    Value = Settings.LowGraphics,
    Callback = SetLowGraphics
})

MainTab:Toggle({
    Title = "Extremely Low Graphics",
    Desc = "Optimización visual extrema",
    Value = Settings.ExtremelyLow,
    Callback = SetExtremelyLow
})

MainTab:Toggle({
    Title = "Optimize Lighting",
    Desc = "Reduce efectos de iluminación",
    Value = Settings.OptimizeLighting,
    Callback = SetOptimizeLighting
})

RemoverTab:Section({
    Title = "World Remover"
})

RemoverTab:Toggle({
    Title = "Remover vegetación",
    Desc = "Oculta vegetación y conserva colisiones",
    Value = Settings.RemoveVegetation,
    Callback = SetRemoveVegetation
})

RemoverTab:Toggle({
    Title = "Remover decoración",
    Desc = "Elimina decoración identificada por nombre",
    Value = Settings.RemoveDecoration,
    Callback = SetRemoveDecoration
})

SettingsTab:Section({
    Title = "Interface"
})

SettingsTab:Button({
    Title = "Save Settings",
    Desc = "Guardar configuración",
    Callback = function()
        SaveSettings()
        Notify("NIGHTSAKEN", "Configuración guardada")
    end
})

InfoTab:Section({
    Title = "NIGHTSAKEN v0.3"
})

InfoTab:Paragraph({
    Title = "Forsaken Mobile Optimizer",
    Content = "Optimizador visual para dispositivos móviles."
})

InfoTab:Paragraph({
    Title = "Map Scan",
    Content = "Una captura por mapa. No repite el escaneo del mismo mapa."
})

InfoTab:Paragraph({
    Title = "Vegetation",
    Content = "Oculta la vegetación visual sin crear copias físicas."
})

InfoTab:Paragraph({
    Title = "Decoration",
    Content = "Elimina objetos decorativos identificados y protege objetos interactivos."
})

print("[NIGHTSAKEN] Parte 4 cargada")
--========================================================
-- PART 5: NEW OBJECT DETECTION
--========================================================

local function GetVegetationTarget(object)
    if not object or IsCollisionProxy(object) then
        return nil
    end

    local current = object

    while current and current ~= Workspace do
        if current:IsA("Model")
            and ContainsKeyword(
                current.Name,
                VegetationKeywords
            ) then
            return current
        end

        current = current.Parent
    end

    if object:IsA("BasePart")
        and ContainsKeyword(
            object.Name,
            VegetationKeywords
        ) then
        return object
    end

    return nil
end

local function GetDecorationTarget(object)
    if not object or IsCollisionProxy(object) then
        return nil
    end

    local current = object

    while current and current ~= Workspace do
        if current:IsA("Model")
            and ContainsKeyword(
                current.Name,
                DecorationKeywords
            ) then
            return current
        end

        current = current.Parent
    end

    if (object:IsA("Model") or object:IsA("BasePart"))
        and ContainsKeyword(
            object.Name,
            DecorationKeywords
        ) then
        return object
    end

    return nil
end

local function ProcessNewObject(object)
    if not object or not object.Parent then
        return
    end

    if IsCollisionProxy(object) then
        return
    end

    if Settings.LowGraphics or Settings.ExtremelyLow then
        OptimizeObject(object)
    end

    if not IsMatchActive() then
        return
    end

    local mapRoot = GetCurrentMapRoot()

    if not mapRoot or not object:IsDescendantOf(mapRoot) then
        return
    end

    if Settings.RemoveVegetation then
        local target = GetVegetationTarget(object)

        if target
            and not VegetationProcessed[target]
            and not IsProtected(target) then

            VegetationProcessed[target] = true

            EnqueueJob("New Vegetation", function()
                if IsMatchActive() and target.Parent then
                    HideVegetation(target)
                end
            end)
        end
    end

    if Settings.RemoveDecoration then
        local target = GetDecorationTarget(object)

        if target
            and not DecorationProcessed[target]
            and not IsProtected(target) then

            DecorationProcessed[target] = true

            EnqueueJob("New Decoration", function()
                if IsMatchActive()
                    and target.Parent
                    and not IsProtected(target) then

                    pcall(function()
                        target:Destroy()
                    end)
                end
            end)
        end
    end
end

Workspace.DescendantAdded:Connect(function(object)
    task.delay(0.5, function()
        ProcessNewObject(object)
    end)
end)

--========================================================
-- PART 5: MAP WATCHER
--========================================================

task.spawn(function()
    while task.wait(2) do
        local active = IsMatchActive()
        local mapRoot = GetCurrentMapRoot()

        if not active or not mapRoot then
            CurrentMapActive = false
            CurrentMapReference = nil
            continue
        end

        if mapRoot ~= CurrentMapReference then
            CurrentMapReference = mapRoot
            CurrentMapActive = true

            print(
                "[NIGHTSAKEN] Nuevo mapa detectado:",
                mapRoot.Name
            )

            ProcessMapRemovers(mapRoot)
        elseif CurrentMapActive then
            -- No vuelve a escanear el mapa.
            -- Solo espera objetos nuevos mediante DescendantAdded.
        end
    end
end)

--========================================================
-- PART 5: INITIAL LOAD
--========================================================

task.defer(function()
    if Settings.LowGraphics then
        SetLowGraphics(true)
    end

    if Settings.ExtremelyLow then
        SetExtremelyLow(true)
    end

    if Settings.OptimizeLighting then
        SetOptimizeLighting(true)
    end

    -- Los removers no se ejecutan al cargar.
    -- Esperan la confirmación de una partida activa.

    Notify(
        "NIGHTSAKEN v0.3",
        "Sistema cargado. Esperando partida."
    )
end)

--========================================================
-- STARTUP
--========================================================

print("========================================")
print("NIGHTSAKEN v0.3")
print("FORSAKEN MOBILE OPTIMIZER")
print("LOADED")
print("========================================")

Notify(
    "NIGHTSAKEN v0.3",
    "Optimizer cargado correctamente"
)
