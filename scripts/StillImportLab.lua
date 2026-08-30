-- 静物资产绑定实验：Door sidecar -> StillObjectRuntime。
-- 开门走 driver；open <= 0.05 时按 sidecar 隐藏 Light 槽。

local UI = require("urhox-libs/UI")
local LookApplier = require "LookApplier"
local FixedGameCamera = require "FixedGameCamera"
local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"

local StillImportLab = {}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type Node|nil
local doorRoot_ = nil
---@type table|nil
local doorRuntime_ = nil
---@type StillObject?
local doorObject_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Slider|nil
local morphSlider_ = nil

local yawOrbit_ = 0.0
local LEVEL_ATMOSPHERE_PATH = "levels/default-level.json"

local CAMERA = {
    pitch = 30.0,
    orthoSize = 8.0,
    target = { x = 0.0, y = 1.4, z = 0.0 },
    nearClip = 0.1,
    farClip = 100.0,
}

local function LoadLevelAtmosphere()
    local atmosphere = LookApplier.DefaultAtmosphere()
    if not fileSystem:FileExists(LEVEL_ATMOSPHERE_PATH) then
        print("StillImportLab: missing " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local file = File(LEVEL_ATMOSPHERE_PATH, FILE_READ)
    if not file or not file:IsOpen() then
        print("StillImportLab: cannot open " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local json = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, json)
    if not ok or type(data) ~= "table" then
        print("StillImportLab: atmosphere decode failed: " .. tostring(data))
        return atmosphere
    end
    print("StillImportLab: loaded atmosphere from " .. LEVEL_ATMOSPHERE_PATH
        .. " lightGroup=" .. tostring((data.atmosphere or {}).lightGroup))
    return LookApplier.CopyAtmosphere(data.atmosphere)
end

local function ApplyOpenAmount(amount)
    if not doorObject_ or not doorRuntime_ then
        return
    end
    doorObject_:SetDriver("open", amount)
    StillObjectRuntime.ApplyDrivers(doorRuntime_, doorObject_)
    local openAmount = doorObject_:GetDriver("open")
    if statusLabel_ then
        statusLabel_:SetText(string.format(
            "Open = %.2f  Light %s",
            openAmount,
            openAmount > 0.05 and "可见" or "隐藏"
        ))
    end
    print(string.format("StillImportLab: open=%.2f lightVisible=%s", openAmount, tostring(openAmount > 0.05)))
end

local function CreateDoor()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    doorObject_ = StillObject.New({
        id = "lab_door",
        name = "叙事门",
        modelId = "door",
        transform = {
            position = { x = 0, y = 0, z = 0 },
            rotation = { x = 0, y = 0, z = 0 },
            scale = { x = 1, y = 1, z = 1 },
        },
        driverState = { open = 0 },
    })
    doorRoot_ = scene_:CreateChild("NarrativeDoor")
    doorRuntime_ = StillObjectRuntime.Bind(doorRoot_, doorObject_)
    if not doorRuntime_ then
        error("StillImportLab: failed to bind door asset; catalog did not resolve StillModels/Door.json")
    end
    ApplyOpenAmount(0.0)
end

local function CreateGroundMark()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    local node = scene_:CreateChild("AxisMark")
    node.position = Vector3(0, 0.01, 0)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    node.scale = Vector3(6, 1, 6)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Vector4(0.18, 0.22, 0.28, 1)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.85))
    model:SetMaterial(material)
end

local function CreateUI()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    statusLabel_ = UI.Label {
        text = "Open = 0.00  Light 隐藏",
        fontSize = 13,
        fontColor = { 231, 238, 248, 255 },
        whiteSpace = "normal",
    }
    morphSlider_ = UI.Slider {
        value = 0,
        min = 0,
        max = 1,
        step = 0.01,
        width = 220,
        onChange = function(_, value)
            ApplyOpenAmount(value)
        end,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        padding = 16,
        justifyContent = "flex-start",
        alignItems = "flex-start",
        backgroundColor = { 0, 0, 0, 0 },
        children = {
            UI.Panel {
                width = 380,
                padding = 12,
                gap = 8,
                backgroundColor = { 21, 27, 38, 220 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "静物资产绑定 / Door",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = { 231, 238, 248, 255 },
                    },
                    UI.Label {
                        text = "sidecar：门框/门板三色、Lit/Light 色、open driver。open ≤ 0.05 隐藏丁达尔。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = "开门 0~1",
                        fontSize = 12,
                        fontColor = { 231, 238, 248, 255 },
                    },
                    morphSlider_,
                    statusLabel_,
                    UI.Label {
                        text = "拖拽 0~1。RMB 绕门转。O 键开关。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end

local function ApplyCamera()
    local config = {
        pitch = CAMERA.pitch,
        orthoSize = CAMERA.orthoSize,
        target = CAMERA.target,
        nearClip = CAMERA.nearClip,
        farClip = CAMERA.farClip,
    }
    if not cameraNode_ then
        return
    end
    local target, position = FixedGameCamera.GetWorldPosition(config)
    local orbit = Quaternion(yawOrbit_, Vector3.UP)
    local offset = position - target
    cameraNode_.position = target + orbit * offset
    cameraNode_:LookAt(target)
end

function StillImportLab.Start()
    graphics.windowTitle = "Still Import Lab — Door asset"
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    renderer.hdrRendering = false

    LookApplier.ApplyAtmosphere(scene_, LoadLevelAtmosphere())
    cameraNode_, camera_ = FixedGameCamera.Create(scene_, "LabCamera", CAMERA)
    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)

    CreateGroundMark()
    CreateDoor()
    CreateUI()
    ApplyCamera()

    SubscribeToEvent("Update", "HandleStillImportLabUpdate")
    print("StillImportLab: Door bound from StillModels/Door.json")
end

function StillImportLab.Stop()
    UI.Shutdown()
    doorRuntime_ = nil
    doorObject_ = nil
    doorRoot_ = nil
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    viewport_ = nil
    statusLabel_ = nil
    morphSlider_ = nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleStillImportLabUpdate(eventType, eventData)
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mouseMove = input:GetMouseMove()
        yawOrbit_ = yawOrbit_ + mouseMove.x * 0.35
        ApplyCamera()
    end
    if input:GetKeyPress(KEY_O) and doorObject_ then
        local nextValue = doorObject_:GetDriver("open") < 0.5 and 1.0 or 0.0
        ApplyOpenAmount(nextValue)
        if morphSlider_ then
            morphSlider_.props.value = nextValue
        end
    end
end

return StillImportLab
