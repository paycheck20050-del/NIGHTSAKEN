--========================================================
-- NIGHTSAKEN v0.5
-- FORSAKEN MOBILE OPTIMIZER
-- UI: WINDUI 1.6.66
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
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

--========================================================
-- CONFIGURATION
--========================================================

local SCRIPT_VERSION = "0.5"
local CONFIG_FILE = "NIGHTSAKEN_V05.json"

local WINDUI_VERSION = "1.6.66"

local WINDUI_URL =
    "https://github.com/Footagesus/WindUI/releases/download/"
    .. WINDUI_VERSION .. "/main.lua"

local Settings = {
    LowGraphics = false,
    ExtremelyLow = false,
    OptimizeLighting = false,
    RemoveVegetation = false,
    RemoveDecoration = false,
    OptimizeOutro = true
}

local Palette = {
    Color3.fromHex("#777C72"),
    Color3.fromHex("#A6A49A"),
    Color3.fromHex("#89939B"),
    Color3.fromHex("#66717D")
}

local BatchSize = 150
local NewObjectBatchSize = 50

local WindUI = nil
local Window = nil

--========================================================
-- MAIN STATES
--========================================================

local JobQueue = {}
local JobRunning = false

local PendingObjects = {}
local PendingSet = setmetatable({}, {__mode = "k"})
local BufferScheduled = false

local GraphicsOriginal =
    setmetatable({}, {__mode = "k"})

local RemoverOriginal =
    setmetatable({}, {__mode = "k"})

local ProtectedCache =
    setmetatable({}, {__mode = "k"})

local NewObjectProcessed =
    setmetatable({}, {__mode = "k"})

local CurrentSession = {
    MapInstance = nil,
    VegetationDone = false,
    DecorationDone = false,
    Cancelled = false
}

local LobbySession = {
    Root = nil,
    VegetationDone = false,
    DecorationDone = false
}

local LobbyOptimized = false
local IsPaused = false
local IsMatch = false

local ActiveThemeColor = Palette[1]

local ActiveCamera = nil
local CameraConnection = nil
local CameraReplacementConnection = nil
local MapConnection = nil

local LightingOriginal = nil
local LightingEffectOriginal =
    setmetatable({}, {__mode = "k"})

local TerrainDecorationOriginal = nil

--========================================================
-- FORWARD DECLARATIONS
--========================================================

local EnqueueJob
local ProcessCurrentMap
local RefreshMatchState
local ResetMapMemory
local ScheduleBuffer
local RequestRemoverProcessing
local SetEnginePaused
local ApplyGraphics
local RestoreGraphics
local RestoreLighting
local RestoreRemoverObjects

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
            return HttpService:JSONDecode(
                readfile(CONFIG_FILE)
            )
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
        writefile(
            CONFIG_FILE,
            HttpService:JSONEncode(Settings)
        )
    end)
end

LoadSettings()

--========================================================
-- NOTIFICATIONS
--========================================================

local function Notify(title, message)
    if not WindUI then
        print(
            "[NIGHTSAKEN] "
            .. tostring(message)
        )
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
-- KEYWORDS
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

--========================================================
-- PROTECTION SYSTEM
--========================================================

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

local function GetModelAncestor(object)
    if not object then
        return nil
    end

    if object:IsA("Model") then
        return object
    end

    return object:FindFirstAncestorWhichIsA("Model")
end

-- Recursive interaction checks happen once per Model.
local function HasInteraction(model)
    if not model or not model:IsA("Model") then
        return false
    end

    for _, item in ipairs(model:GetDescendants()) do
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

local function InvalidateProtectionCache(object)
    local current = object

    while current and current ~= Workspace do
        if current:IsA("Model") then
            ProtectedCache[current] = nil
        end

        current = current.Parent
    end
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

    local model = GetModelAncestor(object)

    if model and ProtectedCache[model] ~= nil then
        if ProtectedCache[model] then
            return true
        end

        -- The model was already checked.
        -- Still check the individual object's name below.
    elseif model then
        local protectedModel = false

        if ContainsKeyword(
            model.Name,
            ProtectedKeywords
        ) then
            protectedModel = true
        elseif model:FindFirstChildOfClass("Humanoid") then
            protectedModel = true
        elseif HasInteraction(model) then
            protectedModel = true
        end

        ProtectedCache[model] = protectedModel

        if protectedModel then
            return true
        end
    end

    local current = object

    while current and current ~= Workspace do
        if ContainsKeyword(
            current.Name,
            ProtectedKeywords
        ) then
            if model then
                ProtectedCache[model] = true
            end

            return true
        end

        current = current.Parent
    end

    return false
end

print("[NIGHTSAKEN] Part 1 loaded")--========================================================
-- PART 2: GRAPHICS OPTIMIZER
--========================================================

--========================================================
-- MAP COLOR SELECTOR
--========================================================

local function GetMapThemeColor()
    local ambient = Lighting.OutdoorAmbient

    local brightness = (
        ambient.R +
        ambient.G +
        ambient.B
    ) / 3

    if brightness > 0.5 then
        return Palette[2]

    elseif brightness > 0.3 then
        return Palette[1]

    elseif brightness > 0.15 then
        return Palette[3]

    else
        return Palette[4]
    end
end

local function GetFloorColor(color)
    return color:Lerp(
        Color3.new(0, 0, 0),
        0.10
    )
end

--========================================================
-- ORIGINAL GRAPHICS
--========================================================

local function SaveGraphicsOriginal(object)
    if GraphicsOriginal[object] then
        return GraphicsOriginal[object]
    end

    local state = {}

    if object:IsA("BasePart") then
        state.Material = object.Material
        state.Color = object.Color
        state.CastShadow = object.CastShadow
        state.Reflectance = object.Reflectance

    elseif object:IsA("Decal")
        or object:IsA("Texture") then

        state.Transparency = object.Transparency

    elseif object:IsA("ParticleEmitter")
        or object:IsA("Trail")
        or object:IsA("Beam")
        or object:IsA("Smoke")
        or object:IsA("Fire")
        or object:IsA("Sparkles") then

        state.Enabled = object.Enabled
    end

    GraphicsOriginal[object] = state

    return state
end

--========================================================
-- GRAPHICS PROCESSING
--========================================================

local function OptimizeObject(object)
    if not object or not object.Parent then
        return
    end

    pcall(function()
        if object:IsA("BasePart") then
            SaveGraphicsOriginal(object)

            if Settings.LowGraphics
                or Settings.ExtremelyLow then

                object.Material = Enum.Material.SmoothPlastic
                object.CastShadow = false
                object.Reflectance = 0
            end

            if Settings.ExtremelyLow then
                local selectedColor = ActiveThemeColor

                if object.CFrame.UpVector.Y > 0.85 then
                    selectedColor = GetFloorColor(
                        ActiveThemeColor
                    )
                end

                object.Color = selectedColor
            end

        elseif object:IsA("Decal")
            or object:IsA("Texture") then

            if Settings.LowGraphics
                or Settings.ExtremelyLow then

                SaveGraphicsOriginal(object)
                object.Transparency = 1
            end

        elseif object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles") then

            if Settings.LowGraphics
                or Settings.ExtremelyLow then

                SaveGraphicsOriginal(object)
                object.Enabled = false
            end
        end
    end)
end

--========================================================
-- RESTORE GRAPHICS
--========================================================

RestoreGraphics = function()
    for object, state in pairs(GraphicsOriginal) do
        if object and object.Parent then
            pcall(function()
                if object:IsA("BasePart") then
                    if state.Material then
                        object.Material = state.Material
                    end

                    if state.Color then
                        object.Color = state.Color
                    end

                    if state.CastShadow ~= nil then
                        object.CastShadow = state.CastShadow
                    end

                    if state.Reflectance ~= nil then
                        object.Reflectance = state.Reflectance
                    end

                elseif object:IsA("Decal")
                    or object:IsA("Texture") then

                    object.Transparency = state.Transparency

                elseif state.Enabled ~= nil then
                    object.Enabled = state.Enabled
                end
            end)
        end

        GraphicsOriginal[object] = nil
    end
end

--========================================================
-- GRAPHICS SCAN
--========================================================

local function ProcessGraphicsScan()
    local objects = Workspace:GetDescendants()
    local processed = 0

    if Settings.ExtremelyLow then
        ActiveThemeColor = GetMapThemeColor()
    end

    for _, object in ipairs(objects) do
        while IsPaused do
            task.wait()
        end

        if not Settings.LowGraphics
            and not Settings.ExtremelyLow then
            break
        end

        OptimizeObject(object)

        processed = processed + 1

        if processed % BatchSize == 0 then
            task.wait()
        end
    end

    return processed
end

--========================================================
-- GRAPHICS CALLBACK
--========================================================

ApplyGraphics = function()
    if not Settings.LowGraphics
        and not Settings.ExtremelyLow then

        RestoreGraphics()
        return
    end

    EnqueueJob("Graphics Optimizer", function()
        local count = ProcessGraphicsScan()

        Notify(
            "Graphics Optimizer",
            tostring(count) .. " objects processed"
        )
    end)
end

local function SetLowGraphics(enabled)
    Settings.LowGraphics = enabled
    SaveSettings()
    ApplyGraphics()
end

local function SetExtremelyLow(enabled)
    Settings.ExtremelyLow = enabled
    SaveSettings()
    ApplyGraphics()
end

--========================================================
-- LIGHTING OPTIMIZER
--========================================================

local function SaveLightingEffect(effect)
    if LightingEffectOriginal[effect] ~= nil then
        return
    end

    if effect:IsA("PostEffect") then
        LightingEffectOriginal[effect] = {
            Type = "PostEffect",
            Enabled = effect.Enabled
        }

    elseif effect:IsA("Atmosphere") then
        LightingEffectOriginal[effect] = {
            Type = "Atmosphere",
            Density = effect.Density,
            Haze = effect.Haze,
            Glare = effect.Glare
        }
    end
end

local function OptimizeOneLightingEffect(effect)
    if effect:IsA("PostEffect") then
        SaveLightingEffect(effect)
        effect.Enabled = false

    elseif effect:IsA("Atmosphere") then
        SaveLightingEffect(effect)

        effect.Density = 0
        effect.Haze = 0
        effect.Glare = 0
    end
end

local function OptimizeLighting()
    if not LightingOriginal then
        LightingOriginal = {
            GlobalShadows = Lighting.GlobalShadows,
            FogEnd = Lighting.FogEnd,
            Brightness = Lighting.Brightness
        }
    end

    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Brightness = 2

        local effects = Lighting:GetDescendants()

        for index, effect in ipairs(effects) do
            OptimizeOneLightingEffect(effect)

            if index % BatchSize == 0 then
                task.wait()
            end
        end

        if Terrain then
            Terrain.Decoration = false
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
        end
    end)
end

RestoreLighting = function()
    if LightingOriginal then
        pcall(function()
            Lighting.GlobalShadows =
                LightingOriginal.GlobalShadows

            Lighting.FogEnd =
                LightingOriginal.FogEnd

            Lighting.Brightness =
                LightingOriginal.Brightness
        end)

        LightingOriginal = nil
    end

    for effect, state in pairs(LightingEffectOriginal) do
        if effect and effect.Parent then
            pcall(function()
                if state.Type == "PostEffect" then
                    effect.Enabled = state.Enabled

                elseif state.Type == "Atmosphere" then
                    effect.Density = state.Density
                    effect.Haze = state.Haze
                    effect.Glare = state.Glare
                end
            end)
        end

        LightingEffectOriginal[effect] = nil
    end
end

local function SetOptimizeLighting(enabled)
    Settings.OptimizeLighting = enabled
    SaveSettings()

    if enabled then
        EnqueueJob(
            "Optimize Lighting",
            OptimizeLighting
        )
    else
        RestoreLighting()
    end
end

print("[NIGHTSAKEN] Part 2 loaded")--========================================================
-- PART 3: REWORKED REMOVER ENGINE
--========================================================

--========================================================
-- TERRAIN DECORATION
--========================================================

local function DisableTerrainDecoration()
    if not Terrain then
        return
    end

    if TerrainDecorationOriginal == nil then
        TerrainDecorationOriginal = Terrain.Decoration
    end

    pcall(function()
        Terrain.Decoration = false
    end)
end

local function RestoreTerrainDecoration()
    if not Terrain or TerrainDecorationOriginal == nil then
        return
    end

    pcall(function()
        Terrain.Decoration = TerrainDecorationOriginal
    end)

    TerrainDecorationOriginal = nil
end

--========================================================
-- ORIGINAL REMOVER STATE
--========================================================

local function SaveRemoverOriginal(object)
    if RemoverOriginal[object] then
        return RemoverOriginal[object]
    end

    local state = {}

    if object:IsA("BasePart") then
        state.Transparency = object.Transparency
        state.CastShadow = object.CastShadow

    elseif object:IsA("Decal")
        or object:IsA("Texture") then

        state.Transparency = object.Transparency
    end

    RemoverOriginal[object] = state

    return state
end

--========================================================
-- HIDE VEGETATION
--========================================================

local function HideVisualObject(object)
    if not object or not object.Parent then
        return false
    end

    if IsProtected(object) then
        return false
    end

    local parts = {}
    local visuals = {}

    if object:IsA("BasePart") then
        table.insert(parts, object)

    elseif object:IsA("Model") then
        for _, item in ipairs(object:GetDescendants()) do
            if item:IsA("BasePart") then
                table.insert(parts, item)

            elseif item:IsA("Decal")
                or item:IsA("Texture") then

                table.insert(visuals, item)
            end
        end
    else
        return false
    end

    if #parts == 0 then
        return false
    end

    -- Preserve CanCollide and all physical properties.
    for index, part in ipairs(parts) do
        if part.Parent then
            pcall(function()
                SaveRemoverOriginal(part)

                part.Transparency = 1
                part.CastShadow = false
            end)
        end

        if index % BatchSize == 0 then
            task.wait()
        end
    end

    for _, visual in ipairs(visuals) do
        if visual.Parent then
            pcall(function()
                SaveRemoverOriginal(visual)
                visual.Transparency = 1
            end)
        end
    end

    return true
end

--========================================================
-- REMOVE DECORATION
--========================================================

local function DestroyDecoration(object)
    if not object or not object.Parent then
        return false
    end

    if IsProtected(object) then
        return false
    end

    if not (
        object:IsA("Model")
        or object:IsA("BasePart")
    ) then
        return false
    end

    -- The interaction check has already been performed
    -- by the protection system at Model level.
    local success = pcall(function()
        object:Destroy()
    end)

    return success
end

--========================================================
-- RESTORE HIDDEN OBJECTS
--========================================================

RestoreRemoverObjects = function()
    for object, state in pairs(RemoverOriginal) do
        if object and object.Parent then
            pcall(function()
                if state.Transparency ~= nil then
                    object.Transparency = state.Transparency
                end

                if object:IsA("BasePart")
                    and state.CastShadow ~= nil then

                    object.CastShadow = state.CastShadow
                end
            end)
        end

        RemoverOriginal[object] = nil
    end

    RestoreTerrainDecoration()
end

--========================================================
-- OBJECT CLASSIFICATION
--========================================================

local function GetRemoverCategory(object)
    if not object or not object.Parent then
        return nil
    end

    if not (
        object:IsA("Model")
        or object:IsA("BasePart")
    ) then
        return nil
    end

    if IsProtected(object) then
        return nil
    end

    if ContainsKeyword(
        object.Name,
        VegetationKeywords
    ) then
        return "Vegetation"
    end

    if ContainsKeyword(
        object.Name,
        DecorationKeywords
    ) then
        return "Decoration"
    end

    return nil
end

--========================================================
-- SHARED SCAN
--========================================================

local function HasSelectedAncestor(object, root, selected)
    local parent = object.Parent

    while parent and parent ~= root do
        if selected[parent] then
            return true
        end

        parent = parent.Parent
    end

    return false
end

local function ProcessRemoverScan(
    root,
    removeVegetation,
    removeDecoration
)
    if not root or not root.Parent then
        return 0, 0
    end

    if removeVegetation then
        DisableTerrainDecoration()
    end

    local objects = root:GetDescendants()

    local selected = {}
    local candidates = {}

    local scanned = 0

    -- One scan for both systems.
    for _, object in ipairs(objects) do
        while IsPaused do
            task.wait()
        end

        local category = GetRemoverCategory(object)

        local enabled =
            (category == "Vegetation" and removeVegetation)
            or
            (category == "Decoration" and removeDecoration)

        if enabled then
            selected[object] = category
        end

        scanned = scanned + 1

        if scanned % BatchSize == 0 then
            task.wait()
        end
    end

    -- Keep only outermost candidates.
    for object, category in pairs(selected) do
        if not HasSelectedAncestor(
            object,
            root,
            selected
        ) then
            table.insert(candidates, {
                Object = object,
                Category = category
            })
        end
    end

    local vegetationCount = 0
    local decorationCount = 0

    -- Apply the two different behaviors.
    for index, entry in ipairs(candidates) do
        while IsPaused do
            task.wait()
        end

        local object = entry.Object
        local category = entry.Category

        if object.Parent and not IsProtected(object) then
            if category == "Vegetation"
                and removeVegetation then

                if HideVisualObject(object) then
                    vegetationCount = vegetationCount + 1
                end

            elseif category == "Decoration"
                and removeDecoration then

                if DestroyDecoration(object) then
                    decorationCount = decorationCount + 1
                end
            end
        end

        if index % 10 == 0 then
            task.wait()
        end
    end

    return vegetationCount, decorationCount
end

--========================================================
-- SESSION MEMORY
--========================================================

ResetMapMemory = function()
    if CurrentSession then
        CurrentSession.Cancelled = true
    end

    if MapConnection then
        MapConnection:Disconnect()
        MapConnection = nil
    end

    CurrentSession = {
        MapInstance = nil,
        VegetationDone = false,
        DecorationDone = false,
        Cancelled = false
    }

    -- Discard references from the previous map.
    ProtectedCache = setmetatable({}, {__mode = "k"})
    NewObjectProcessed = setmetatable({}, {__mode = "k"})

    table.clear(PendingObjects)
    PendingSet = setmetatable({}, {__mode = "k"})

    print("[NIGHTSAKEN] Map session cleared")
end

local function IsCurrentSession(session)
    return session ~= nil
        and session == CurrentSession
        and not session.Cancelled
        and session.MapInstance ~= nil
        and session.MapInstance.Parent ~= nil
end

print("[NIGHTSAKEN] Part 3 loaded")--========================================================
-- PART 4: WINDUI LOADER
--========================================================

local fetchSuccess, source = pcall(function()
    return game:HttpGet(WINDUI_URL)
end)

if not fetchSuccess
    or type(source) ~= "string"
    or #source < 1000 then

    warn("[NIGHTSAKEN] WindUI download failed")
    return
end

local compileSuccess, compiled = pcall(function()
    return loadstring(source)
end)

if not compileSuccess or type(compiled) ~= "function" then
    warn("[NIGHTSAKEN] WindUI compile failed")
    return
end

local loadSuccess, loadedWindUI = pcall(compiled)

if not loadSuccess or type(loadedWindUI) ~= "table" then
    warn("[NIGHTSAKEN] WindUI initialization failed")
    return
end

WindUI = loadedWindUI

--========================================================
-- WINDOW
--========================================================

local windowSuccess, createdWindow = pcall(function()
    return WindUI:CreateWindow({
        Title = "NIGHTSAKEN",
        Author = "Forsaken Optimizer",
        Icon = "moon",
        Folder = "NIGHTSAKEN_v05",
        Theme = "Dark",
        Size = UDim2.fromOffset(420, 450),
        MinSize = Vector2.new(300, 350),
        Resizable = true,
        SideBarWidth = 150,
        HideSearchBar = false
    })
end)

if not windowSuccess or not createdWindow then
    warn("[NIGHTSAKEN] Window creation failed")
    return
end

Window = createdWindow

pcall(function()
    Window:Tag({
        Title = "v0.5",
        Color = Color3.fromHex("#89939B")
    })
end)

--========================================================
-- UPDATES HISTORY
--========================================================

local Updates = {
    {
        Version = "v0.5",
        Changes =
            "• Rebuilt vegetation and decoration systems.\n" ..
            "• Shared world scanner.\n" ..
            "• Four-lock match validation.\n" ..
            "• Model-level interaction cache.\n" ..
            "• Lobby and match processing.\n" ..
            "• Improved cutscene pause handling.\n" ..
            "• Updated memory cleanup.\n" ..
            "• Automatic NEW labels for menu options."
    },

    {
        Version = "v0.4",
        Changes =
            "• NIGHTSAKEN Rework.\n" ..
            "• Automatic updates history.\n" ..
            "• Adaptive four-color system.\n" ..
            "• Shared remover scan prototype.\n" ..
            "• Object buffer prototype.\n" ..
            "• Camera-based cutscene pause system."
    },

    {
        Version = "v0.3",
        Changes =
            "• Graphics optimizer.\n" ..
            "• JobQueue processing.\n" ..
            "• Initial map detection.\n" ..
            "• Vegetation and decoration systems."
    },

    {
        Version = "v0.2",
        Changes =
            "• Lighting and shadow optimization.\n" ..
            "• Configuration saved in JSON."
    },

    {
        Version = "v0.1",
        Changes =
            "• Initial NIGHTSAKEN release."
    }
}

--========================================================
-- TABS
--========================================================

local tabsSuccess, tabs = pcall(function()
    local result = {}

    result.Updates = Window:Tab({
        Title = "Updates",
        Icon = "bell"
    })

    result.Main = Window:Tab({
        Title = "Optimizer",
        Icon = "zap"
    })

    result.Remover = Window:Tab({
        Title = "Remover",
        Icon = "eye-off"
    })

    result.Settings = Window:Tab({
        Title = "Settings",
        Icon = "settings"
    })

    result.Info = Window:Tab({
        Title = "Info",
        Icon = "info"
    })

    return result
end)

if not tabsSuccess or not tabs then
    warn("[NIGHTSAKEN] Tab creation failed")
    return
end

local UpdatesTab = tabs.Updates
local MainTab = tabs.Main
local RemoverTab = tabs.Remover
local SettingsTab = tabs.Settings
local InfoTab = tabs.Info

--========================================================
-- UPDATE SECTIONS
--========================================================

for index, update in ipairs(Updates) do
    local isNew = index == 1

    local section = UpdatesTab:Section({
        Title = (isNew and "[NEW] " or "[OLD] ")
            .. "Version " .. update.Version,

        Opened = isNew
    })

    section:Paragraph({
        Title = "What's New - " .. update.Version,
        Desc = update.Changes
    })
end

--========================================================
-- GRAPHICS CALLBACKS
--========================================================

-- ApplyGraphics is defined in Part 2.

--========================================================
-- REMOVER CALLBACKS
--========================================================

local function SetRemoveVegetation(enabled)
    Settings.RemoveVegetation = enabled
    SaveSettings()

    if not enabled then
        if not Settings.RemoveDecoration then
            RestoreRemoverObjects()
        else
            RestoreTerrainDecoration()
        end

        return
    end

    RequestRemoverProcessing()
end

local function SetRemoveDecoration(enabled)
    Settings.RemoveDecoration = enabled
    SaveSettings()

    if not enabled then
        return
    end

    RequestRemoverProcessing()
end

--========================================================
-- MAIN TAB
--========================================================

MainTab:Section({
    Title = "Graphics Optimizer",
    Opened = true
})

MainTab:Toggle({
    Title = "[NEW] Low Graphics",
    Desc = "Simplifies materials while preserving original colors",
    Value = Settings.LowGraphics,
    Callback = SetLowGraphics
})

MainTab:Toggle({
    Title = "[NEW] Extremely Low Graphics",
    Desc = "Uses one adaptive color for the active map",
    Value = Settings.ExtremelyLow,
    Callback = SetExtremelyLow
})

MainTab:Toggle({
    Title = "[NEW] Optimize Lighting",
    Desc = "Reduces global lighting effects",
    Value = Settings.OptimizeLighting,
    Callback = SetOptimizeLighting
})

--========================================================
-- REMOVER TAB
--========================================================

RemoverTab:Section({
    Title = "World Remover",
    Opened = true
})

RemoverTab:Toggle({
    Title = "[NEW] Vegetation Remover",
    Desc = "Hides vegetation while preserving collisions",
    Value = Settings.RemoveVegetation,
    Callback = SetRemoveVegetation
})

RemoverTab:Toggle({
    Title = "[NEW] Decoration Remover",
    Desc = "Destroys safe decorative objects",
    Value = Settings.RemoveDecoration,
    Callback = SetRemoveDecoration
})

--========================================================
-- SETTINGS TAB
--========================================================

SettingsTab:Section({
    Title = "Configuration",
    Opened = true
})

SettingsTab:Button({
    Title = "[NEW] Save Settings",
    Desc = "Save the current configuration",
    Callback = function()
        SaveSettings()
        Notify("NIGHTSAKEN", "Settings saved")
    end
})

SettingsTab:Button({
    Title = "[NEW] Restore Hidden Objects",
    Desc = "Restore objects hidden by the vegetation remover",
    Callback = function()
        RestoreRemoverObjects()

        Notify(
            "NIGHTSAKEN",
            "Hidden objects restored"
        )
    end
})

--========================================================
-- INFO TAB
--========================================================

InfoTab:Section({
    Title = "NIGHTSAKEN v0.5",
    Opened = true
})

InfoTab:Paragraph({
    Title = "Forsaken Mobile Optimizer",
    Desc = "A mobile optimization engine focused on reducing unnecessary visual processing."
})

InfoTab:Paragraph({
    Title = "Graphics Engine",
    Desc = "Low Graphics simplifies materials. Extremely Low Graphics applies one adaptive map color."
})

InfoTab:Paragraph({
    Title = "World Remover",
    Desc = "Vegetation is hidden. Safe decorative objects are destroyed after protection checks."
})

InfoTab:Paragraph({
    Title = "Match Detection",
    Desc = "Uses map, player, match marker and team checks before starting a match scan."
})

InfoTab:Paragraph({
    Title = "Memory",
    Desc = "Uses temporary caches for the current map and disconnects the old map event."
})

print("[NIGHTSAKEN] Part 4 loaded")--========================================================
-- PART 5: JOB QUEUE
--========================================================

local ResumeSignal = Instance.new("BindableEvent")

local function StartJobWorker()
    if JobRunning then
        return
    end

    JobRunning = true

    task.spawn(function()
        while #JobQueue > 0 do
            while IsPaused do
                ResumeSignal.Event:Wait()
            end

            local job = table.remove(JobQueue, 1)

            if job and type(job.Callback) == "function" then
                local success, err = xpcall(
                    job.Callback,
                    function(message)
                        return tostring(message)
                    end
                )

                if not success then
                    warn(
                        "[NIGHTSAKEN] Job error "
                        .. tostring(job.Name)
                        .. ": "
                        .. tostring(err)
                    )
                end
            end

            task.wait()
        end

        JobRunning = false

        -- Prevent the worker restart race.
        if #JobQueue > 0 then
            StartJobWorker()
        end
    end)
end

EnqueueJob = function(name, callback)
    if type(callback) ~= "function" then
        return
    end

    table.insert(JobQueue, {
        Name = name,
        Callback = callback
    })

    StartJobWorker()
end

--========================================================
-- PART 5: PAUSE SYSTEM
--========================================================

SetEnginePaused = function(paused)
    if IsPaused == paused then
        return
    end

    IsPaused = paused

    if not paused then
        ResumeSignal:Fire()

        if #PendingObjects > 0 then
            ScheduleBuffer()
        end

        print("[NIGHTSAKEN] Engine resumed")
    else
        print("[NIGHTSAKEN] Engine paused")
    end
end

--========================================================
-- PART 5: MAP DETECTION
--========================================================

local MapNames = {
    "map",
    "currentmap",
    "activemap",
    "mapfolder",
    "gamemap",
    "current_map",
    "active_map"
}

local LobbyNames = {
    "lobby",
    "mainlobby",
    "waitingroom",
    "intermission",
    "menu"
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

    if value and value:IsA("BoolValue") then
        return value.Value
    end

    return nil
end

local function GetMatchMarker()
    for _, marker in ipairs(MatchMarkers) do
        local value = GetMarkerValue(
            Workspace,
            marker
        )

        if value ~= nil then
            return value
        end

        value = GetMarkerValue(
            Player,
            marker
        )

        if value ~= nil then
            return value
        end
    end

    return nil
end

local function GetCurrentMapRoot()
    for _, child in ipairs(Workspace:GetChildren()) do
        if ContainsKeyword(child.Name, MapNames) then
            return child
        end
    end

    return nil
end

local function GetLobbyRoot()
    for _, child in ipairs(Workspace:GetChildren()) do
        if ContainsKeyword(child.Name, LobbyNames) then
            return child
        end
    end

    return nil
end

local function IsLobbyTeam()
    local team = Player.Team

    if not team then
        return true
    end

    local name = NormalizeName(team.Name)

    return name == "lobby"
        or name == "spectator"
        or name == "spectators"
        or name == "waiting"
end

--========================================================
-- FOUR MATCH LOCKS
--========================================================

local function IsMatchActive()
    local marker = GetMatchMarker()
    local mapRoot = GetCurrentMapRoot()

    -- Lock 1: match marker or valid team.
    if marker == false then
        return false
    end

    local teamConfirmsMatch =
        Player.Team ~= nil and not IsLobbyTeam()

    local markerConfirmsMatch = marker == true

    if not markerConfirmsMatch
        and not teamConfirmsMatch then
        return false
    end

    -- A map must exist.
    if not mapRoot then
        return false
    end

    return true
end

local function IsPlayerAlive()
    local character = Player.Character

    if not character then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    return true
end

local function IsMapReady(mapRoot)
    if not mapRoot or not mapRoot.Parent then
        return false
    end

    return #mapRoot:GetChildren() > 0
end

--========================================================
-- MATCH SESSION
--========================================================

local function StartMapSession(mapRoot)
    if not mapRoot or not mapRoot.Parent then
        return
    end

    if CurrentSession.MapInstance == mapRoot then
        return
    end

    ResetMapMemory()

    CurrentSession.MapInstance = mapRoot

    print(
        "[NIGHTSAKEN] New match map:",
        mapRoot.Name
    )

    -- Disconnect automatically when the map disappears.
    MapConnection = mapRoot.AncestryChanged:Connect(
        function(_, parent)
            if not parent
                and CurrentSession.MapInstance == mapRoot then

                ResetMapMemory()
                IsMatch = false

                task.defer(function()
                    RefreshMatchState()
                end)
            end
        end
    )
end

local function TryStartMatch()
    if IsPaused then
        return false
    end

    -- Lock 1: confirmed match.
    if not IsMatchActive() then
        return false
    end

    local mapRoot = GetCurrentMapRoot()

    if not mapRoot then
        return false
    end

    -- Lock 2: map must be different.
    if mapRoot == CurrentSession.MapInstance then
        return false
    end

    -- Lock 3: map must have loaded objects.
    if not IsMapReady(mapRoot) then
        return false
    end

    -- Lock 4: player must be alive.
    if not IsPlayerAlive() then
        return false
    end

    StartMapSession(mapRoot)

    IsMatch = true

    ProcessCurrentMap()

    return true
end

--========================================================
-- SHARED ROOT PROCESSOR
--========================================================

local function QueueRemoverScan(root, state, isMatchSession)
    if not root or not root.Parent then
        return
    end

    local removeVegetation =
        Settings.RemoveVegetation
        and not state.VegetationDone

    local removeDecoration =
        Settings.RemoveDecoration
        and not state.DecorationDone

    if not removeVegetation and not removeDecoration then
        return
    end

    local sessionReference = state

    -- Mark the requested work as scheduled.
    if removeVegetation then
        state.VegetationDone = true
    end

    if removeDecoration then
        state.DecorationDone = true
    end

    EnqueueJob(
        isMatchSession and "Match Remover Scan"
            or "Lobby Remover Scan",

        function()
            if not root or not root.Parent then
                return
            end

            if isMatchSession then
                if not IsCurrentSession(sessionReference) then
                    return
                end
            elseif LobbySession ~= sessionReference then
                return
            end

            while IsPaused do
                task.wait()
            end

            local vegetationCount, decorationCount =
                ProcessRemoverScan(
                    root,
                    removeVegetation,
                    removeDecoration
                )

            Notify(
                "NIGHTSAKEN Remover",
                "Vegetation: "
                    .. tostring(vegetationCount)
                    .. " | Decoration: "
                    .. tostring(decorationCount)
            )
        end
    )
end

--========================================================
-- PROCESS CURRENT MAP
--========================================================

ProcessCurrentMap = function()
    local mapRoot = CurrentSession.MapInstance

    if not mapRoot or not mapRoot.Parent then
        return
    end

    if not IsMatchActive() then
        return
    end

    if not IsPlayerAlive() then
        return
    end

    QueueRemoverScan(
        mapRoot,
        CurrentSession,
        true
    )
end

--========================================================
-- LOBBY PROCESSING
--========================================================

local function ProcessLobbyOnce()
    if IsMatch then
        return
    end

    local lobbyRoot = GetLobbyRoot()

    if not lobbyRoot then
        return
    end

    if LobbySession.Root ~= lobbyRoot then
        LobbySession = {
            Root = lobbyRoot,
            VegetationDone = false,
            DecorationDone = false
        }

        LobbyOptimized = false
    end

    QueueRemoverScan(
        lobbyRoot,
        LobbySession,
        false
    )

    if (
        not Settings.RemoveVegetation
        or LobbySession.VegetationDone
    ) and (
        not Settings.RemoveDecoration
        or LobbySession.DecorationDone
    ) then
        LobbyOptimized = true
    end
end

--========================================================
-- REQUEST REMOVER PROCESSING
--========================================================

RequestRemoverProcessing = function()
    if not Settings.RemoveVegetation
        and not Settings.RemoveDecoration then
        return
    end

    if IsMatch and CurrentSession.MapInstance then
        ProcessCurrentMap()
    else
        ProcessLobbyOnce()
    end
end

--========================================================
-- MATCH STATE REFRESH
--========================================================

RefreshMatchState = function()
    local active = IsMatchActive()

    if not active then
        IsMatch = false

        if CurrentSession.MapInstance then
            ResetMapMemory()
        end

        ProcessLobbyOnce()
        return
    end

    local mapRoot = GetCurrentMapRoot()

    if not mapRoot then
        return
    end

    if mapRoot ~= CurrentSession.MapInstance then
        TryStartMatch()
        return
    end

    IsMatch = true

    if Settings.RemoveVegetation
        or Settings.RemoveDecoration then

        ProcessCurrentMap()
    end
end

--========================================================
-- PART 5: CAMERA DETECTION
--========================================================

local function OnCameraTypeChanged()
    if not ActiveCamera then
        SetEnginePaused(false)
        return
    end

    local scriptable =
        ActiveCamera.CameraType == Enum.CameraType.Scriptable

    if Settings.OptimizeOutro then
        SetEnginePaused(scriptable)
    else
        SetEnginePaused(false)
    end

    if not scriptable then
        task.defer(function()
            TryStartMatch()
            RefreshMatchState()
        end)
    end
end

local function BindCamera(camera)
    if CameraConnection then
        CameraConnection:Disconnect()
        CameraConnection = nil
    end

    ActiveCamera = camera

    if not camera then
        SetEnginePaused(false)
        return
    end

    CameraConnection =
        camera:GetPropertyChangedSignal("CameraType"):Connect(
            OnCameraTypeChanged
        )

    OnCameraTypeChanged()
end

BindCamera(Workspace.CurrentCamera)

CameraReplacementConnection =
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(
        function()
            BindCamera(Workspace.CurrentCamera)
        end
    )

--========================================================
-- PART 5: NEW OBJECT TARGETS
--========================================================

local function GetRemoverTarget(object, keywords)
    if not object or IsCollisionProxy(object) then
        return nil
    end

    local current = object

    while current and current ~= Workspace do
        if (
            current:IsA("Model")
            or current:IsA("BasePart")
        ) and ContainsKeyword(current.Name, keywords) then

            return current
        end

        current = current.Parent
    end

    return nil
end

local function ProcessNewObject(object)
    if not object or not object.Parent then
        return
    end

    if IsPaused then
        return
    end

    if IsCollisionProxy(object) then
        return
    end

    InvalidateProtectionCache(object)

    -- Graphics processing.
    if Settings.LowGraphics or Settings.ExtremelyLow then
        OptimizeObject(object)
    end

    if not IsMatch
        or not CurrentSession.MapInstance then
        return
    end

    local mapRoot = CurrentSession.MapInstance

    if not object:IsDescendantOf(mapRoot) then
        return
    end

    if Settings.RemoveVegetation then
        local target = GetRemoverTarget(
            object,
            VegetationKeywords
        )

        if target
            and not NewObjectProcessed[target]
            and not IsProtected(target) then

            NewObjectProcessed[target] = true
            HideVisualObject(target)
        end
    end

    if Settings.RemoveDecoration then
        local target = GetRemoverTarget(
            object,
            DecorationKeywords
        )

        if target
            and not NewObjectProcessed[target]
            and not IsProtected(target) then

            NewObjectProcessed[target] = true
            DestroyDecoration(target)
        end
    end
end

--========================================================
-- PART 5: OBJECT BUFFER
--========================================================

local function FlushBuffer()
    BufferScheduled = false

    if IsPaused then
        return
    end

    if #PendingObjects == 0 then
        return
    end

    local batch = PendingObjects

    PendingObjects = {}
    PendingSet = setmetatable({}, {__mode = "k"})

    EnqueueJob("New Objects Buffer", function()
        for index, object in ipairs(batch) do
            if IsPaused then
                for remaining = index, #batch do
                    local pending = batch[remaining]

                    if pending and pending.Parent
                        and not PendingSet[pending] then

                        PendingSet[pending] = true
                        table.insert(PendingObjects, pending)
                    end
                end

                ScheduleBuffer()
                return
            end

            if object and object.Parent then
                ProcessNewObject(object)
            end

            if index % NewObjectBatchSize == 0 then
                task.wait()
            end
        end
    end)
end

ScheduleBuffer = function()
    if BufferScheduled or IsPaused then
        return
    end

    if #PendingObjects == 0 then
        return
    end

    BufferScheduled = true

    task.delay(0.5, FlushBuffer)
end

local function AddPendingObject(object)
    if not object or PendingSet[object] then
        return
    end

    InvalidateProtectionCache(object)

    PendingSet[object] = true
    table.insert(PendingObjects, object)

    ScheduleBuffer()
end

--========================================================
-- PART 5: EVENT WATCHERS
--========================================================

local RefreshScheduled = false

local function ScheduleMatchRefresh()
    if RefreshScheduled then
        return
    end

    RefreshScheduled = true

    task.defer(function()
        RefreshScheduled = false

        RefreshMatchState()
    end)
end

Workspace.DescendantAdded:Connect(function(object)
    AddPendingObject(object)

    if object:IsA("BoolValue") then
        for _, marker in ipairs(MatchMarkers) do
            if object.Name == marker then
                object:GetPropertyChangedSignal("Value"):Connect(
                    ScheduleMatchRefresh
                )
            end
        end
    end

    ScheduleMatchRefresh()
end)

Workspace.ChildAdded:Connect(function()
    ScheduleMatchRefresh()
end)

Workspace.ChildRemoved:Connect(function(child)
    if child == CurrentSession.MapInstance then
        ResetMapMemory()
        IsMatch = false
    end

    ScheduleMatchRefresh()
end)

--========================================================
-- MATCH MARKER WATCHERS
--========================================================

for _, marker in ipairs(MatchMarkers) do
    Workspace:GetAttributeChangedSignal(marker):Connect(
        ScheduleMatchRefresh
    )

    Player:GetAttributeChangedSignal(marker):Connect(
        ScheduleMatchRefresh
    )
end

local function WatchExistingMarker(object)
    if not object:IsA("BoolValue") then
        return
    end

    for _, marker in ipairs(MatchMarkers) do
        if object.Name == marker then
            object:GetPropertyChangedSignal("Value"):Connect(
                ScheduleMatchRefresh
            )
        end
    end
end

for _, object in ipairs(Workspace:GetDescendants()) do
    WatchExistingMarker(object)
end

Player:GetPropertyChangedSignal("Team"):Connect(
    ScheduleMatchRefresh
)

Player.CharacterAdded:Connect(function()
    task.defer(function()
        ScheduleMatchRefresh()
    end)
end)

--========================================================
-- PART 5: STARTUP
--========================================================

task.defer(function()
    -- Initial graphics optimization.
    if Settings.LowGraphics
        or Settings.ExtremelyLow then

        ApplyGraphics()
    end

    -- Initial lighting optimization.
    if Settings.OptimizeLighting then
        EnqueueJob(
            "Initial Lighting",
            OptimizeLighting
        )
    end

    -- One initial lobby scan.
    if not IsMatchActive() then
        IsMatch = false
        ProcessLobbyOnce()
    end

    -- Check if a match is already active.
    RefreshMatchState()

    Notify(
        "NIGHTSAKEN v0.5",
        "Optimizer loaded successfully"
    )
end)

--========================================================
-- STARTUP COMPLETE
--========================================================

print("========================================")
print("NIGHTSAKEN v0.5")
print("FORSAKEN MOBILE OPTIMIZER")
print("WINDUI 1.6.66")
print("LOADED")
print("========================================")

Notify(
    "NIGHTSAKEN v0.5",
    "System initialized"
)