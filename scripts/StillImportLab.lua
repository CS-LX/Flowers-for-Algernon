-- 静物导入装配实验：Door.fbx -> Door.mdl。
-- 优先播导入的开门 .ani（SetTime 0~1）；没有 .ani 时直接移 DoorOpener 骨头。

local UI = require("urhox-libs/UI")
local LookApplier = require "LookApplier"
local FixedGameCamera = require "FixedGameCamera"

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
---@type AnimatedModel|nil
local doorModel_ = nil
---@type Node|nil
local openerBoneNode_ = nil
---@type AnimationController|nil
local animCtrl_ = nil
---@type string|nil
local openAnimName_ = nil
---@type number
local openAnimLength_ = 1.0
---@type Label|nil
local statusLabel_ = nil
---@type Slider|nil
local morphSlider_ = nil

local openAmount_ = 0.0
local yawOrbit_ = 0.0
local OPEN_DISTANCE = 2.8
local OPENER_BONE_NAME = "DoorBone"
local OPEN_ANIM_CANDIDATES = {
    "Animations/Door/DoorOpenerAnim.ani",
    "Animations/Door/DoorOpener_DoorOpenerAnim.ani",
    "Animations/Door/Open.ani",
}

local LEVEL_ATMOSPHERE_PATH = "levels/default-level.json"
local DOOR_MODEL_PATH = "Meshes/Door.mdl"

local CAMERA = {
    pitch = 30.0,
    orthoSize = 8.0,
    target = { x = 0.0, y = 1.4, z = 0.0 },
    nearClip = 0.1,
    farClip = 100.0,
}

-- import-model 日志：geo0=Door, geo1=Frame, geo2=Light, geo3=Lit
local SLOT_LOOKS = {
    [0] = {
        name = "Door",
        look = {
            shader = LookApplier.SHADER_TRI_PRISM_LOOK,
            colorNeg = "#1E5FA8",
            colorMid = "#3D8FD4",
            colorPos = "#8ED4FF",
            emissionStrength = 0.0,
        },
    },
    [1] = {
        name = "Frame",
        look = {
            shader = LookApplier.SHADER_TRI_PRISM_LOOK,
            colorNeg = "#8F8478",
            colorMid = "#C4B6A6",
            colorPos = "#F1E6D5",
            emissionStrength = 0.0,
        },
    },
    [2] = {
        name = "Light",
        look = {
            shader = LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG,
            colorNeg = "#D8C7A2",
            colorMid = "#F4E7C8",
            colorPos = "#FFF8E8",
            fogColor = "#82F0FF",
            fogHeightA = 2.4,
            fogHeightB = 0.0,
            emissionColor = "#FFF4D2",
            emissionStrength = 0.8,
        },
    },
    [3] = {
        name = "Lit",
        look = {
            shader = LookApplier.SHADER_TRI_PRISM_LOOK,
            colorNeg = "#C48A2A",
            colorMid = "#F0C14A",
            colorPos = "#FFE7A0",
            emissionColor = "#FFD27A",
            emissionStrength = 0.55,
        },
    },
}

local function LoadLevelAtmosphere()
    local atmosphere = LookApplier.DefaultAtmosphere()
    if not fileSystem:FileExists(LEVEL_ATMOSPHERE_PATH) then
        print("StillImportLab: missing " .. LEVEL_ATMOSPHERE_PATH .. ", using default atmosphere")
        return atmosphere
    end
    local file = File(LEVEL_ATMOSPHERE_PATH, FILE_READ)
    if not file:IsOpen() then
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

local function FindOpenerBone(anim)
    local skeleton = anim:GetSkeleton()
    if not skeleton then
        return nil
    end
    local named = skeleton:GetBone(OPENER_BONE_NAME)
    if named and named.node then
        return named.node
    end
    for index = 0, skeleton:GetNumBones() - 1 do
        local bone = skeleton:GetBone(index)
        if bone and bone.node and bone.name == OPENER_BONE_NAME then
            return bone.node
        end
    end
    return nil
end

local function FindOpenAnimation()
    for _, path in ipairs(OPEN_ANIM_CANDIDATES) do
        if fileSystem:FileExists(path) then
            local animation = cache:GetResource("Animation", path)
            if animation then
                return path, animation.length
            end
        end
    end
    print("StillImportLab: no open .ani on disk, skip Animation resource load")
    return nil, 1.0
end

local function ApplyOpenAmount(amount)
    openAmount_ = math.max(0.0, math.min(1.0, amount))
    local mode = "none"
    if animCtrl_ and openAnimName_ then
        animCtrl_:SetTime(openAnimName_, openAmount_ * openAnimLength_)
        mode = "ani"
    elseif openerBoneNode_ then
        openerBoneNode_.position = Vector3(0, OPEN_DISTANCE * openAmount_, 0)
        mode = "bone"
    end
    if doorModel_ then
        local lightMat = doorModel_:GetMaterial(2)
        if lightMat then
            lightMat:SetShaderParameter("emission_strength", Variant(0.15 + 0.85 * openAmount_))
            lightMat:SetShaderParameter("hover_amount", Variant(openAmount_))
        end
    end
    if statusLabel_ then
        if mode == "ani" then
            statusLabel_:SetText(string.format(
                "Open = %.2f  动画 %s  t=%.3fs / %.3fs",
                openAmount_,
                openAnimName_,
                openAmount_ * openAnimLength_,
                openAnimLength_
            ))
        elseif mode == "bone" then
            statusLabel_:SetText(string.format(
                "Open = %.2f  无 .ani，直接移 %s  Y=%.2fm",
                openAmount_,
                OPENER_BONE_NAME,
                OPEN_DISTANCE * openAmount_
            ))
        else
            statusLabel_:SetText("既没有开门动画，也没有 DoorOpener 骨骼")
        end
    end
    print(string.format("StillImportLab: openAmount=%.2f mode=%s", openAmount_, mode))
end

local function CreateDoor()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    local resource = cache:GetResource("Model", DOOR_MODEL_PATH)
    if not resource then
        error("StillImportLab: missing " .. DOOR_MODEL_PATH)
    end
    local skeleton = resource:GetSkeleton()
    print(string.format(
        "StillImportLab: %s geos=%d bones=%s bbox=(%.3f,%.3f,%.3f)",
        DOOR_MODEL_PATH,
        resource:GetNumGeometries(),
        tostring(skeleton and skeleton:GetNumBones()),
        resource.boundingBox.size.x,
        resource.boundingBox.size.y,
        resource.boundingBox.size.z
    ))

    doorRoot_ = scene_:CreateChild("NarrativeDoor")
    -- FBX 默认导入后高度沿 -Z；绕 X 转 90° 立到 Y-up。
    doorRoot_.rotation = Quaternion(90, Vector3.RIGHT)
    doorRoot_.position = Vector3(0, 0, 0)

    local anim = doorRoot_:CreateComponent("AnimatedModel")
    anim:SetModel(resource)
    openerBoneNode_ = FindOpenerBone(anim)
    animCtrl_ = doorRoot_:CreateComponent("AnimationController")
    openAnimName_, openAnimLength_ = FindOpenAnimation()
    if openAnimName_ and animCtrl_ then
        animCtrl_:Play(openAnimName_, 0, false, 0)
        animCtrl_:SetSpeed(openAnimName_, 0)
        animCtrl_:SetTime(openAnimName_, 0)
        print(string.format("StillImportLab: playing %s length=%.3f", openAnimName_, openAnimLength_))
    else
        print("StillImportLab: no .ani imported; will drive DoorOpener bone directly")
    end
    print(string.format(
        "StillImportLab: openerBone=%s liveBones=%s anim=%s",
        tostring(openerBoneNode_ ~= nil),
        tostring(anim:GetSkeleton() and anim:GetSkeleton():GetNumBones()),
        tostring(openAnimName_)
    ))

    local geoCount = anim:GetNumGeometries()
    for index = 0, geoCount - 1 do
        local slot = SLOT_LOOKS[index]
        local material = LookApplier.CreatePartMaterial(slot and slot.look or LookApplier.DefaultPartLook())
        anim:SetMaterial(index, material)
        print(string.format(
            "StillImportLab: slot %d name=%s shader=%s",
            index,
            slot and slot.name or "unknown",
            slot and slot.look.shader or LookApplier.SHADER_TRI_PRISM_LOOK
        ))
    end
    doorModel_ = anim
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
        text = "Open = 0.00",
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
                        text = "静物导入实验 / Door.fbx",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = { 231, 238, 248, 255 },
                    },
                    UI.Label {
                        text = "4 geometry：0 Door 蓝、1 Frame 石膏、2 Light 雾光、3 Lit 暖光。开门优先用导入的 .ani。",
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
                        text = "拖拽 0~1。RMB 绕门转。O 键开关。本次导入器未写出 .ani 时会退回移骨头。",
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
    graphics.windowTitle = "Still Import Lab — Door.fbx"
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
    print("StillImportLab: FBX Door assembled as one model with 4 material slots.")
end

function StillImportLab.Stop()
    UI.Shutdown()
    openerBoneNode_ = nil
    animCtrl_ = nil
    openAnimName_ = nil
    doorModel_ = nil
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
    if input:GetKeyPress(KEY_O) then
        ApplyOpenAmount(openAmount_ < 0.5 and 1.0 or 0.0)
        if morphSlider_ then
            morphSlider_.props.value = openAmount_
        end
    end
end

return StillImportLab
