-- 自研 stencil 实验：离屏 RT 覆盖图 + 右下角预览。
-- 不接玩法。RT 挂在 RenderSurface 上，先于屏幕 Viewport 更新；屏幕只画可见世界。

local AlgernonView = require "AlgernonView"
local LookApplier = require "LookApplier"
local StillModelCatalog = require "StillModelCatalog"

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
---@field algernonClipMaterials Material[]
---@field quadModel StaticModel|nil
---@field rtWidth integer
---@field rtHeight integer
---@field yaw number
---@field pitch number
local StencilRtLab = {}
StencilRtLab.__index = StencilRtLab

local MASK_BIT = 1
local WORLD_BIT = 2
local PREVIEW_HEIGHT = 180
local CAMERA_SPEED = 10.0
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

local function HexToColor(hex, fallback)
    if type(hex) ~= "string" then
        return fallback
    end
    local cleaned = hex:gsub("#", "")
    if #cleaned ~= 6 and #cleaned ~= 8 then
        return fallback
    end
    local r = tonumber(cleaned:sub(1, 2), 16)
    local g = tonumber(cleaned:sub(3, 4), 16)
    local b = tonumber(cleaned:sub(5, 6), 16)
    if not r or not g or not b then
        return fallback
    end
    return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
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
    ---@type Material[]
    self.algernonClipMaterials = {}
    ---@type StaticModel|nil
    self.quadModel = nil
    self.rtWidth = 0
    self.rtHeight = 0
    self.yaw = 0.0
    self.pitch = 8.0
    return self
end

local function CurrentViewportSize()
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()
    if width < 8 then
        width = 8
    end
    if height < 8 then
        height = 8
    end
    return width, height
end

function StencilRtLab:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    local atmosphere = LookApplier.CopyAtmosphere(LookApplier.DefaultAtmosphere())
    -- 实验室天空用近距雾色顶成蓝；不新建 Zone，避免盖掉 LightGroup。
    atmosphere.fog.color = "#5BA3E8"
    atmosphere.fog.start = 8.0
    atmosphere.fog.finish = 40.0
    LookApplier.ApplyAtmosphere(self.scene, atmosphere)
    renderer.hdrRendering = false
    self:LockSkyboxToWorld()
end

function StencilRtLab:LockSkyboxToWorld()
    if not self.scene then
        return
    end
    local skyboxes = self.scene:GetComponents("Skybox", true)
    local count = 0
    for _, skybox in ipairs(skyboxes or {}) do
        skybox.viewMask = WORLD_BIT
        count = count + 1
    end
    print("StencilRtLab: locked Skybox viewMask count=" .. tostring(count))
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
            command.useFogColor = false
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
    local width, height = CurrentViewportSize()
    self.rtTexture = Texture2D:new()
    self.rtTexture:SetNumLevels(1)
    self.rtTexture:SetFilterMode(FILTER_NEAREST)
    self.rtTexture:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    self.rtTexture:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    -- 格式查询是 Graphics 类静态方法；用实例 graphics: 会把 userdata 当成 self 传进去。
    local created = self.rtTexture:SetSize(width, height, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    if not created then
        print("StencilRtLab: failed to create color RT")
        return false
    end

    self.rtDepth = Texture2D:new()
    self.rtDepth:SetNumLevels(1)
    local depthCreated = self.rtDepth:SetSize(
        width,
        height,
        Graphics:GetDepthStencilFormat(),
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
    self.rtWidth = width
    self.rtHeight = height
    print(string.format("StencilRtLab: RT %dx%d color+depth created", width, height))
    return true
end

function StencilRtLab:ResizeRtIfNeeded()
    if not self.rtTexture or not self.rtDepth then
        return
    end
    local width, height = CurrentViewportSize()
    if width == self.rtWidth and height == self.rtHeight then
        return
    end
    local colorOk = self.rtTexture:SetSize(width, height, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    local depthOk = self.rtDepth:SetSize(width, height, Graphics:GetDepthStencilFormat(), TEXTURE_DEPTHSTENCIL)
    if not colorOk or not depthOk then
        print(string.format("StencilRtLab: RT resize failed %dx%d", width, height))
        return
    end
    local surface = self.rtTexture:GetRenderSurface()
    surface:SetLinkedDepthStencil(self.rtDepth:GetRenderSurface())
    if self.rtViewport then
        surface:SetViewport(0, self.rtViewport)
    end
    surface:SetUpdateMode(SURFACE_UPDATEALWAYS)
    self.rtWidth = width
    self.rtHeight = height
    self:BindMaskToMaterials()
    self:SyncPreviewSize()
    print(string.format("StencilRtLab: RT resized to %dx%d", width, height))
end

function StencilRtLab:CreateWorld()
    local floorNode = self.scene:CreateChild("Floor")
    floorNode.position = Vector3(0.0, -0.05, 0.0)
    floorNode.scale = Vector3(12.0, 0.1, 12.0)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(CreateUnlitMaterial(Color(1.0, 0.88, 0.18, 1.0)))
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
    self.algernonView:SetLocalTransform({ scale = 2.5 })
    self.algernonView:Apply(Vector3(0.0, 0.0, 1.2), Quaternion(180.0, Vector3.UP))
    self.algernonView:SetVisible(true)
    self:SetSubtreeViewMask(self.algernonView.node, WORLD_BIT)
    self:ApplyAlgernonClipMaterials()
    print("StencilRtLab: floor + mask quad + algernon created")
end

function StencilRtLab:BindMaskToMaterials()
    local rtTexture = self.rtTexture
    if not rtTexture then
        return
    end
    for _, material in ipairs(self.algernonClipMaterials) do
        material:SetSurfaceTexture("mask_rt", rtTexture)
        material:SetShaderParameter("clip_threshold", Variant(0.5))
    end
end

function StencilRtLab:ApplyAlgernonClipMaterials()
    self.algernonClipMaterials = {}
    local view = self.algernonView
    if not view or not view.runtime or not view.runtime.model then
        print("StencilRtLab: algernon runtime missing, skip clip shader")
        return
    end
    local model = view.runtime.model
    -- Material 没有 GetShaderParameter；槽色从资产 look 读。
    for _, slot in ipairs(view.runtime.asset.slots or {}) do
        local look = StillModelCatalog.SlotLook(view.runtime.asset, slot, view.dummyObject:GetActiveParams())
        local material = Material:new()
        if not material:SetSurfaceShader("Shaders/BLGL/AlgernonRtClip.shader") then
            print("StencilRtLab: failed to load AlgernonRtClip.shader")
            return
        end
        material:SetShaderParameter("base_color", Variant(HexToColor(look.color or look.baseColor, Color(0.957, 0.945, 0.918, 1.0))))
        local technique = material:GetTechnique(0)
        if technique and technique:HasPass("base") then
            local pass = technique:GetPass("base")
            pass:SetDepthWrite(true)
            pass:SetBlendMode(BLEND_REPLACE)
        end
        self.algernonClipMaterials[#self.algernonClipMaterials + 1] = material
        model:SetMaterial(slot.index, material)
    end
    self:BindMaskToMaterials()
    print("StencilRtLab: algernon clip materials=" .. tostring(#self.algernonClipMaterials))
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
    self.preview:SetAlignment(HA_RIGHT, VA_BOTTOM)
    self.preview:SetPosition(-16, -16)
    ui.root:AddChild(self.preview)
    self:SyncPreviewSize()

    self.hintLabel = Text:new()
    self.hintLabel:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
    self.hintLabel.color = Color(0.92, 0.90, 0.84)
    self.hintLabel.text = "Stencil RT Lab  WASD 移动  右键观察  Space/C 升降  右下角=RT"
    self.hintLabel:SetAlignment(HA_LEFT, VA_TOP)
    self.hintLabel:SetPosition(16, 12)
    ui.root:AddChild(self.hintLabel)
    print("StencilRtLab: RT preview attached to ui.root")
end

function StencilRtLab:SyncPreviewSize()
    if not self.preview or self.rtWidth <= 0 or self.rtHeight <= 0 then
        return
    end
    local height = PREVIEW_HEIGHT
    local width = math.floor(height * self.rtWidth / self.rtHeight + 0.5)
    if width < 8 then
        width = 8
    end
    self.preview:SetSize(width, height)
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
    -- 飞跃式：WASD 沿水平面移动，不跟着俯仰钻进地面。
    local rotation = self.cameraNode.rotation
    local rawForward = rotation * Vector3.FORWARD
    local planarForward = Vector3(rawForward.x, 0.0, rawForward.z)
    local forward = planarForward:Length() < 0.001 and Vector3.FORWARD or planarForward:Normalized()
    local rawRight = Vector3.UP:CrossProduct(forward)
    local right = rawRight:Length() < 0.001 and Vector3.RIGHT or rawRight:Normalized()
    local move = Vector3.ZERO
    if input:GetKeyDown(KEY_W) then
        move = move + forward
    end
    if input:GetKeyDown(KEY_S) then
        move = move - forward
    end
    if input:GetKeyDown(KEY_A) then
        move = move - right
    end
    if input:GetKeyDown(KEY_D) then
        move = move + right
    end
    if move:Length() > 0.001 then
        self.cameraNode:Translate(move:Normalized() * dt * speed, TS_WORLD)
    end
    if input:GetKeyDown(KEY_SPACE) then
        self.cameraNode:Translate(Vector3(0.0, 1.0, 0.0) * dt * speed, TS_WORLD)
    end
    if input:GetKeyDown(KEY_C) then
        self.cameraNode:Translate(Vector3(0.0, -1.0, 0.0) * dt * speed, TS_WORLD)
    end
    self:SyncRtCamera()
end

function StencilRtLab:HandleScreenMode()
    self:ResizeRtIfNeeded()
end

function StencilRtLab:Update(dt)
    self:ResizeRtIfNeeded()
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
    self.algernonClipMaterials = {}
    print("StencilRtLab: stopped")
end

return StencilRtLab
