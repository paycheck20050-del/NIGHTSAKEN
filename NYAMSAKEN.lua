--==================================================
-- NIGHTSAKEN v0.0
-- Helio G88 | WindUI 1.6.66
-- REBUILT GRAPHICS ENGINE
--==================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- WINDUI
--==================================================

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"
))()

--==================================================
-- SETTINGS
--==================================================

local Settings = {
    LowGraphics = false,
    ExtremelyLowGraphics = false,
    RemoveVegetation = false,
    RemoveDecoration = false,
    InterfaceColor = Color3.fromHex("#8B5CF6")
}

--==================================================
-- COLORS
--==================================================

local COLORS = {
    GreenGray = Color3.fromHex("#777C72"),
    LightGray = Color3.fromHex("#A6A49A"),
    BlueGray = Color3.fromHex("#89939B"),
    DarkBlueGray = Color3.fromHex("#66717D")
}

local SelectedWallColor
local SelectedFloorColor

--==================================================
-- PERFORMANCE CONTROL
--==================================================

local GameplayStarted = false
local Processing = false
local ScanPending = false

local BATCH_SIZE = 40

-- Weak tables: no guardan copias de propiedades.
local ProcessedTextures = setmetatable({}, {__mode = "k"})
local ProcessedMeshes = setmetatable({}, {__mode = "k"})
local ProcessedSurfaces = setmetatable({}, {__mode = "k"})
local ProcessedParts = setmetatable({}, {__mode = "k"})
local HiddenVegetationParts = setmetatable({}, {__mode = "k"})
local HiddenDecorationParts = setmetatable({}, {__mode = "k"})

--==================================================
-- CHARACTER PROTECTION
--==================================================

local function IsCharacterPart(object)
    local ancestor = object

    while ancestor and ancestor ~= Workspace do
        if ancestor:IsA("Model")
            and ancestor:FindFirstChildOfClass("Humanoid") then
            return true
        end

        ancestor = ancestor.Parent
    end

    return false
end

--==================================================
-- TEXTURE ENGINE
--==================================================

local function ShouldHideTextures()
    return Settings.LowGraphics
        or Settings.ExtremelyLowGraphics
end

local function ProcessTexture(object)
    if not ShouldHideTextures() then
        return
    end

    if not object:IsA("Decal")
        and not object:IsA("Texture") then
        return
    end

    if ProcessedTextures[object] then
        return
    end

    ProcessedTextures[object] = true

    pcall(function()
        object.Transparency = 1
    end)

    -- Segundo método: elimina el enlace de imagen.
    pcall(function()
        object.Texture = ""
    end)
end

--==================================================
-- ADAPTIVE LIGHTING
--==================================================

local function GetMapLightingType()
    local ambient = Lighting.OutdoorAmbient

    local brightness = (
        ambient.R + ambient.G + ambient.B
    ) / 3

    if brightness >= 0.60 then
        return "Bright"
    elseif brightness >= 0.30 then
        return "Medium"
    end

    return "Dark"
end

local function IsFloor(object)
    return object:IsA("BasePart")
        and object.Size.Y < 4
        and (
            object.Size.X > 8
            or object.Size.Z > 8
        )
end

local function GetAdaptiveColors()
    local lightingType = GetMapLightingType()

    if lightingType == "Bright" then
        return COLORS.LightGray, COLORS.GreenGray

    elseif lightingType == "Medium" then
        return COLORS.BlueGray, COLORS.DarkBlueGray
    end

    return COLORS.BlueGray, COLORS.LightGray
end

--==================================================
-- MESH TEXTURE ENGINE
--==================================================

local function ProcessMeshTexture(object)
    if not Settings.ExtremelyLowGraphics then
        return
    end

    if ProcessedMeshes[object] then
        return
    end

    if object:IsA("MeshPart") then
        ProcessedMeshes[object] = true

        pcall(function()
            object.TextureID = ""
        end)

        pcall(function()
            object.Material = Enum.Material.SmoothPlastic
        end)

    elseif object:IsA("SpecialMesh") then
        ProcessedMeshes[object] = true

        pcall(function()
            object.TextureId = ""
        end)
    end
end

--==================================================
-- SURFACE APPEARANCE ENGINE
--==================================================

local function ProcessSurfaceAppearance(object)
    if not Settings.ExtremelyLowGraphics then
        return
    end

    if not object:IsA("SurfaceAppearance") then
        return
    end

    if ProcessedSurfaces[object] then
        return
    end

    ProcessedSurfaces[object] = true

    pcall(function()
        object:Destroy()
    end)
end

--==================================================
-- SMOOTH MATERIAL ENGINE
--==================================================

local function ProcessExtremelyLow(object)
    if not Settings.ExtremelyLowGraphics then
        return
    end

    if not object:IsA("BasePart") then
        return
    end

    if IsCharacterPart(object) then
        return
    end

    if ProcessedParts[object] then
        return
    end

    ProcessedParts[object] = true

    pcall(function()
        object.Material = Enum.Material.SmoothPlastic
        object.MaterialVariant = ""
        object.Reflectance = 0

        if IsFloor(object) then
            object.Color = SelectedFloorColor
        else
            object.Color = SelectedWallColor
        end
    end)
end--==================================================
-- REMOVER 🛡️
--==================================================

local VegetationNames = {
    "tree", "rock", "stone", "log", "grass",
    "flower", "bush", "foliage", "vegetation",
    "pasto", "cesped", "césped", "arbol", "árbol",
    "piedra", "tronco", "arbusto", "flores", "tierra"
}

local DecorationNames = {
    "chair", "furniture", "cushion", "pillow",
    "curtain", "table", "round", "mini chair",
    "box", "chest", "painting", "picture", "photo",
    "food", "food stand", "helmet", "straw", "closet",
    "lamp", "flowerpot", "pot", "drawer",
    "silla", "mueble", "cojin", "cojín", "cortina",
    "mesa", "pelota", "caja", "cofre", "cuadro",
    "foto", "comida", "casco", "paja", "clóset",
    "lampara", "lámpara", "maceta", "cajon", "cajón"
}

local function NormalizeName(name)
    name = string.lower(name)

    name = name:gsub("á", "a")
    name = name:gsub("é", "e")
    name = name:gsub("í", "i")
    name = name:gsub("ó", "o")
    name = name:gsub("ú", "u")
    name = name:gsub("ñ", "n")

    return name
end

local function NameMatches(object, names)
    local objectName = NormalizeName(object.Name)

    for _, keyword in ipairs(names) do
        if string.find(
            objectName,
            NormalizeName(keyword),
            1,
            true
        ) then
            return true
        end
    end

    return false
end

--==================================================
-- HIDE MATCHING PARTS
--==================================================

local function HidePart(object, cache)
    if not object:IsA("BasePart") then
        return
    end

    if IsCharacterPart(object) then
        return
    end

    if cache[object] then
        return
    end

    cache[object] = true

    pcall(function()
        object.Transparency = 1
    end)
end

local function HidePartsInside(object, cache)
    HidePart(object, cache)

    if not object:IsA("Model")
        and not object:IsA("Folder") then
        return
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        HidePart(descendant, cache)
    end
end

local function ProcessRemoverObject(object)
    if Settings.RemoveVegetation
        and NameMatches(object, VegetationNames) then

        HidePartsInside(object, HiddenVegetationParts)
    end

    if Settings.RemoveDecoration
        and NameMatches(object, DecorationNames) then

        HidePartsInside(object, HiddenDecorationParts)
    end
end

--==================================================
-- OBJECT PROCESSOR
--==================================================

local function ProcessObject(object)
    if not object or not object.Parent then
        return
    end

    if ShouldHideTextures() then
        ProcessTexture(object)
    end

    if Settings.ExtremelyLowGraphics then
        ProcessMeshTexture(object)
        ProcessSurfaceAppearance(object)
        ProcessExtremelyLow(object)
    end

    if Settings.RemoveVegetation
        or Settings.RemoveDecoration then
        ProcessRemoverObject(object)
    end
end

--==================================================
-- CONTROLLED SCANNER
--==================================================

local function ScanWorkspace()
    if not GameplayStarted then
        return
    end

    if not (
        ShouldHideTextures()
        or Settings.RemoveVegetation
        or Settings.RemoveDecoration
    ) then
        return
    end

    if Processing then
        ScanPending = true
        return
    end

    Processing = true

    task.spawn(function()
        repeat
            ScanPending = false

            if Settings.ExtremelyLowGraphics then
                SelectedWallColor, SelectedFloorColor =
                    GetAdaptiveColors()
            end

            local descendants = Workspace:GetDescendants()

            for index, object in ipairs(descendants) do
                ProcessObject(object)

                if index % BATCH_SIZE == 0 then
                    task.wait()
                end
            end

        until not ScanPending

        Processing = false
    end)
end

--==================================================
-- TOGGLE FUNCTIONS
--==================================================

local function SetLowGraphics(value)
    Settings.LowGraphics = value

    if value and GameplayStarted then
        ScanWorkspace()
    end
end

local function SetExtremelyLowGraphics(value)
    Settings.ExtremelyLowGraphics = value

    if value and GameplayStarted then
        SelectedWallColor, SelectedFloorColor =
            GetAdaptiveColors()

        ScanWorkspace()
    end
end

local function SetRemoveVegetation(value)
    Settings.RemoveVegetation = value

    if value and GameplayStarted then
        ScanWorkspace()
    end
end

local function SetRemoveDecoration(value)
    Settings.RemoveDecoration = value

    if value and GameplayStarted then
        ScanWorkspace()
    end
end

--==================================================
-- NEW OBJECT QUEUE
--==================================================

local NewObjectQueue = {}
local QueueRunning = false

local function AddNewObject(object)
    if not GameplayStarted then
        return
    end

    if not (
        ShouldHideTextures()
        or Settings.RemoveVegetation
        or Settings.RemoveDecoration
    ) then
        return
    end

    NewObjectQueue[#NewObjectQueue + 1] = object

    if QueueRunning then
        return
    end

    QueueRunning = true

    task.spawn(function()
        while #NewObjectQueue > 0 do
            local objectToProcess = table.remove(
                NewObjectQueue,
                1
            )

            if objectToProcess and objectToProcess.Parent then
                ProcessObject(objectToProcess)
            end

            task.wait()
        end

        QueueRunning = false
    end)
end

Workspace.DescendantAdded:Connect(AddNewObject)

--==================================================
-- GAMEPLAY START GATE
--==================================================

local function IsGameplayActive()
    local character = LocalPlayer.Character

    if not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local camera = Workspace.CurrentCamera

    if camera and camera.CameraType == Enum.CameraType.Scriptable then
        return false
    end

    if humanoid.WalkSpeed <= 0 then
        return false
    end

    return humanoid.MoveDirection.Magnitude >= 0.05
end

local function WaitForGameplay()
    local validTime = 0

    while not GameplayStarted do
        if IsGameplayActive() then
            validTime += 0.25
        else
            validTime = 0
        end

        if validTime >= 1.5 then
            GameplayStarted = true
            break
        end

        task.wait(0.25)
    end
end

--==================================================
-- CHARACTER RESPAWN PROTECTION
--==================================================

LocalPlayer.CharacterAdded:Connect(function()
    -- No se inicia otro escaneo durante la carga
    -- del personaje o una posible cinemática.
    task.wait(2)

    if GameplayStarted then
        ScanWorkspace()
    end
end)--==================================================
-- CUSTOM INTERFACE THEME
--==================================================

local function ApplyInterfaceColor(color)
    Settings.InterfaceColor = color

    WindUI:AddTheme({
        Name = "NIGHTSAKEN_CUSTOM",
        Accent = color,
        Background = Color3.fromHex("#101014"),
        Outline = Color3.fromHex("#35353D"),
        Text = Color3.fromHex("#F5F5F5"),
        Placeholder = Color3.fromHex("#999999"),
        Button = color,
        Icon = color
    })

    WindUI:SetTheme("NIGHTSAKEN_CUSTOM")
end

--==================================================
-- MAIN WINDOW
--==================================================

local Window = WindUI:CreateWindow({
    Title = "NIGHTSAKEN",
    Icon = "moon",
    Author = "Helio G88 Optimizer",
    Folder = "NIGHTSAKEN_V00",

    Size = UDim2.fromOffset(520, 580),
    MinSize = Vector2.new(320, 400),

    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 160,
    HideSearchBar = false
})

--==================================================
-- TABS
--==================================================

local UpdatesTab = Window:Tab({
    Title = "Updates",
    Icon = "bell"
})

local OptimizerTab = Window:Tab({
    Title = "Optimizer",
    Icon = "zap"
})

local RemoverTab = Window:Tab({
    Title = "Remover 🛡️",
    Icon = "shield"
})

local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings"
})

--==================================================
-- UPDATES
--==================================================

UpdatesTab:Paragraph({
    Title = "NIGHTSAKEN v0.0",
    Desc = "Rebuilt graphics engine for MediaTek Helio G88."
})

UpdatesTab:Paragraph({
    Title = "Texture Engine",
    Desc = "Double removal method for Decal and Texture images."
})

UpdatesTab:Paragraph({
    Title = "Extremely Low Graphics",
    Desc = "SmoothPlastic, mesh texture removal and SurfaceAppearance destruction."
})

UpdatesTab:Paragraph({
    Title = "Performance",
    Desc = "Controlled batches and protection against repeated processing."
})

--==================================================
-- OPTIMIZER
--==================================================

OptimizerTab:Toggle({
    Title = "Low Graphics",
    Desc = "Hides Decal and Texture images using two methods.",
    Value = false,

    Callback = function(value)
        SetLowGraphics(value)
    end
})

OptimizerTab:Toggle({
    Title = "Extremely Low Graphics",
    Desc = "Removes surface images, mesh textures and complex materials.",
    Value = false,

    Callback = function(value)
        SetExtremelyLowGraphics(value)
    end
})

--==================================================
-- REMOVER
--==================================================

RemoverTab:Toggle({
    Title = "Remove Vegetation",
    Desc = "Hides vegetation, trees, rocks, logs, grass, flowers and dirt.",
    Value = false,

    Callback = function(value)
        SetRemoveVegetation(value)
    end
})

RemoverTab:Toggle({
    Title = "Remove Decoration",
    Desc = "Hides furniture, chairs, tables, boxes, lamps and listed decorations.",
    Value = false,

    Callback = function(value)
        SetRemoveDecoration(value)
    end
})

--==================================================
-- SETTINGS
--==================================================

SettingsTab:Paragraph({
    Title = "Interface Appearance",
    Desc = "Change the accent color of the NIGHTSAKEN interface."
})

SettingsTab:Colorpicker({
    Title = "Interface Color",
    Desc = "Choose your preferred interface color.",
    Default = Settings.InterfaceColor,
    Transparency = 0,

    Callback = function(color)
        ApplyInterfaceColor(color)
    end
})

--==================================================
-- GAMEPLAY INITIALIZATION
--==================================================

task.spawn(function()
    WaitForGameplay()

    task.wait(0.5)

    ScanWorkspace()

    print("NIGHTSAKEN v0.0 - Gameplay optimization started.")
end)

--==================================================
-- END
--==================================================

print("NIGHTSAKEN v0.0 loaded successfully.")
