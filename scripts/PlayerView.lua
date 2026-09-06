-- 玩家表现层。
-- 用导入的 Player.mdl；世界位姿由 Walker 驱动。
-- 模型本地朝向与 Walker Forward 相反，Mesh 绕 Y 转 180°。
-- Cloak 是独立几何体，走路时绕模型 X 轴摆动。
-- topmost 走无深度测试的纯色 shader，候选路径上保持可见。

local PlayerView = {}
PlayerView.__index = PlayerView

local MODEL_PATH = "Meshes/Player.mdl"
-- 旧胶囊大约一个三棱柱高；导入模型约 1.34m，缩到同尺度。
local TARGET_HEIGHT = 0.58
local FACE_YAW = 180.0
local CLOAK_VERTEX_COUNT = 10
local CLOAK_PIVOT = Vector3(0.0, 1.02, 0.0)
local CLOAK_WALK_BASE = 0.28
local CLOAK_WALK_SWING = 0.18
local CLOAK_SWING_RATE = 9.0
local CLOAK_FOLLOW = 10.0
local NORMAL_SHADER = "Shaders/BLGL/PlayerSolid.shader"
local TOPMOST_SHADER = "Shaders/BLGL/PlayerSolidTopmost.shader"
local CLOAK_SHADER = "Shaders/BLGL/PlayerCloak.shader"
local CLOAK_TOPMOST_SHADER = "Shaders/BLGL/PlayerCloakTopmost.shader"
local SLOT_COLORS = {
    Color(0.234497, 0.672245, 0.684455, 1.0),
    Color(0.61092, 0.238724, 0.0336636, 1.0),
    Color(0.800007, 0.571508, 0.2597, 1.0),
    Color(0.214029, 0.0960783, 0.0572623, 1.0),
}

local function FindCloakGeometryIndex(model)
    local bestIndex = 0
    local bestDelta = 999999
    local geoCount = model:GetNumGeometries()
    for geoIndex = 0, geoCount - 1 do
        local geometry = model:GetGeometry(geoIndex, 0)
        local vertexCount = 0
        if geometry then
            vertexCount = geometry:GetVertexCount()
        end
        local delta = math.abs(vertexCount - CLOAK_VERTEX_COUNT)
        if delta < bestDelta then
            bestDelta = delta
            bestIndex = geoIndex
        end
    end
    return bestIndex
end

local function CreateColorMaterial(shaderPath, color, topmost)
    local material = Material:new()
    if not material:SetSurfaceShader(shaderPath) then
        error("failed to load " .. shaderPath)
    end
    material:SetShaderParameter("base_color", Variant(color))
    if topmost then
        material:SetRenderOrder(255)
    end
    return material
end

function PlayerView.New(scene, topmost)
    local self = setmetatable({}, PlayerView)
    self.scene = scene
    self.topmost = topmost == true
    self.node = scene:CreateChild(self.topmost and "PreviewPlayerTopmost" or "PreviewPlayer")
    self.node.position = Vector3.ZERO
    self.node.rotation = Quaternion()
    self.cloakAngle = 0.0
    self.cloakClock = 0.0
    ---@type Material|nil
    self.cloakMaterial = nil

    local model = cache:GetResource("Model", MODEL_PATH)
    if not model then
        error("PlayerView: missing " .. MODEL_PATH)
    end
    local bounds = model.boundingBox
    local height = bounds.max.y - bounds.min.y
    if height < 0.001 then
        height = TARGET_HEIGHT
    end
    local scale = TARGET_HEIGHT / height
    local mesh = self.node:CreateChild("Mesh")
    mesh.position = Vector3(0.0, -bounds.min.y * scale, 0.0)
    mesh.rotation = Quaternion(FACE_YAW, Vector3.UP)
    mesh.scale = Vector3(scale, scale, scale)
    local drawable = mesh:CreateComponent("StaticModel")
    drawable:SetModel(model)
    drawable.castShadows = false
    local cloakGeoIndex = FindCloakGeometryIndex(model)
    local geoCount = drawable:GetNumGeometries()
    for geoIndex = 0, geoCount - 1 do
        local color = SLOT_COLORS[geoIndex + 1] or SLOT_COLORS[1]
        local isCloak = geoIndex == cloakGeoIndex
        local shaderPath = NORMAL_SHADER
        if isCloak then
            shaderPath = self.topmost and CLOAK_TOPMOST_SHADER or CLOAK_SHADER
        elseif self.topmost then
            shaderPath = TOPMOST_SHADER
        end
        local material = CreateColorMaterial(shaderPath, color, self.topmost)
        if isCloak then
            material:SetShaderParameter("cloak_pivot", Variant(CLOAK_PIVOT))
            material:SetShaderParameter("cloak_angle", Variant(0.0))
            self.cloakMaterial = material
        end
        drawable:SetMaterial(geoIndex, material)
    end
    print(string.format(
        "PlayerView: created in %s model=%s geos=%d scale=%.3f height=%.3f faceYaw=%.0f cloakGeo=%d",
        self.topmost and "topmost" or "normal",
        MODEL_PATH,
        geoCount,
        scale,
        height * scale,
        FACE_YAW,
        cloakGeoIndex
    ))
    return self
end

function PlayerView:UpdateCloak(walking, timeStep)
    local dt = timeStep or 0.016
    if dt < 0.0 then
        dt = 0.0
    end
    if walking then
        self.cloakClock = self.cloakClock + dt
        local swing = math.sin(self.cloakClock * CLOAK_SWING_RATE) * CLOAK_WALK_SWING
        local target = CLOAK_WALK_BASE + swing
        local t = 1.0 - math.exp(-CLOAK_FOLLOW * math.max(dt, 0.0001))
        self.cloakAngle = self.cloakAngle + (target - self.cloakAngle) * t
    else
        self.cloakClock = 0.0
        local t = 1.0 - math.exp(-CLOAK_FOLLOW * math.max(dt, 0.0001))
        self.cloakAngle = self.cloakAngle + (0.0 - self.cloakAngle) * t
    end
    if self.cloakMaterial then
        self.cloakMaterial:SetShaderParameter("cloak_angle", Variant(self.cloakAngle))
    end
end

function PlayerView:Apply(position, rotation, walking, timeStep)
    if not self.node then
        return
    end
    self.node.position = position
    self.node.rotation = rotation
    self:UpdateCloak(walking == true, timeStep)
end

function PlayerView:SetVisible(visible)
    if not self.node then
        return false
    end
    self.node.enabled = visible ~= false
    return true
end

function PlayerView:Destroy()
    if self.node then
        self.node:Remove()
        self.node = nil
    end
    self.cloakMaterial = nil
end

return PlayerView
