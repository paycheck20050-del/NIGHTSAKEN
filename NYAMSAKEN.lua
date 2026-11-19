--==================================================
-- NIGHTSAKEN v0.0
-- Designed for MediaTek Helio G88
-- UI: WindUI 1.6.66
--==================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- WINDUI LOADER
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
-- COLOR PALETTE
--==================================================

local COLORS = {
    GreenGray = Color3.fromHex("#777C72"),
    LightGray = Color3.fromHex("#A6A49A"),
    BlueGray = Color3.fromHex("#89939B"),
    DarkBlueGray = Color3.fromHex("#66717D")
}

--==================================================
-- ORIGINAL COLOR BACKUP
--==================================================

local OriginalColors = setmetatable({}, {
    __mode = "k"
})

local OriginalTextureTransparency = setmetatable({}, {
    __mode = "k"
})

local function SaveColor(object)
    if OriginalColors[object] ~= nil then
        return
    end

    if object:IsA("BasePart") then
        OriginalColors[object] = object.Color
    end
end

local function RestoreColors()
    for object, color in pairs(OriginalColors) do
        if object and object.Parent then
            pcall(function()
                object.Color = color
            end)
        end

        OriginalColors[object] = nil
    end
end

--==================================================
-- LOW GRAPHICS
-- Hide textures without changing object colors
--==================================================

local function ProcessTexture(object)
    if not Settings.LowGraphics then
        return
    end

    if not object:IsA("Decal")
        and not object:IsA("Texture") then
        return
    end

    if OriginalTextureTransparency[object] == nil then
        OriginalTextureTransparency[object] =
            object.Transparency
    end

    object.Transparency = 1
end

local function RestoreTextures()
    for object, transparency in pairs(
        OriginalTextureTransparency
    ) do
        if object and object.Parent then
            pcall(function()
                object.Transparency = transparency
            end)
        end

        OriginalTextureTransparency[object] = nil
    end
end

--==================================================
-- EXTREMELY LOW GRAPHICS
-- Lighting classification
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
    else
        return "Dark"
    end
end

--==================================================
-- FLOOR DETECTION
--==================================================

local function IsFloor(object)
    if not object:IsA("BasePart") then
        return false
    end

    return object.Size.Y < 4
        and (
            object.Size.X > 8
            or object.Size.Z > 8
        )
end

--==================================================
-- ADAPTIVE COLOR SELECTION
--==================================================

local function GetAdaptiveColors()
    local lightingType = GetMapLightingType()

    if lightingType == "Bright" then
        return COLORS.LightGray, COLORS.GreenGray

    elseif lightingType == "Medium" then
        return COLORS.BlueGray, COLORS.DarkBlueGray

    else
        return COLORS.BlueGray, COLORS.LightGray
    end
end

--==================================================
-- EXTREMELY LOW GRAPHICS PROCESSOR
--==================================================

local SelectedWallColor
local SelectedFloorColor

local function ProcessExtremelyLow(object)
    if not Settings.ExtremelyLowGraphics then
        return
    end

    if not object:IsA("BasePart") then
        return
    end

    -- No recolorear personajes.
    local ancestor = object.Parent

    while ancestor and ancestor ~= Workspace do
        if ancestor:IsA("Model")
            and ancestor:FindFirstChildOfClass("Humanoid") then
            return
        end

        ancestor = ancestor.Parent
    end

    SaveColor(object)

    if IsFloor(object) then
        object.Color = SelectedFloorColor
    else
        object.Color = SelectedWallColor
    end
end--==================================================
-- REMOVER 🛡️
-- Name-based object categories
-- No original transparency backup
--==================================================

local VegetationNames = {
    "tree",
    "rock",
    "stone",
    "log",
    "grass",
    "flower",
    "bush",
    "foliage",
    "vegetation",
    "pasto",
    "cesped",
    "césped",
    "arbol",
    "árbol",
    "piedra",
    "tronco",
    "arbusto",
    "flores",
    "tierra"
}

local DecorationNames = {
    "chair",
    "furniture",
    "cushion",
    "pillow",
    "curtain",
    "table",
    "round",
    "ball",
    "mini chair",
    "box",
    "chest",
    "painting",
    "picture",
    "photo",
    "food",
    "food stand",
    "helmet",
    "straw",
    "closet",
    "lamp",
    "flowerpot",
    "pot",
    "drawer",
    "silla",
    "mueble",
    "cojin",
    "cojín",
    "cortina",
    "mesa",
    "pelota",
    "caja",
    "cofre",
    "cuadro",
    "foto",
    "comida",
    "casco",
    "paja",
    "closet",
    "clóset",
    "lampara",
    "lámpara",
    "maceta",
    "cajon",
    "cajón"
}

local function NameMatches(object, names)
    local objectName = string.lower(object.Name)

    for _, keyword in ipairs(names) do
        if string.find(objectName, keyword, 1, true) then
            return true
        end
    end

    return false
end

local function HidePartsInside(object)
    if object:IsA("BasePart") then
        object.Transparency = 1
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Transparency = 1
        end
    end
end

local function ProcessRemoverObject(object)
    if Settings.RemoveVegetation
        and NameMatches(object, VegetationNames) then

        HidePartsInside(object)
    end

    if Settings.RemoveDecoration
        and NameMatches(object, DecorationNames) then

        HidePartsInside(object)
    end
end

--==================================================
-- GAMEPLAY START GATE
--==================================================

local GameplayStarted = false

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

    -- Espera a que el jugador pueda moverse.
    -- Esto evita iniciar durante intros donde el personaje está bloqueado.
    if humanoid.WalkSpeed <= 0 then
        return false
    end

    if humanoid.MoveDirection.Magnitude < 0.05 then
        return false
    end

    return true
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
-- MAIN PROCESSOR
--==================================================

local Processing = false

local function ProcessObject(object)
    if not object or not object.Parent then
        return
    end

    ProcessTexture(object)

    ProcessRemoverObject(object)

    ProcessExtremelyLow(object)
end

local function ScanWorkspace()
    if not GameplayStarted or Processing then
        return
    end

    Processing = true

    task.spawn(function()
        if Settings.ExtremelyLowGraphics then
            SelectedWallColor, SelectedFloorColor =
                GetAdaptiveColors()
        end

        local descendants = Workspace:GetDescendants()

        for index, object in ipairs(descendants) do
            ProcessObject(object)

            if index % 150 == 0 then
                task.wait()
            end
        end

        Processing = false
    end)
end

--==================================================
-- TOGGLE FUNCTIONS
--==================================================

local function SetLowGraphics(value)
    Settings.LowGraphics = value

    if not GameplayStarted then
        return
    end

    if value then
        ScanWorkspace()
    else
        RestoreTextures()
    end
end

local function SetExtremelyLowGraphics(value)
    Settings.ExtremelyLowGraphics = value

    if not GameplayStarted then
        return
    end

    if value then
        SelectedWallColor, SelectedFloorColor =
            GetAdaptiveColors()

        ScanWorkspace()
    else
        RestoreColors()
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
-- NEW OBJECTS
--==================================================

Workspace.DescendantAdded:Connect(function(object)
    if not GameplayStarted then
        return
    end

    if not (
        Settings.LowGraphics
        or Settings.ExtremelyLowGraphics
        or Settings.RemoveVegetation
        or Settings.RemoveDecoration
    ) then
        return
    end

    task.defer(function()
        if object and object.Parent then
            ProcessObject(object)
        end
    end)
end)

--==================================================
-- CLEANUP REMOVED OBJECTS
--==================================================

Workspace.DescendantRemoving:Connect(function(object)
    OriginalColors[object] = nil
    OriginalTextureTransparency[object] = nil
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
    Desc = "A new beginning. Designed for MediaTek Helio G88."
})

UpdatesTab:Paragraph({
    Title = "Optimization Start",
    Desc = "Optimizations wait until gameplay begins. They do not run during the killer intro."
})

--==================================================
-- OPTIMIZER
--==================================================

OptimizerTab:Toggle({
    Title = "Low Graphics",
    Desc = "Hides all Decal and Texture images while preserving object colors.",
    Value = false,

    Callback = function(value)
        SetLowGraphics(value)
    end
})

OptimizerTab:Toggle({
    Title = "Extremely Low Graphics",
    Desc = "Uses adaptive four-color graphics based on OutdoorAmbient.",
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
    Desc = "Hides trees, rocks, logs, grass, flowers, bushes and dirt.",
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

    -- La primera optimización ocurre después
    -- de que el jugador ya puede moverse.
    task.wait(0.5)

    ScanWorkspace()

    print("NIGHTSAKEN v0.0 - Gameplay optimization started.")
end)

--==================================================
-- END
--==================================================

print("NIGHTSAKEN v0.0 loaded.")
