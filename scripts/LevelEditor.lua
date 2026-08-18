-- Level Editor 总协调器。
-- 负责关卡级 Part 选择、PartRoot 派生显示与 Level/Part 编辑模式切换。
-- 局部体素编辑仍交给 VoxelSandbox，关卡数据仍由 LevelDocument 持有。

local PartEditSession = require "PartEditSession"
local PartRootRenderer = require "PartRootRenderer"
local LevelEditorUI = require "LevelEditorUI"
local VoxelSandbox = require "VoxelSandbox"

local LevelEditor = {}
---@class LevelEditor
---@field scene Scene
---@field cameraNode Node
---@field camera Camera
---@field debugRenderer DebugRenderer
---@field levelDocument table
---@field edgeLength number
---@field voxelHeight number
---@field partRenderer table
---@field selectedPartId string|nil
---@field mode string
---@field partEditor table|nil
---@field ui table|nil
LevelEditor.__index = LevelEditor

function LevelEditor.New(scene, cameraNode, camera, debugRenderer, levelDocument, edgeLength, voxelHeight)
    local self = setmetatable({}, LevelEditor)
    self.scene = scene
    self.cameraNode = cameraNode
    self.camera = camera
    self.debugRenderer = debugRenderer
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.partRenderer = PartRootRenderer.New(scene, edgeLength, voxelHeight)
    self.selectedPartId = nil
    self.mode = "level"
    self.partEditor = nil
    self.ui = nil
    return self
end

function LevelEditor:Start()
    self:EnterLevelMode()
end

function LevelEditor:GetSelectedPart()
    return self.selectedPartId and self.levelDocument:GetPart(self.selectedPartId) or nil
end

function LevelEditor:SetupLevelCamera()
    local settings = self.levelDocument.fixedCamera
    local pitch = math.rad(settings.pitch)
    local distance = settings.orthoSize * 1.5
    local horizontal = math.cos(pitch) * distance
    local yaw = math.rad(settings.yaw)
    local target = Vector3(settings.target.x, settings.target.y, settings.target.z)
    local offset = Vector3(
        math.sin(yaw) * horizontal,
        math.sin(pitch) * distance,
        -math.cos(yaw) * horizontal
    )
    self.cameraNode.position = target + offset
    self.cameraNode:LookAt(target)
    self.camera.orthographic = true
    self.camera.orthoSize = settings.orthoSize
    self.camera.nearClip = settings.nearClip
    self.camera.farClip = settings.farClip
end

function LevelEditor:EnterLevelMode()
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    self.mode = "level"
    self:SetupLevelCamera()

    local built, errorMessage = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        error(errorMessage)
    end
    if not self.selectedPartId then
        local parts = self.levelDocument:GetParts()
        self.selectedPartId = parts[1] and parts[1].id or nil
    end

    self.ui = LevelEditorUI.New(self)
    self.ui:Build()
    self:RefreshLevelUI("Level View：" .. self.levelDocument.name)
    print("Level Editor: entered level mode")
end

function LevelEditor:SelectPart(partId)
    if not self.levelDocument:GetPart(partId) then
        return false
    end
    self.selectedPartId = partId
    self:RefreshLevelUI("已选择 Part：" .. self:GetSelectedPart().name)
    return true
end

function LevelEditor:RefreshLevelUI(status)
    if self.ui then
        self.ui:Refresh()
        self.ui:SetStatus(status or "Level View")
    end
end

function LevelEditor:OpenSelectedPart()
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local session, errorMessage = PartEditSession.Open(self.partRenderer.grid, part)
    if not session then
        if self.ui then
            self.ui:SetStatus("无法打开 Part：" .. tostring(errorMessage))
        end
        return false
    end

    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
    self.mode = "part"
    self.partEditor = VoxelSandbox.New(
        self.scene,
        self.cameraNode,
        self.camera,
        self.debugRenderer,
        self.edgeLength,
        self.voxelHeight,
        session
    )
    self.partEditor.onBackToLevel = function()
        self:BackToLevel()
    end
    self.partEditor:Start()
    print("Level Editor: opened Part " .. part.name)
    return true
end

function LevelEditor:BackToLevel()
    if self.mode ~= "part" or not self.partEditor then
        return false
    end
    self.partEditor:SaveDocument()
    self:EnterLevelMode()
    return true
end

function LevelEditor:RotateSelectedPart()
    local part = self:GetSelectedPart()
    if not part or not part:HasBehavior("rotator") then
        return false
    end
    local nextStep = (part.transform.rotation.yawSteps + 1) % 6
    if not part:SetYawSteps(nextStep) then
        if self.ui then
            self.ui:SetStatus("当前 Rotator 状态不允许旋转到 " .. tostring(nextStep))
        end
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    self:RefreshLevelUI("旋转塔状态：" .. tostring(part.transform.rotation.yawSteps) .. "（" .. tostring(part.transform.rotation.yawSteps * 60) .. "°）")
    return true
end

function LevelEditor:DrawSelectionGizmo()
    if self.mode ~= "level" or not self.selectedPartId then
        return
    end
    local root = self.partRenderer:GetRoot(self.selectedPartId)
    local minPoint, maxPoint = self.partRenderer:GetLocalBounds(self.selectedPartId)
    if not root or not minPoint or not maxPoint then
        return
    end

    local corners = {
        Vector3(minPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),
    }
    local world = {}
    for index, corner in ipairs(corners) do
        world[index] = root.worldTransform * corner
    end
    local edges = {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }
    local color = Color(0.44, 0.84, 1.0, 1.0)
    for _, edge in ipairs(edges) do
        self.debugRenderer:AddLine(world[edge[1]], world[edge[2]], color, false)
    end
end

function LevelEditor:Refresh()
    if self.mode == "level" then
        self:DrawSelectionGizmo()
    elseif self.partEditor then
        self.partEditor:Refresh()
    end
end

function LevelEditor:Stop()
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
end

return LevelEditor
