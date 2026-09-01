-- 自研 stencil 实验：离屏 RT 覆盖图 + 右下角预览。
-- 不接玩法。RT 挂在 RenderSurface 上，先于屏幕 Viewport 更新；屏幕只画可见世界。

local AlgernonView = require "AlgernonView"
local LookApplier = require "LookApplier"

---@class StencilRtLab
---@field scene Scene|nil
---@field cameraNode Node|nil
---@field worldCamera Camera|nil
---@field rtCameraNode Node|nil
---@field rtCamera Camera|nil
---@field worldViewport Viewport|nil
---@field rtViewport Viewport|nil
---@field rtTexture Texture2D|nil
---@field rtDepth Texture2D|nil
---@field preview BorderImage|nil
---@field hintLabel Text|nil
---@field algernonView table|nil
---@field quadModel StaticModel|nil
---@field yaw number
---@field pitch number
local StencilRtLab = {}
StencilRtLab.__index = StencilRtLab

local MASK_BIT = 1
local WORLD_BIT = 2
local RT_SIZE = 256
local PREVIEW_SIZE = 180
local CAMERA_SPEED = 8.0
local MOUSE_SENSITIVITY = 0.12

local function CreateUnlitMaterial(color)
    local material = Material:new()
    if not material:SetSurfaceShader("Shaders/BLGL/PlayerSolid.shader") then
        print("StencilRtLab: failed to load PlayerSolid.shader")
        material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        material:SetShaderParameter("MatDiffColor", Variant(color))
        return material
    end
    material:SetShaderParameter("base_color", Variant(color))
    return material
end

local function CopyCamera(source, target)
    target.fov = source.fov
    target.nearClip = source.nearClip
    target.farClip = source.farClip
    target.orthographic = source.orthographic
    target.aspectRatio = source.aspectRatio
end

function StencilRtLab.New()
    local self = setmetatable({}, StencilRtLab)
    ---@type Scene|nil
    self.scene = nil
    ---@type Node|nil
    self.cameraNode = nil
    ---@type Camera|nil
    self.worldCamera = nil
    ---@type Node|nil
    self.rtCameraNode = nil
    ---@type Camera|nil
    self.rtCamera = nil
    ---@type Viewport|nil
    self.worldViewport = nil
    ---@type Viewport|nil
    self.rtViewport = nil
    ---@type Texture2D|nil
    self.rtTexture = nil
    ---@type Texture2D|nil
    self.rtDepth = nil
    ---@type BorderImage|nil
    self.preview = nil
    ---@type Text|nil
    self.hintLabel = nil
    ---@type table|nil
    self.algernonView = nil
    ---@type StaticModel|nil
    self.quadModel = nil
    self.yaw = 0.0
    self.pitch = 8.0
    return self
end

function StencilRtLab:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.scene, LookApplier.DefaultAtmosphere())
    renderer.hdrRendering = false
end

function StencilRtLab:CreateCameras()
    self.cameraNode = self.scene:CreateChild("WorldCamera")
    self.cameraNode.position = Vector3(0.0, 1.6, -6.0)
    self.worldCamera = self.cameraNode:CreateComponent("Camera")
    self.worldCamera.fov = 60.0
    self.worldCamera.nearClip = 0.1
    self.worldCamera.farClip = 200.0
    self.worldCamera.viewMask = WORLD_BIT
    self.cameraNode.rotation = Quaternion(self.pitch, self.yaw, 0.0)

    self.rtCameraNode = self.scene:CreateChild("RtCamera")
    self.rtCamera = self.rtCameraNode:CreateComponent("Camera")
    self.rtCamera.viewMask = MASK_BIT
    self:SyncRtCamera()
end

function StencilRtLab:SyncRtCamera()
    if not self.cameraNode or not self.rtCameraNode or not self.worldCamera or not self.rtCamera then
        return
    end
    self.rtCameraNode.worldPosition = self.cameraNode.worldPosition
    self.rtCameraNode.worldRotation = self.cameraNode.worldRotation
    CopyCamera(self.worldCamera, self.rtCamera)
    self.rtCamera.viewMask = MASK_BIT
end

function StencilRtLab:CreateMaskRenderPath()
    local path = renderer:GetDefaultRenderPath():Clone()
    for index = 0, path:GetNumCommands() - 1 do
        local command = path:GetCommand(index)
        if command.type == CMD_CLEAR then
            command.clearFlags = CLEAR_COLOR | CLEAR_DEPTH | CLEAR_STENCIL
            command.clearColor = Color(0.0, 0.0, 0.0, 1.0)
            command.clearDepth = 1.0
            command.clearStencil = 0
            command.enabled = true
        elseif command.type == CMD_SCENEPASS then
            command.enabled = true
        else
            command.enabled = false
        end
        path:SetCommand(index, command)
    end
    return path
end

function StencilRtLab:CreateRt()
    self.rtTexture = Texture2D:new()
    self.rtTexture:SetNumLevels(1)
    self.rtTexture:SetFilterMode(FILTER_NEAREST)
    self.rtTexture:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    self.rtTexture:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    local created = self.rtTexture:SetSize(RT_SIZE, RT_SIZE, graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    if not created then
        print("StencilRtLab: failed to create color RT")
        return false
    end

    self.rtDepth = Texture2D:new()
    self.rtDepth:SetNumLevels(1)
    local depthCreated = self.rtDepth:SetSize(
        RT_SIZE,
        RT_SIZE,
        graphics:GetDepthStencilFormat(),
        TEXTURE_DEPTHSTENCIL
    )
    if not depthCreated then
        print("StencilRtLab: failed to create depth-stencil RT")
        return false
    end

    local surface = self.rtTexture:GetRenderSurface()
    surface:SetLinkedDepthStencil(self.rtDepth:GetRenderSurface())
    self.rtViewport = Viewport:new(self.scene, self.rtCamera, self:CreateMaskRenderPath())
    surface:SetViewport(0, self.rtViewport)
    surface:SetUpdateMode(SURFACE_UPDATEALWAYS)
    print(string.format("StencilRtLab: RT %dx%d color+depth created", RT_SIZE, RT_SIZE))
    return true
end

function StencilRtLab:CreateWorld()
    local floorNode = self.scene:CreateChild("Floor")
    floorNode.position = Vector3(0.0, -0.05, 0.0)
    floorNode.scale = Vector3(12.0, 0.1, 12.0)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(CreateUnlitMaterial(Color(0.72, 0.68, 0.60, 1.0)))
    floorModel.viewMask = WORLD_BIT
    floorModel.castShadows = false

    local quadNode = self.scene:CreateChild("MaskQuad")
    quadNode.position = Vector3(0.0, 1.1, 0.0)
    quadNode.scale = Vector3(1.6, 2.2, 0.02)
    self.quadModel = quadNode:CreateComponent("StaticModel")
    self.quadModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    -- 面片只进 RT。RT 里画成白覆盖；主视口看不见它。
    self.quadModel:SetMaterial(CreateUnlitMaterial(Color(1.0, 1.0, 1.0, 1.0)))
    self.quadModel.viewMask = MASK_BIT
    self.quadModel.castShadows = false

    self.algernonView = AlgernonView.New(self.scene)
    self.algernonView:Apply(Vector3(0.0, 0.0, 1.2), Quaternion(180.0, Vector3.UP))
    self.algernonView:SetVisible(true)
    local algernonModel = self.algernonView.node:GetComponent("StaticModel", true)
    if algernonModel then
        algernonModel.viewMask = WORLD_BIT
        print("StencilRtLab: algernon viewMask set on first StaticModel")
    end
    self:SetSubtreeViewMask(self.algernonView.node, WORLD_BIT)
    print("StencilRtLab: floor + mask quad + algernon created")
end

---@param node Node
---@param mask integer
function StencilRtLab:SetSubtreeViewMask(node, mask)
    if not node then
        return
    end
    local model = node:GetComponent("StaticModel")
    if model then
        model.viewMask = mask
    end
    local animated = node:GetComponent("AnimatedModel")
    if animated then
        animated.viewMask = mask
    end
    local children = node:GetChildren(true)
    for _, child in ipairs(children or {}) do
        local childModel = child:GetComponent("StaticModel")
        if childModel then
            childModel.viewMask = mask
        end
        local childAnimated = child:GetComponent("AnimatedModel")
        if childAnimated then
            childAnimated.viewMask = mask
        end
    end
end

function StencilRtLab:CreateViewports()
    self.worldViewport = Viewport:new(self.scene, self.worldCamera)
    -- RT 挂在 RenderSurface 上，引擎会在屏幕 Viewport 之前更新它。
    -- 不要把 RT Viewport 塞进 renderer 槽 0，否则用户会先看到整屏黑底白片。
    renderer:SetViewport(0, self.worldViewport)
    renderer:SetNumViewports(1)
    print("StencilRtLab: screen viewport=world, RT updates on RenderSurface first")
end

function StencilRtLab:CreatePreview()
    local rtTexture = self.rtTexture
    if not rtTexture then
        print("StencilRtLab: preview skipped, no RT texture")
        return
    end
    self.preview = BorderImage:new()
    self.preview:SetTexture(rtTexture)
    self.preview:SetFullImageRect()
    self.preview:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
    self.preview:SetAlignment(HA_RIGHT, VA_BOTTOM)
    self.preview:SetPosition(-16, -16)
    ui.root:AddChild(self.preview)

    self.hintLabel = Text:new()
    self.hintLabel:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
    self.hintLabel.color = Color(0.92, 0.90, 0.84)
    self.hintLabel.text = "Stencil RT Lab  WASD 移动  右键观察  Space/C 升降  右下角=RT"
    self.hintLabel:SetAlignment(HA_LEFT, VA_TOP)
    self.hintLabel:SetPosition(16, 12)
    ui.root:AddChild(self.hintLabel)
    print("StencilRtLab: RT preview attached to ui.root")
end

function StencilRtLab:Start()
    graphics.windowTitle = "Stencil RT Lab"
    self:CreateScene()
    self:CreateCameras()
    if not self:CreateRt() then
        return false
    end
    self:CreateWorld()
    self:CreateViewports()
    self:CreatePreview()
    input.mouseMode = MM_FREE
    print("StencilRtLab: started")
    return true
end

function StencilRtLab:HandleCamera(dt)
    if not self.cameraNode then
        return
    end
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local yaw = self.yaw + input.mouseMoveX * MOUSE_SENSITIVITY
        local pitch = self.pitch + input.mouseMoveY * MOUSE_SENSITIVITY
        if pitch < -89.0 then
            pitch = -89.0
        elseif pitch > 89.0 then
            pitch = 89.0
        end
        self.yaw = yaw
        self.pitch = pitch
        self.cameraNode.rotation = Quaternion(self.pitch, self.yaw, 0.0)
    end

    local speed = CAMERA_SPEED
    if input:GetKeyDown(KEY_SHIFT) then
        speed = speed * 2.0
    end
    if input:GetKeyDown(KEY_W) then
        self.cameraNode:Translate(Vector3(0.0, 0.0, 1.0) * dt * speed)
    end
    if input:GetKeyDown(KEY_S) then
        self.cameraNode:Translate(Vector3(0.0, 0.0, -1.0) * dt * speed)
    end
    if input:GetKeyDown(KEY_A) then
        self.cameraNode:Translate(Vector3(-1.0, 0.0, 0.0) * dt * speed)
    end
    if input:GetKeyDown(KEY_D) then
        self.cameraNode:Translate(Vector3(1.0, 0.0, 0.0) * dt * speed)
    end
    if input:GetKeyDown(KEY_SPACE) then
        self.cameraNode:Translate(Vector3(0.0, 1.0, 0.0) * dt * speed, TS_WORLD)
    end
    if input:GetKeyDown(KEY_C) then
        self.cameraNode:Translate(Vector3(0.0, -1.0, 0.0) * dt * speed, TS_WORLD)
    end
    self:SyncRtCamera()
end

function StencilRtLab:Update(dt)
    self:HandleCamera(dt)
    if self.rtTexture then
        local surface = self.rtTexture:GetRenderSurface()
        if surface then
            surface:QueueUpdate()
        end
    end
end

function StencilRtLab:Stop()
    renderer:SetNumViewports(1)
    if self.preview then
        self.preview:Remove()
        self.preview = nil
    end
    if self.hintLabel then
        self.hintLabel:Remove()
        self.hintLabel = nil
    end
    if self.algernonView then
        self.algernonView:Destroy()
        self.algernonView = nil
    end
    if self.scene then
        self.scene:Clear(true, true)
        self.scene = nil
    end
    self.cameraNode = nil
    self.worldCamera = nil
    self.rtCameraNode = nil
    self.rtCamera = nil
    self.worldViewport = nil
    self.rtViewport = nil
    self.rtTexture = nil
    self.rtDepth = nil
    self.quadModel = nil
    print("StencilRtLab: stopped")
end

return StencilRtLab
