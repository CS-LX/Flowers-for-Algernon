-- 玩家表现层。
-- 只创建一个给定 Scene 所属的纯色非光照 PlayerView，不持有路径或状态逻辑。

local PlayerView = {}
PlayerView.__index = PlayerView

local BODY_COLOR = Color(0.96, 0.86, 0.36, 1.0)
local HEAD_COLOR = Color(0.98, 0.72, 0.48, 1.0)

local function CreateColorMaterial(name, color, topmost)
    local material = Material:new()
    if not material:SetSurfaceShader("Shaders/BLGL/PlayerSolid.shader") then
        error("failed to load PlayerSolid.shader")
    end
    material:SetShaderParameter("base_color", Variant(color))
    if topmost then
        material:SetRenderOrder(250)
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

    local body = self.node:CreateChild("Body")
    body.position = Vector3(0, 0.22, 0)
    local bodyModel = body:CreateComponent("StaticModel")
    bodyModel.model = CapsuleGeometry(0.16, 0.38, 12, 6):ToModel()
    bodyModel.material = CreateColorMaterial(
        self.topmost and "PlayerViewTopmostBody" or "PlayerViewBody",
        BODY_COLOR,
        self.topmost
    )
    local head = self.node:CreateChild("Head")
    head.position = Vector3(0, 0.46, 0)
    head.scale = Vector3(0.72, 0.72, 0.72)
    local headModel = head:CreateComponent("StaticModel")
    headModel.model = SphereGeometry(0.16, 16, 8):ToModel()
    headModel.material = CreateColorMaterial(
        self.topmost and "PlayerViewTopmostHead" or "PlayerViewHead",
        HEAD_COLOR,
        self.topmost
    )
    return self
end

function PlayerView:Apply(position, rotation)
    if not self.node then
        return
    end
    self.node.position = position
    self.node.rotation = rotation
end

function PlayerView:Destroy()
    if self.node then
        self.node:Remove()
        self.node = nil
    end
end

return PlayerView
