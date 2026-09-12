-- 手感调节迷你关卡。
-- 只放 3-1 旋转 Part，镜头/雾/体素 look 对齐第一章；进出走关卡近雾 tween。

local UI = require("urhox-libs/UI")
local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local PointerInput = require "PointerInput"
local ControlSettings = require "ControlSettings"
local MenuVolumeRow = require "MenuVolumeRow"
local MenuTextItem = require "MenuTextItem"
local MenuHoverTint = require "MenuHoverTint"
local LevelCatalog = require "LevelCatalog"
local LevelDocument = require "LevelDocument"
local TriPrismGrid = require "TriPrismGrid"
local PartRootRenderer = require "PartRootRenderer"
local PreviewRotatorController = require "PreviewRotatorController"
local FixedGameCamera = require "FixedGameCamera"
local Sfx = require "Sfx"

local FeelCalibrate = {}
FeelCalibrate.__index = FeelCalibrate

local WHITE = { 255, 255, 255, 255 }
local HINT_COLOR = { 255, 255, 255, 200 }
local LABEL_WIDTH = 168
local PANEL_WIDTH = 820
local MODE_FONT_SIZE = 28
local MODE_SCALE = 1.18
local MODE_TWEEN = 0.18
local FOG_REVEAL_DURATION = 1.0
local COVER_FOG_START = 0.1
local COVER_FOG_END = 2.0
local COVER_FOG_DENSITY = 1.0
local SETTLE_STABLE_DT = 0.05
local SETTLE_NEEDED = 3
local MAX_REVEAL_DT = 1.0 / 30.0

local CHAPTER1_LOOK = {
    shader = "tri_prism_look_height_fog",
    colorNeg = "#554C3E",
    colorMid = "#685D4F",
    colorPos = "#FFF7E7",
    fogColor = "#C0B499",
    fogHeightA = 0.0,
    fogHeightB = -0.5,
    aoEnabled = true,
    aoColor = "#2A1F1A",
    aoSmooth = 0.18,
    aoBlend = 1.0,
    emissionColor = "#FFF4D2",
    emissionStrength = 0.25,
    lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
    fogUp = { x = 0.0, y = 1.0, z = 0.0 },
}

local CHAPTER1_ATMOSPHERE = {
    lightGroup = "LightGroup/Daytime.xml",
    fog = {
        color = "#937754",
        start = 1000.0,
        finish = 2000.0,
        density = 0.0,
        heightFog = false,
    },
    bloom = { enabled = false, threshold = 1.1, intensity = 0.15 },
    vignette = { enabled = false, intensity = 0.08 },
    tonemap = "none",
}

local CHAPTER1_CAMERA = {
    target = { x = 0.0, y = 1.2, z = 0.0 },
    orthoSize = 12.0,
    nearClip = 0.1,
    farClip = 100.0,
    pitch = 30.0,
}

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/MiSans-Regular.ttf",
                    bold = "Fonts/MiSans-Bold.ttf",
                },
            },
        },
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })
    UI.SetScale(UI.Scale.DESIGN_RESOLUTION(1920, 1080))
end

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function EaseOutCubic(t)
    local inverse = 1.0 - Clamp01(t)
    return 1.0 - inverse * inverse * inverse
end

local function MixChannel(fromValue, toValue, t)
    return math.floor(fromValue + (toValue - fromValue) * t + 0.5)
end

local function MixRgba(fromColor, toColor, t)
    return {
        MixChannel(fromColor[1], toColor[1], t),
        MixChannel(fromColor[2], toColor[2], t),
        MixChannel(fromColor[3], toColor[3], t),
        MixChannel(fromColor[4] or 255, toColor[4] or 255, t),
    }
end

local function HasMode(modes, wanted)
    if type(modes) ~= "table" then
        return false
    end
    for i = 1, #modes do
        if modes[i] == wanted then
            return true
        end
    end
    return false
end

local function CopyLook(source)
    local look = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do
                nested[nestedKey] = nestedValue
            end
            look[key] = nested
        else
            look[key] = value
        end
    end
    return look
end

local function StubPathRuntime()
    return {
        RefreshAfterMechanismSnap = function()
            return true
        end,
        GetNode = function()
            return nil
        end,
    }
end

local function MakeVeilBand(height, fromAlpha)
    return UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        bottom = 0,
        height = height,
        pointerEvents = "none",
        backgroundGradient = {
            type = "linear",
            direction = "to-top",
            from = { 0, 0, 0, fromAlpha },
            to = { 0, 0, 0, 0 },
        },
    }
end

function FeelCalibrate.New()
    local self = setmetatable({}, FeelCalibrate)
    ---@type Scene|nil
    self.scene = nil
    ---@type Node|nil
    self.cameraNode = nil
    ---@type Camera|nil
    self.camera = nil
    ---@type Viewport|nil
    self.viewport = nil
    ---@type table|nil
    self.levelDocument = nil
    ---@type table|nil
    self.partRenderer = nil
    ---@type table|nil
    self.rotatorController = nil
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.uiPanel = nil
    ---@type Widget|nil
    self.veil = nil
    ---@type Widget|nil
    self.panLabel = nil
    ---@type Widget|nil
    self.orbitLabel = nil
    self.panAmount = 0.0
    self.orbitAmount = 0.0
    self.panFrom = 0.0
    self.orbitFrom = 0.0
    self.panTo = 0.0
    self.orbitTo = 0.0
    self.modeTweenElapsed = 0.0
    self.modeTweenDuration = 0.0
    ---@type Widget|nil
    self.hintLabel = nil
    ---@type MenuVolumeRow|nil
    self.sliderRow = nil
    ---@type MenuTextItem|nil
    self.confirmItem = nil
    ---@type table|nil
    self.fogReveal = nil
    self.waitingSettle = false
    self.settleCount = 0
    self.delayReveal = false
    self.uiOpacity = 0.0
    self.inputLocked = true
    ---@type fun()|nil
    self.onFinished = nil
    ---@type fun()|nil
    self.onFogCoverFinished = nil
    self.selectedColor = MenuHoverTint.FromFog(LookApplier.HexToColor("#C0B499"))
    return self
end

function FeelCalibrate:CoverFogColor()
    return LookApplier.HexToColor(CHAPTER1_ATMOSPHERE.fog.color, Color(0.58, 0.47, 0.33, 1))
end

function FeelCalibrate:ApplyCoverFog(density)
    if not self.scene then
        return false
    end
    return LookApplier.SetCoverFog(self.scene, self:CoverFogColor(), density)
end

function FeelCalibrate:LoadDocument()
    local json, jsonError = LevelCatalog.ReadSourceJson("Levels/level-3-1.json")
    if not json then
        return false, jsonError
    end
    local ok, decoded = pcall(cjson.decode, json)
    if not ok or type(decoded) ~= "table" or type(decoded.parts) ~= "table" then
        return false, "feel calibrate: invalid 3-1 json"
    end
    local rotatorParts = {}
    for i = 1, #decoded.parts do
        local part = decoded.parts[i]
        if type(part) == "table" and HasMode(part.behaviorModes, "rotator") then
            part.look = CopyLook(CHAPTER1_LOOK)
            rotatorParts[#rotatorParts + 1] = part
        end
    end
    if #rotatorParts == 0 then
        return false, "feel calibrate: 3-1 has no rotator"
    end
    decoded.parts = rotatorParts
    decoded.stillObjects = {}
    decoded.pathCandidates = {}
    decoded.spawnNodeKey = ""
    decoded.atmosphere = CHAPTER1_ATMOSPHERE
    decoded.fixedCamera = CHAPTER1_CAMERA
    local voxel = rotatorParts[1].localVoxelDocument or {}
    local gridInfo = voxel.grid or {}
    local edge = tonumber(gridInfo.edgeLength) or VoxelRenderer.DEFAULT_EDGE
    local height = tonumber(gridInfo.voxelHeight) or VoxelRenderer.DEFAULT_HEIGHT
    local grid = TriPrismGrid.New(edge, height)
    local packed = cjson.encode(decoded)
    if type(packed) ~= "string" or packed == "" then
        return false, "feel calibrate: encode failed"
    end
    local document, loadError = LevelDocument.LoadInlineRuntime(packed, grid)
    if not document then
        return false, loadError
    end
    self.levelDocument = document
    self.edgeLength = edge
    self.voxelHeight = height
    return true
end

function FeelCalibrate:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.scene, CHAPTER1_ATMOSPHERE)
    self:ApplyCoverFog(COVER_FOG_DENSITY)
    Sfx.BindUiScene(self.scene)
    self.cameraNode, self.camera = FixedGameCamera.Create(
        self.scene,
        "FeelCamera",
        CHAPTER1_CAMERA
    )
    self.viewport = Viewport:new(self.scene, self.camera)
    renderer:SetViewport(0, self.viewport)
    renderer:SetNumViewports(1)
    self.partRenderer = PartRootRenderer.New(self.scene, self.edgeLength, self.voxelHeight)
    local built, buildError = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        return false, buildError
    end
    self.rotatorController = PreviewRotatorController.New(
        self.levelDocument,
        self.partRenderer,
        StubPathRuntime(),
        self.camera,
        self.scene,
        nil,
        nil,
        nil
    )
    self.rotatorController.autoPick = true
    self.waitingSettle = true
    self.settleCount = 0
    self.inputLocked = true
    print("FeelCalibrate: scene ready")
    return true
end

function FeelCalibrate:HintText()
    if ControlSettings.IsPanRotate() then
        return "左右拖动旋转体素"
    end
    return "按住体素绕轴心拖转"
end

function FeelCalibrate:ApplyModeVisual()
    local panT = EaseOutCubic(self.panAmount)
    local orbitT = EaseOutCubic(self.orbitAmount)
    if self.panLabel then
        self.panLabel:SetFontColor(MixRgba(WHITE, self.selectedColor, panT))
        self.panLabel:SetStyle({
            fontWeight = "bold",
            scale = 1.0 + (MODE_SCALE - 1.0) * panT,
        })
    end
    if self.orbitLabel then
        self.orbitLabel:SetFontColor(MixRgba(WHITE, self.selectedColor, orbitT))
        self.orbitLabel:SetStyle({
            fontWeight = "bold",
            scale = 1.0 + (MODE_SCALE - 1.0) * orbitT,
        })
    end
    if self.hintLabel then
        self.hintLabel:SetStyle({ text = self:HintText() })
    end
end

function FeelCalibrate:BeginModeTween()
    local pan = ControlSettings.IsPanRotate()
    self.panFrom = self.panAmount
    self.orbitFrom = self.orbitAmount
    self.panTo = pan and 1.0 or 0.0
    self.orbitTo = pan and 0.0 or 1.0
    if math.abs(self.panFrom - self.panTo) < 0.001
        and math.abs(self.orbitFrom - self.orbitTo) < 0.001 then
        self.modeTweenDuration = 0.0
        self:ApplyModeVisual()
        return
    end
    self.modeTweenElapsed = 0.0
    self.modeTweenDuration = MODE_TWEEN
    self:ApplyModeVisual()
end

function FeelCalibrate:UpdateModeTween(timeStep)
    if self.modeTweenDuration <= 0.0 then
        return
    end
    local elapsed = self.modeTweenElapsed + timeStep
    self.modeTweenElapsed = elapsed
    local t = Clamp01(elapsed / self.modeTweenDuration)
    self.panAmount = self.panFrom + (self.panTo - self.panFrom) * t
    self.orbitAmount = self.orbitFrom + (self.orbitTo - self.orbitFrom) * t
    self:ApplyModeVisual()
    if t >= 1.0 then
        self.panAmount = self.panTo
        self.orbitAmount = self.orbitTo
        self.modeTweenDuration = 0.0
        self:ApplyModeVisual()
    end
end

function FeelCalibrate:SetMode(mode)
    ControlSettings.SetRotateMode(mode, true)
    self:BeginModeTween()
    Sfx.PlayModalClick()
    print("FeelCalibrate: mode " .. mode)
end

function FeelCalibrate:BuildUI()
    EnsureUI()
    local pan = ControlSettings.IsPanRotate()
    self.panAmount = pan and 1.0 or 0.0
    self.orbitAmount = pan and 0.0 or 1.0
    self.panFrom = self.panAmount
    self.orbitFrom = self.orbitAmount
    self.panTo = self.panAmount
    self.orbitTo = self.orbitAmount
    self.modeTweenDuration = 0.0
    self.panLabel = UI.Label {
        text = "平移",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        height = 56,
        fontSize = MODE_FONT_SIZE,
        fontColor = pan and self.selectedColor or WHITE,
        fontWeight = "bold",
        textAlign = "center",
        verticalAlign = "middle",
        alignItems = "center",
        justifyContent = "center",
        transformOrigin = "center",
        pointerEvents = "auto",
        onClick = function()
            self:SetMode(ControlSettings.MODE_PAN)
        end,
    }
    self.orbitLabel = UI.Label {
        text = "环绕",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        height = 56,
        fontSize = MODE_FONT_SIZE,
        fontColor = (not pan) and self.selectedColor or WHITE,
        fontWeight = "bold",
        textAlign = "center",
        verticalAlign = "middle",
        alignItems = "center",
        justifyContent = "center",
        transformOrigin = "center",
        pointerEvents = "auto",
        onClick = function()
            self:SetMode(ControlSettings.MODE_ORBIT)
        end,
    }
    self.hintLabel = UI.Label {
        text = self:HintText(),
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        fontSize = 20,
        fontColor = HINT_COLOR,
        fontWeight = "bold",
        textAlign = "center",
        pointerEvents = "none",
    }
    self.sliderRow = MenuVolumeRow {
        title = "灵敏度",
        value = ControlSettings.SliderValue(),
        thumbColor = self.selectedColor,
        onVolume = function(value, persist)
            ControlSettings.SetFromSlider(value, persist)
        end,
    }
    self.confirmItem = MenuTextItem {
        text = "确定",
        onSelect = function()
            self:BeginConfirm()
        end,
    }
    self.confirmItem:SetHoverColor(self.selectedColor)
    self.uiPanel = UI.Panel {
        width = PANEL_WIDTH,
        alignItems = "stretch",
        justifyContent = "center",
        gap = 18,
        opacity = 0.0,
        pointerEvents = "none",
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 36,
                children = {
                    UI.Label {
                        text = "旋转模式",
                        width = LABEL_WIDTH,
                        fontSize = 28,
                        fontColor = WHITE,
                        fontWeight = "bold",
                        pointerEvents = "none",
                        flexShrink = 0,
                    },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexBasis = 0,
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "spaceBetween",
                        gap = 0,
                        children = {
                            self.panLabel,
                            self.orbitLabel,
                        },
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 36,
                children = {
                    UI.Panel {
                        width = LABEL_WIDTH,
                        flexShrink = 0,
                        pointerEvents = "none",
                    },
                    self.hintLabel,
                },
            },
            self.sliderRow,
            self.confirmItem,
        },
    }
    -- 单层 2-stop alpha 渐变在 8-bit 上会有肉眼断层；叠几层短 ramp 让衰减更接近 ease-out。
    self.veil = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        bottom = 0,
        height = "36%",
        pointerEvents = "none",
        opacity = 0.0,
        children = {
            MakeVeilBand("100%", 50),
            MakeVeilBand("70%", 70),
            MakeVeilBand("45%", 90),
            MakeVeilBand("22%", 110),
        },
    }
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            self.veil,
            UI.Panel {
                width = "100%",
                height = "100%",
                flexDirection = "column",
                justifyContent = "flex-end",
                alignItems = "center",
                paddingBottom = 72,
                pointerEvents = "box-none",
                children = {
                    self.uiPanel,
                },
            },
        },
    }
    UI.SetRoot(self.root, true)
    self:ApplyUiOpacity()
end

function FeelCalibrate:ApplyUiOpacity()
    local opacity = self.uiOpacity
    local interactive = (not self.inputLocked) and opacity > 0.05
    if self.uiPanel then
        self.uiPanel:SetStyle({ opacity = opacity })
        self.uiPanel:SetProp("pointerEvents", interactive and "auto" or "none")
    end
    if self.veil then
        self.veil:SetStyle({ opacity = opacity })
    end
end

function FeelCalibrate:AllowFogReveal()
    if not self.delayReveal then
        return
    end
    self.delayReveal = false
    if self.waitingSettle and self.settleCount >= SETTLE_NEEDED then
        self.waitingSettle = false
        self:StartFogReveal()
    end
end

function FeelCalibrate:StartFogReveal()
    self.fogReveal = {
        duration = FOG_REVEAL_DURATION,
        clock = 0.0,
        fromDensity = COVER_FOG_DENSITY,
        toDensity = CHAPTER1_ATMOSPHERE.fog.density,
        fromColor = self:CoverFogColor(),
        toColor = self:CoverFogColor(),
        conceal = false,
    }
    print("FeelCalibrate: fog reveal")
end

function FeelCalibrate:BeginFogConceal()
    if self.fogReveal and self.fogReveal.conceal then
        return true
    end
    self.inputLocked = true
    self.waitingSettle = false
    local zone = LookApplier.GetZone(self.scene)
    local fromDensity = zone and zone.fogDensity or CHAPTER1_ATMOSPHERE.fog.density
    self.fogReveal = {
        duration = FOG_REVEAL_DURATION,
        clock = 0.0,
        fromDensity = fromDensity,
        toDensity = COVER_FOG_DENSITY,
        fromColor = self:CoverFogColor(),
        toColor = self:CoverFogColor(),
        conceal = true,
    }
    print("FeelCalibrate: fog conceal")
    return true
end

function FeelCalibrate:UpdateFog(timeStep)
    if self.waitingSettle then
        self:ApplyCoverFog(COVER_FOG_DENSITY)
        if timeStep > 0.0 and timeStep <= SETTLE_STABLE_DT then
            self.settleCount = self.settleCount + 1
        else
            self.settleCount = 0
        end
        if self.settleCount >= SETTLE_NEEDED and not self.delayReveal then
            self.waitingSettle = false
            self:StartFogReveal()
        end
        return
    end
    local reveal = self.fogReveal
    if not reveal then
        return
    end
    local dt = timeStep
    if dt > MAX_REVEAL_DT then
        dt = MAX_REVEAL_DT
    end
    local nextClock = reveal.clock + dt
    reveal.clock = nextClock
    local t = Clamp01(nextClock / reveal.duration)
    local mix = reveal.conceal and (1.0 - (1.0 - t) * (1.0 - t)) or (t * t)
    local zone = LookApplier.GetZone(self.scene)
    if zone then
        zone.fogStart = COVER_FOG_START
        zone.fogEnd = COVER_FOG_END
        zone.fogDensity = reveal.fromDensity + (reveal.toDensity - reveal.fromDensity) * mix
        zone.fogColor = LookApplier.MixColor(reveal.fromColor, reveal.toColor, mix)
    end
    if reveal.conceal then
        self.uiOpacity = 1.0 - mix
    else
        self.uiOpacity = mix
    end
    self:ApplyUiOpacity()
    if t >= 1.0 then
        self.fogReveal = nil
        if reveal.conceal then
            self:ApplyCoverFog(COVER_FOG_DENSITY)
            print("FeelCalibrate: fog conceal finished")
            local finished = self.onFogCoverFinished
            self.onFogCoverFinished = nil
            if finished then
                finished()
            end
            return
        end
        LookApplier.ApplyAtmosphere(self.scene, CHAPTER1_ATMOSPHERE)
        self.inputLocked = false
        self.uiOpacity = 1.0
        self:ApplyUiOpacity()
        print("FeelCalibrate: fog reveal finished")
    end
end

function FeelCalibrate:BeginConfirm()
    if self.inputLocked then
        return
    end
    if self.fogReveal and self.fogReveal.conceal then
        return
    end
    ControlSettings.SetCalibrated(true, true)
    Sfx.PlayModalClick()
    print("FeelCalibrate: confirm")
    self:BeginFogConceal()
end

function FeelCalibrate:Start()
    local loaded, loadError = self:LoadDocument()
    if not loaded then
        print("FeelCalibrate: load failed " .. tostring(loadError))
        if self.onFinished then
            self.onFinished()
        end
        return false
    end
    local created, createError = self:CreateScene()
    if not created then
        print("FeelCalibrate: scene failed " .. tostring(createError))
        if self.onFinished then
            self.onFinished()
        end
        return false
    end
    self:BuildUI()
    self:ApplyModeVisual()
    print("FeelCalibrate: started mode=" .. ControlSettings.RotateMode())
    return true
end

function FeelCalibrate:Update(timeStep)
    PointerInput.BeginFrame()
    self:UpdateFog(timeStep)
    if self.inputLocked then
        return
    end
    if self.rotatorController then
        self.rotatorController:Update(timeStep)
    end
    if self.sliderRow and self.sliderRow.slider and self.sliderRow.slider.Update then
        self.sliderRow.slider:Update(timeStep)
    end
    if self.confirmItem and self.confirmItem.Update then
        self.confirmItem:Update(timeStep)
    end
    self:UpdateModeTween(timeStep)
end

function FeelCalibrate:Stop()
    if self.root then
        UI.SetRoot(nil, true)
    end
    self.root = nil
    self.uiPanel = nil
    self.veil = nil
    self.sliderRow = nil
    self.confirmItem = nil
    if self.rotatorController then
        self.rotatorController:RestoreAuthoredStates()
        self.rotatorController = nil
    end
    self.partRenderer = nil
    self.levelDocument = nil
    if self.scene then
        self.scene:Clear()
        self.scene = nil
    end
    self.camera = nil
    self.cameraNode = nil
    self.viewport = nil
    print("FeelCalibrate: stopped")
end

return FeelCalibrate
