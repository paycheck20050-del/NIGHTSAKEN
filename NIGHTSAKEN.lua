
--========================================================
-- NIGHTSAKEN v0.2
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

local CONFIG_FILE = "NIGHTSAKEN_V02.json"

local Settings = {
    LowGraphics = false,
    ExtremelyLow = false,
    OptimizeLighting = false,
    RemoveVegetation = false,
    RemoveDecoration = false
}

local Palette = {
    Color3.fromHex("#777C72"),
    Color3.fromHex("#A6A49A"),
    Color3.fromHex("#89939B"),
    Color3.fromHex("#66717D")
}

local WindUI = nil
local Window = nil

local EnqueueJob
local JobQueue = {}
local JobRunning = false

local ProcessedVegetation = setmetatable({}, {__mode = "k"})
local ProcessedDecoration = setmetatable({}, {__mode = "k"})

--========================================================
-- SAVE / LOAD SETTINGS
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
            Settings[key] = data[key] == true
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
-- REMOVER KEYWORDS
--========================================================

local VegetationKeywords = {
    "tree", "trees", "treepart", "treemodel",
    "leaf", "leaves", "foliage", "branch",
    "branches", "trunk", "stump", "wood",
    "bush", "bushes", "shrub", "shrubs",
    "grass", "flower", "flowers", "plant",
    "plants", "fern", "ferns", "vine",
    "vines", "vegetation", "mushroom",
    "mushrooms", "weed", "weeds",
    "rock", "rocks", "pebble", "pebbles",
    "rockformation", "log", "logs",
    "arbol", "arboles", "hoja", "hojas",
    "rama", "ramas", "arbusto", "arbustos",
    "pasto", "hierba", "flor", "flores",
    "planta", "plantas", "piedra", "piedras",
    "helecho", "tronco", "musgo"
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
    "ball", "sphere", "computer", "monitor",
    "briefcase", "bench", "foodstand",
    "fooddisplay", "decoration", "ornament",
    "poster", "clock", "cabinet", "vendingmachine",
    "trashcan", "plantpot", "flowerpot",
    "pelota", "silla", "mesa", "lampara",
    "cuadro", "barril", "caja", "estatua",
    "banco", "alfombra", "decoracion",
    "maceta", "reloj", "television",
    "sofa", "sillon", "cartel", "estante",
    "computadora", "monitor", "candelabro",
    "cajero", "maquina", "bote", "basurero"
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
    "round", "timer"
}

--========================================================
-- NAME NORMALIZATION
--========================================================

local function NormalizeName(name)
    name = string.lower(tostring(name))
    name = name:gsub("[%s_%-%.]", "")
    name = name:gsub("[áàä]", "a")
    name = name:gsub("[éèë]", "e")
    name = name:gsub("[íìï]", "i")
    name = name:gsub("[óòö]", "o")
    name = name:gsub("[úùü]", "u")

    return name
end

local function ContainsKeyword(name, keywords)
    name = NormalizeName(name)

    for _, keyword in ipairs(keywords) do
        local normalized = NormalizeName(keyword)

        if string.find(name, normalized, 1, true) then
            return true
        end
    end

    return false
end

--========================================================
-- COLLISION PROXY DETECTION
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

--========================================================
-- PROTECTION SYSTEM
--========================================================

local function IsProtected(object)
    if not object then
        return true
    end

    if IsCollisionProxy(object) then
        return true
    end

    local current = object

    while current and current ~= Workspace do
        if ContainsKeyword(
            current.Name,
            ProtectedKeywords
        ) then
            return true
        end

        current = current.Parent
    end

    if Player.Character
        and object:IsDescendantOf(Player.Character) then
        return true
    end

    if object:IsA("Model") then
        for _, descendant in ipairs(object:GetDescendants()) do
            if descendant:IsA("ProximityPrompt")
                or descendant:IsA("ClickDetector")
                or descendant:IsA("Humanoid")
                or descendant:IsA("Tool")
                or descendant:IsA("Seat")
                or descendant:IsA("VehicleSeat")
                or descendant:IsA("SpawnLocation") then

                return true
            end
        end
    end

    return false
end

--========================================================
-- GRAPHICS OPTIMIZATION
--========================================================

local function OptimizeObject(object)
    if not object or not object.Parent then
        return
    end

    pcall(function()
        if object:IsA("BasePart") then
            object.Material = Enum.Material.SmoothPlastic
            object.CastShadow = false

        elseif object:IsA("Decal")
            or object:IsA("Texture") then

            object.Transparency = 1

        elseif object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles")
            or object:IsA("PostEffect") then

            object.Enabled = false
        end
    end)
end

local function ApplyLowGraphics()
    local objects = Workspace:GetDescendants()

    for index, object in ipairs(objects) do
        OptimizeObject(object)

        if index % 120 == 0 then
            task.wait()
        end
    end
end

local function ApplyExtremeGraphics()
    local objects = Workspace:GetDescendants()

    for index, object in ipairs(objects) do
        OptimizeObject(object)

        if object:IsA("BasePart") then
            pcall(function()
                object.Color = Palette[
                    math.random(1, #Palette)
                ]
            end)
        end

        if index % 120 == 0 then
            task.wait()
        end
    end
end

local function ApplyLightingOptimization()
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

local function SetLowGraphics(enabled)
    Settings.LowGraphics = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Low Graphics", ApplyLowGraphics)
    end
end

local function SetExtremelyLow(enabled)
    Settings.ExtremelyLow = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Extremely Low Graphics", ApplyExtremeGraphics)
    end
end

local function SetOptimizeLighting(enabled)
    Settings.OptimizeLighting = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Optimize Lighting", ApplyLightingOptimization)
    end
end

--========================================================
-- VEGETATION COLLISION SYSTEM
--========================================================

local function IsStaticObject(object)
    if object:IsA("BasePart") then
        return object.Anchored
    end

    if object:IsA("Model") then
        local found = false

        for _, item in ipairs(object:GetDescendants()) do
            if item:IsA("BasePart") then
                found = true

                if not item.Anchored then
                    return false
                end
            end
        end

        return found
    end

    return false
end

--========================================================
-- CONFIGURE INVISIBLE COLLISION COPY
--========================================================

local function ConfigureCollisionPart(part)
    if not part:IsA("BasePart") then
        return
    end

    part.Transparency = 1
    part.LocalTransparencyModifier = 1
    part.CastShadow = false

    -- No cambiamos:
    -- CanCollide
    -- CanTouch
    -- CanQuery
    -- CFrame
    -- Size
    -- Anchored
end

local function PrepareCollisionCopy(original)
    local oldArchivable = original.Archivable

    pcall(function()
        original.Archivable = true
    end)

    local clone = nil

    local cloneSuccess = pcall(function()
        clone = original:Clone()
    end)

    pcall(function()
        original.Archivable = oldArchivable
    end)

    if not cloneSuccess or not clone then
        return nil
    end

    clone.Name = "NS_CollisionProxy"

    local descendants = clone:GetDescendants()

    for index, item in ipairs(descendants) do
        if item:IsA("BasePart") then
            ConfigureCollisionPart(item)

        elseif item:IsA("Decal")
            or item:IsA("Texture") then

            item.Transparency = 1

        elseif item:IsA("ParticleEmitter")
            or item:IsA("Trail")
            or item:IsA("Beam")
            or item:IsA("Fire")
            or item:IsA("Smoke")
            or item:IsA("Sparkles")
            or item:IsA("Highlight")
            or item:IsA("PointLight")
            or item:IsA("SpotLight")
            or item:IsA("SurfaceLight") then

            item.Enabled = false

        elseif item:IsA("BillboardGui")
            or item:IsA("SurfaceGui") then

            item.Enabled = false

        elseif item:IsA("Script")
            or item:IsA("LocalScript")
            or item:IsA("ModuleScript") then

            item:Destroy()

        elseif item:IsA("SurfaceAppearance") then
            item:Destroy()
        end

        if index % 100 == 0 then
            task.wait()
        end
    end

    if clone:IsA("BasePart") then
        ConfigureCollisionPart(clone)
    end

    return clone
end

--========================================================
-- REPLACE ORIGINAL WITH COLLISION COPY
--========================================================

local function RemoveVegetationWithCollision(object)
    if not object or not object.Parent then
        return false
    end

    if IsProtected(object) or not IsStaticObject(object) then
        return false
    end

    local parent = object.Parent
    local clone = nil

    local success = pcall(function()
        clone = PrepareCollisionCopy(object)

        if not clone then
            error("No se pudo crear la copia")
        end

        clone.Parent = parent

        -- Solo después de crear la copia,
        -- destruimos el objeto original.
        object:Destroy()
    end)

    if not success then
        if clone then
            pcall(function()
                clone:Destroy()
            end)
        end

        return false
    end

    return true
end

--========================================================
-- FIND VEGETATION CANDIDATES
--========================================================

local function FindVegetationCandidates()
    local objects = Workspace:GetDescendants()
    local candidates = {}
    local candidateSet = {}

    for index, object in ipairs(objects) do
        if (object:IsA("Model") or object:IsA("BasePart"))
            and not IsCollisionProxy(object)
            and not IsProtected(object)
            and IsStaticObject(object)
            and ContainsKeyword(
                object.Name,
                VegetationKeywords
            ) then

            candidateSet[object] = true
        end

        if index % 150 == 0 then
            task.wait()
        end
    end

    -- Evitar procesar hijos de modelos seleccionados.
    for object in pairs(candidateSet) do
        local parent = object.Parent
        local hasCandidateParent = false

        while parent and parent ~= Workspace do
            if candidateSet[parent] then
                hasCandidateParent = true
                break
            end

            parent = parent.Parent
        end

        if not hasCandidateParent then
            table.insert(candidates, object)
        end
    end

    return candidates
end

--========================================================
-- VEGETATION REMOVER
--========================================================

local function RemoveVegetation()
    local candidates = FindVegetationCandidates()

    local removed = 0
    local failed = 0

    for index, object in ipairs(candidates) do
        if object.Parent then
            if RemoveVegetationWithCollision(object) then
                removed = removed + 1
            else
                failed = failed + 1
            end
        end

        -- Repartir el trabajo para reducir bloqueos.
        if index % 15 == 0 then
            task.wait()
        end
    end

    print("[NIGHTSAKEN] Vegetación reemplazada:", removed)
    print("[NIGHTSAKEN] Vegetación omitida:", failed)

    return removed, failed
end

--========================================================
-- OLD DECORATION REMOVER
--========================================================

local function RemoveMatchingObjects(keywords)
    local removed = 0
    local objects = Workspace:GetDescendants()

    -- Primero modelos.
    for index, object in ipairs(objects) do
        if object.Parent
            and object:IsA("Model")
            and not IsCollisionProxy(object)
            and ContainsKeyword(object.Name, keywords)
            and not IsProtected(object) then

            local success = pcall(function()
                object:Destroy()
            end)

            if success then
                removed = removed + 1
            end
        end

        if index % 120 == 0 then
            task.wait()
        end
    end

    -- Después piezas individuales.
    for index, object in ipairs(objects) do
        if object.Parent
            and object:IsA("BasePart")
            and not IsCollisionProxy(object)
            and ContainsKeyword(object.Name, keywords)
            and not IsProtected(object) then

            local success = pcall(function()
                object:Destroy()
            end)

            if success then
                removed = removed + 1
            end
        end

        if index % 120 == 0 then
            task.wait()
        end
    end

    return removed
end

--========================================================
-- REMOVER CONTROLS CALLBACKS
--========================================================

local function SetRemoveVegetation(enabled)
    Settings.RemoveVegetation = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Vegetation Remover", function()
            local amount, failed = RemoveVegetation()

            Notify(
                "Vegetation Remover",
                tostring(amount) .. " objetos reemplazados; "
                .. tostring(failed) .. " omitidos"
            )
        end)
    end
end

local function SetRemoveDecoration(enabled)
    Settings.RemoveDecoration = enabled
    SaveSettings()

    if enabled then
        EnqueueJob("Decoration Remover", function()
            local amount = RemoveMatchingObjects(
                DecorationKeywords
            )

            Notify(
                "Decoration Remover",
                "Decoración eliminada: " .. tostring(amount)
            )
        end)
    end
end

--========================================================
-- OPTIMIZATION QUEUE
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

            Notify(
                "NIGHTSAKEN",
                "Procesando: " .. job.Name
            )

            local success, errorMessage = xpcall(
                job.Callback,
                function(err)
                    return tostring(err)
                end
            )

            if success then
                print("[NIGHTSAKEN] Terminado:", job.Name)
            else
                warn(
                    "[NIGHTSAKEN] Error en "
                    .. job.Name .. ": "
                    .. tostring(errorMessage)
                )

                Notify(
                    "NIGHTSAKEN",
                    "Error en: " .. job.Name
                )
            end

            task.wait(0.1)
        end

        JobRunning = false

        Notify(
            "NIGHTSAKEN",
            "Optimización terminada"
        )

        print("[NIGHTSAKEN] OPTIMIZACIÓN TERMINADA")
    end)
end

--========================================================
-- WINDUI LOADER
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

    warn("[NIGHTSAKEN] Error descargando WindUI:", source)
    return
end

local compileSuccess, compiled = pcall(function()
    return loadstring(source)
end)

if not compileSuccess or type(compiled) ~= "function" then
    warn("[NIGHTSAKEN] Error compilando WindUI:", compiled)
    return
end

local loadSuccess, loadedWindUI = pcall(compiled)

if not loadSuccess or type(loadedWindUI) ~= "table" then
    warn("[NIGHTSAKEN] Error iniciando WindUI:", loadedWindUI)
    return
end

WindUI = loadedWindUI

--========================================================
-- CREATE WINDOW
--========================================================

local windowSuccess, createdWindow = pcall(function()
    return WindUI:CreateWindow({
        Title = "NIGHTSAKEN",
        Author = "Forsaken Optimizer",
        Icon = "moon",

        Folder = "NIGHTSAKEN_v02",

        Theme = "Dark",
        Size = UDim2.fromOffset(420, 430),
        MinSize = Vector2.new(300, 350),
        Resizable = true,
        SideBarWidth = 150,
        HideSearchBar = false
    })
end)

if not windowSuccess or not createdWindow then
    warn("[NIGHTSAKEN] Error creando ventana:", createdWindow)
    return
end

Window = createdWindow

pcall(function()
    Window:Tag({
        Title = "v0.2",
        Color = Color3.fromHex("#89939B")
    })
end)

--========================================================
-- CREATE TABS
--========================================================

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
    warn("[NIGHTSAKEN] Error creando pestañas:", tabs)
    return
end

local MainTab = tabs.Main
local RemoverTab = tabs.Remover
local SettingsTab = tabs.Settings
local InfoTab = tabs.Info

--========================================================
-- OPTIMIZER CONTROLS
--========================================================

MainTab:Section({
    Title = "Graphics"
})

MainTab:Toggle({
    Title = "Low Graphics",
    Desc = "Reduce texturas, sombras y efectos visuales",
    Value = Settings.LowGraphics,

    Callback = SetLowGraphics
})

MainTab:Toggle({
    Title = "Extremely Low Graphics",
    Desc = "Optimización extrema con paleta de colores",
    Value = Settings.ExtremelyLow,

    Callback = SetExtremelyLow
})

MainTab:Toggle({
    Title = "Optimize Lighting",
    Desc = "Desactiva efectos de iluminación",
    Value = Settings.OptimizeLighting,

    Callback = SetOptimizeLighting
})

--========================================================
-- REMOVER CONTROLS
--========================================================

RemoverTab:Section({
    Title = "World Remover"
})

RemoverTab:Toggle({
    Title = "Remover vegetación",
    Desc = "Reemplaza vegetación por copias invisibles con colisión",
    Value = Settings.RemoveVegetation,

    Callback = SetRemoveVegetation
})

RemoverTab:Toggle({
    Title = "Remover decoración",
    Desc = "Elimina objetos decorativos del mapa",
    Value = Settings.RemoveDecoration,

    Callback = SetRemoveDecoration
})

--========================================================
-- SETTINGS
--========================================================

SettingsTab:Section({
    Title = "Interface"
})

local themes = {}

pcall(function()
    local availableThemes = WindUI:GetThemes()

    for themeName in pairs(availableThemes) do
        table.insert(themes, themeName)
    end
end)

table.sort(themes)

if #themes > 0 then
    SettingsTab:Dropdown({
        Title = "UI Theme",
        Values = themes,
        Value = "Dark",
        SearchBarEnabled = true,

        Callback = function(theme)
            pcall(function()
                WindUI:SetTheme(theme)
            end)
        end
    })
end

SettingsTab:Button({
    Title = "Save Settings",
    Desc = "Guardar configuración actual",

    Callback = function()
        SaveSettings()

        Notify(
            "NIGHTSAKEN",
            "Configuración guardada"
        )
    end
})

--========================================================
-- INFORMATION
--========================================================

InfoTab:Section({
    Title = "NIGHTSAKEN v0.2"
})

InfoTab:Paragraph({
    Title = "Forsaken Mobile Optimizer",
    Content = "Optimizador visual diseñado para reducir la carga gráfica en dispositivos móviles."
})

InfoTab:Paragraph({
    Title = "Independent Controls",
    Content = "Low Graphics y Extremely Low Graphics funcionan de forma independiente."
})

InfoTab:Paragraph({
    Title = "Vegetation Collision",
    Content = "Reemplaza piezas compatibles por copias invisibles que conservan sus propiedades físicas."
})

InfoTab:Paragraph({
    Title = "Decoration Remover",
    Content = "Conserva el sistema de eliminación de decoración de NIGHTSAKEN v0.1."
})

InfoTab:Paragraph({
    Title = "Local Changes",
    Content = "Los cambios se intentan aplicar localmente y no modifican directamente el servidor."
})

--========================================================
-- FIND NEW VEGETATION TARGET
--========================================================

local function GetVegetationTarget(object)
    if not object or IsCollisionProxy(object) then
        return nil
    end

    local current = object

    -- Buscar primero un modelo de vegetación.
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

    -- Si no pertenece a un modelo detectado,
    -- comprobar la pieza individual.
    if object:IsA("BasePart")
        and ContainsKeyword(
            object.Name,
            VegetationKeywords
        ) then

        return object
    end

    return nil
end

--========================================================
-- FIND NEW DECORATION TARGET
--========================================================

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

--========================================================
-- AUTOMATIC NEW OBJECT DETECTION
--========================================================

Workspace.DescendantAdded:Connect(function(object)
    task.delay(0.35, function()
        if not object.Parent then
            return
        end

        if IsCollisionProxy(object) then
            return
        end

        -- Graphics optimization.
        if Settings.LowGraphics or Settings.ExtremelyLow then
            OptimizeObject(object)
        end

        if Settings.ExtremelyLow
            and object:IsA("BasePart") then

            pcall(function()
                object.Color = Palette[
                    math.random(1, #Palette)
                ]
            end)
        end

        -- Automatic vegetation replacement.
        if Settings.RemoveVegetation then
            local target = GetVegetationTarget(object)

            if target and not ProcessedVegetation[target] then
                ProcessedVegetation[target] = true

                EnqueueJob(
                    "New Vegetation",
                    function()
                        if target.Parent then
                            RemoveVegetationWithCollision(target)
                        end
                    end
                )
            end
        end

        -- Original decoration removal behavior.
        if Settings.RemoveDecoration then
            local target = GetDecorationTarget(object)

            if target and not ProcessedDecoration[target] then
                ProcessedDecoration[target] = true

                EnqueueJob(
                    "New Decoration",
                    function()
                        if target.Parent
                            and not IsProtected(target) then

                            pcall(function()
                                target:Destroy()
                            end)
                        end
                    end
                )
            end
        end
    end)
end)

--========================================================
-- LOAD SAVED SETTINGS
--========================================================

task.defer(function()
    if Settings.LowGraphics then
        EnqueueJob(
            "Low Graphics",
            ApplyLowGraphics
        )
    end

    if Settings.ExtremelyLow then
        EnqueueJob(
            "Extremely Low Graphics",
            ApplyExtremeGraphics
        )
    end

    if Settings.OptimizeLighting then
        EnqueueJob(
            "Optimize Lighting",
            ApplyLightingOptimization
        )
    end

    if Settings.RemoveVegetation then
        EnqueueJob(
            "Vegetation Remover",
            function()
                local amount, failed = RemoveVegetation()

                Notify(
                    "Vegetation Remover",
                    tostring(amount) .. " objetos reemplazados; "
                    .. tostring(failed) .. " omitidos"
                )
            end
        )
    end

    if Settings.RemoveDecoration then
        EnqueueJob(
            "Decoration Remover",
            function()
                local amount = RemoveMatchingObjects(
                    DecorationKeywords
                )

                Notify(
                    "Decoration Remover",
                    "Decoración eliminada: " .. tostring(amount)
                )
            end
        )
    end
end)

--========================================================
-- STARTUP
--========================================================

print("========================================")
print("NIGHTSAKEN v0.2")
print("FORSAKEN MOBILE OPTIMIZER")
print("LOADED SUCCESSFULLY")
print("========================================")

Notify(
    "NIGHTSAKEN v0.2",
    "Optimizer cargado correctamente"
)
