-- 路径点击反馈：单例六边形环迸发，可达时中心再留一个 spot。
-- 只服务 GamePreview 表现层，不参与 Path Graph。

local ClickFeedbackVfx = {}
ClickFeedbackVfx.__index = ClickFeedbackVfx

local RING_DURATION = 0.6
local RING_RADIUS = 0.5
local RING_WIDTH_START = 0.2
local SPOT_SCALE = 0.2
local SPOT_FADE_START = 0.1
local SPOT_FADE_END = 0.4
local LIFT = 0.03
local SHADER_PATH = "Shaders/BLGL/ClickFeedback.shader"

local RING_COLOR = Color(0.96, 0.90, 0.82, 1.0)
local SPOT_BLACK = Color(0.08, 0.07, 0.06, 1.0)
local SPOT_WHITE = Color(0.98, 0.96, 0.92, 1.0)

local function EaseOutExpo(t)
    if t >= 1.0 then
        return 1.0
    end
    if t <= 0.0 then
        return 0.0
    end
    return 1.0 - 2.0 ^ (-10.0 * t)
end

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

local function HexPoint(radius, index)
    local angle = (index - 1) * math.pi / 3.0
    return Vector3(math.cos(angle) * radius, 0.0, -math.sin(angle) * radius)
end

local function AddTriangle(geometry, a, b, c, normal)
    geometry:DefineVertex(a)
    geometry:DefineNormal(normal)
    geometry:DefineVertex(b)
    geometry:DefineNormal(normal)
    geometry:DefineVertex(c)
    geometry:DefineNormal(normal)
end

local function FillRing(geometry, outerRadius, width)
    local innerRadius = math.max(outerRadius - width, 0.0001)
    geometry:SetNumGeometries(1)
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local up = Vector3.UP
    for index = 1, 6 do
        local nextIndex = index % 6 + 1
        local outerA = HexPoint(outerRadius, index)
        local outerB = HexPoint(outerRadius, nextIndex)
        local innerA = HexPoint(innerRadius, index)
        local innerB = HexPoint(innerRadius, nextIndex)
        AddTriangle(geometry, innerA, outerA, outerB, up)
        AddTriangle(geometry, innerA, outerB, innerB, up)
    end
    geometry:Commit()
end

local function FillSpot(geometry, radius)
    geometry:SetNumGeometries(1)
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local up = Vector3.UP
    local center = Vector3.ZERO
    for index = 1, 6 do
        local nextIndex = index % 6 + 1
        AddTriangle(geometry, center, HexPoint(radius, index), HexPoint(radius, nextIndex), up)
    end
    geometry:Commit()
end

local function CreateMaterial(color)
    local material = Material:new()
    if not material:SetSurfaceShader(SHADER_PATH) then
        print("ClickFeedbackVfx: failed to load " .. SHADER_PATH)
        material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        material:SetShaderParameter("MatDiffColor", Variant(color))
        return material
    end
    material:SetShaderParameter("base_color", Variant(color))
    material:SetRenderOrder(255)
    return material
end

local function FaceRotation(normal)
    local up = normal and CopyVector(normal) or Vector3.UP
    if up:Length() < 0.001 then
        up = Vector3.UP
    else
        up = up:Normalized()
    end
    local tangent = Vector3.FORWARD - up * Vector3.FORWARD:DotProduct(up)
    if tangent:Length() < 0.001 then
        tangent = Vector3.RIGHT - up * Vector3.RIGHT:DotProduct(up)
    end
    local rotation = Quaternion()
    rotation:FromLookRotation(tangent:Normalized(), up)
    return rotation
end

function ClickFeedbackVfx.New()
    local self = setmetatable({}, ClickFeedbackVfx)
    ---@type Scene|nil
    self.scene = nil
    ---@type Node|nil
    self.node = nil
    ---@type Node|nil
    self.ringNode = nil
    ---@type Node|nil
    self.spotNode = nil
    ---@type CustomGeometry|nil
    self.ringGeometry = nil
    ---@type CustomGeometry|nil
    self.spotGeometry = nil
    self.ringMaterial = nil
    self.spotMaterial = nil
    self.elapsed = 0.0
    self.reachable = false
    ---@type string|nil
    self.targetKey = nil
    self.ringFinished = false
    self.ringRadius = RING_RADIUS
    return self
end

function ClickFeedbackVfx:Ensure(scene)
    if self.node and self.scene == scene then
        return true
    end
    self:Destroy()
    if not scene then
        return false
    end
    self.scene = scene
    self.node = scene:CreateChild("PathClickFeedback")
    self.ringNode = self.node:CreateChild("Ring")
    self.spotNode = self.node:CreateChild("Spot")
    self.ringGeometry = self.ringNode:CreateComponent("CustomGeometry")
    self.spotGeometry = self.spotNode:CreateComponent("CustomGeometry")
    self.ringMaterial = CreateMaterial(RING_COLOR)
    self.spotMaterial = CreateMaterial(SPOT_BLACK)
    self.ringGeometry:SetMaterial(self.ringMaterial)
    self.spotGeometry:SetMaterial(self.spotMaterial)
    FillSpot(self.spotGeometry, RING_RADIUS)
    self.spotGeometry:SetMaterial(self.spotMaterial)
    self.ringNode.enabled = false
    self.spotNode.enabled = false
    self.node.enabled = false
    return true
end

function ClickFeedbackVfx:Play(scene, record, reachable, radius)
    if not record or not record.worldPoint then
        return false
    end
    if not self:Ensure(scene) then
        return false
    end
    local normal = record.worldNormal or Vector3.UP
    self.ringRadius = tonumber(radius) or RING_RADIUS
    if self.ringRadius <= 0.0 then
        self.ringRadius = RING_RADIUS
    end
    self.node.position = record.worldPoint + CopyVector(normal) * LIFT
    self.node.rotation = FaceRotation(normal)
    self.elapsed = 0.0
    self.reachable = reachable == true
    self.targetKey = record.key
    self.ringFinished = false
    self.node.enabled = true
    self.ringNode.scale = Vector3.ONE
    self:ApplyRing(0.0)
    self.spotNode.enabled = self.reachable
    if self.reachable then
        local spotRadius = self.ringRadius * SPOT_SCALE
        self.spotNode.scale = Vector3(spotRadius, 1.0, spotRadius)
        self.spotMaterial:SetShaderParameter("base_color", Variant(SPOT_BLACK))
        self.spotGeometry:SetMaterial(self.spotMaterial)
    end
    print(string.format(
        "ClickFeedbackVfx: play reachable=%s key=%s radius=%.2f",
        tostring(self.reachable),
        tostring(self.targetKey),
        self.ringRadius
    ))
    return true
end

function ClickFeedbackVfx:ApplyRing(time)
    local t = math.min(1.0, time / RING_DURATION)
    local scale = EaseOutExpo(t)
    local width = RING_WIDTH_START * (1.0 - t)
    if t >= 1.0 or width <= 0.0005 or scale <= 0.0005 then
        if t >= 1.0 or width <= 0.0005 then
            self.ringNode.enabled = false
            self.ringFinished = true
        end
        return
    end
    local outer = self.ringRadius * scale
    if width >= outer then
        width = outer * 0.99
    end
    self.ringNode.enabled = true
    FillRing(self.ringGeometry, outer, width)
    self.ringGeometry:SetMaterial(self.ringMaterial)
end

function ClickFeedbackVfx:ApplySpot(time)
    if not self.reachable or not self.spotNode or not self.spotNode.enabled then
        return
    end
    local color = SPOT_BLACK
    if time >= SPOT_FADE_END then
        color = SPOT_WHITE
    elseif time >= SPOT_FADE_START then
        local u = (time - SPOT_FADE_START) / (SPOT_FADE_END - SPOT_FADE_START)
        color = Color(
            SPOT_BLACK.r + (SPOT_WHITE.r - SPOT_BLACK.r) * u,
            SPOT_BLACK.g + (SPOT_WHITE.g - SPOT_BLACK.g) * u,
            SPOT_BLACK.b + (SPOT_WHITE.b - SPOT_BLACK.b) * u,
            1.0
        )
    end
    self.spotMaterial:SetShaderParameter("base_color", Variant(color))
end

function ClickFeedbackVfx:Update(timeStep)
    if not self.node or not self.node.enabled then
        return
    end
    self.elapsed = self.elapsed + timeStep
    if not self.ringFinished then
        self:ApplyRing(self.elapsed)
    end
    if self.reachable then
        self:ApplySpot(self.elapsed)
        return
    end
    if self.ringFinished then
        self.node.enabled = false
    end
end

function ClickFeedbackVfx:NotifyArrived(nodeKey)
    if not self.reachable then
        return false
    end
    if self.targetKey ~= nodeKey then
        return false
    end
    print("ClickFeedbackVfx: spot cleared at " .. tostring(nodeKey))
    if self.spotNode then
        self.spotNode.enabled = false
    end
    self.reachable = false
    if self.ringFinished and self.node then
        self.node.enabled = false
    end
    self.targetKey = nil
    return true
end

function ClickFeedbackVfx:Destroy()
    if self.node then
        self.node:Remove()
    end
    self.scene = nil
    self.node = nil
    self.ringNode = nil
    self.spotNode = nil
    self.ringGeometry = nil
    self.spotGeometry = nil
    self.ringMaterial = nil
    self.spotMaterial = nil
    self.targetKey = nil
    self.reachable = false
    self.ringFinished = false
end

return ClickFeedbackVfx
