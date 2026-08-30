-- 玩法入口状态机。
-- levelselect <-> playing / editor。
-- 章节进关只读游戏内配置 JSON；关卡编辑器独立，不挂在任何一章上。
-- 编辑器加载仍走 StarterLevel / levels/default-level.json。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local LevelCatalog = require "LevelCatalog"
local LevelSelectUI = require "LevelSelectUI"
local LevelSession = require "LevelSession"
local PlayHud = require "PlayHud"
local LevelEditor = require "LevelEditor"
local StarterLevel = require "StarterLevel"
local TriPrismGrid = require "TriPrismGrid"
local UI = require("urhox-libs/UI")

---@class GameApp
---@field state string
---@field edgeLength number
---@field voxelHeight number
---@field menuScene Scene|nil
---@field menuCameraNode Node|nil
---@field menuCamera Camera|nil
---@field menuViewport Viewport|nil
---@field selectUI LevelSelectUI|nil
---@field playHud PlayHud|nil
---@field session table|nil
---@field levelEditor LevelEditor|nil
---@field editorDocument table|nil
local GameApp = {}
GameApp.__index = GameApp

local STATE_LEVEL_SELECT = "levelselect"
local STATE_PLAYING = "playing"
local STATE_EDITOR = "editor"

function GameApp.New()
    local self = setmetatable({}, GameApp)
    self.state = STATE_LEVEL_SELECT
    self.edgeLength = VoxelRenderer.DEFAULT_EDGE
    self.voxelHeight = VoxelRenderer.DEFAULT_HEIGHT
    ---@type Scene|nil
    self.menuScene = nil
    ---@type Node|nil
    self.menuCameraNode = nil
    ---@type Camera|nil
    self.menuCamera = nil
    ---@type Viewport|nil
    self.menuViewport = nil
    ---@type LevelSelectUI|nil
    self.selectUI = nil
    ---@type PlayHud|nil
    self.playHud = nil
    ---@type table|nil
    self.session = nil
    ---@type LevelEditor|nil
    self.levelEditor = nil
    ---@type table|nil
    self.editorDocument = nil
    return self
end

function GameApp:CreateMenuScene()
    self.menuScene = Scene()
    self.menuScene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())

    self.menuCameraNode = self.menuScene:CreateChild("MenuCamera")
    self.menuCameraNode.position = Vector3(0, 8.660254, -15.0)
    self.menuCameraNode:LookAt(Vector3(0, 0, 0))
    self.menuCamera = self.menuCameraNode:CreateComponent("Camera")
    self.menuCamera.orthographic = true
    self.menuCamera.orthoSize = 10.0
    self.menuCamera.nearClip = 0.1
    self.menuCamera.farClip = 100.0

    self.menuViewport = Viewport:new(self.menuScene, self.menuCamera)
    renderer:SetViewport(0, self.menuViewport)
    renderer:SetNumViewports(1)
    renderer.hdrRendering = false
end

function GameApp:BindMenuViewport()
    if self.menuViewport then
        renderer:SetViewport(0, self.menuViewport)
        renderer:SetNumViewports(1)
    end
end

function GameApp:Start()
    self:CreateMenuScene()
    self.selectUI = LevelSelectUI.New(function(definition)
        self:EnterLevel(definition)
    end, function()
        self:EnterEditor()
    end)
    self.playHud = PlayHud.New(function()
        self:BackToLevelSelect()
    end)
    self:ShowLevelSelect("选择一章进入，或打开独立关卡编辑器")
    print("GameApp: started in levelselect, chapters=" .. tostring(#LevelCatalog.GetAll()))
end

function GameApp:ShowLevelSelect(status)
    self.state = STATE_LEVEL_SELECT
    self:BindMenuViewport()
    LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())
    if self.selectUI then
        self.selectUI:Show()
        if status then
            self.selectUI:SetStatus(status)
        end
    end
end

function GameApp:EnterLevel(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    print("GameApp: entering chapter " .. definition.id .. " source=" .. definition.sourcePath)
    if self.selectUI then
        self.selectUI:Hide()
    end
    self:DisposeSession()
    local session = LevelSession.New(definition, self.edgeLength, self.voxelHeight)
    local started, errorMessage = session:Init()
    if not started then
        print("GameApp: level init failed: " .. tostring(errorMessage))
        self:ShowLevelSelect("进入失败：" .. tostring(errorMessage))
        return false
    end
    self.session = session
    self.state = STATE_PLAYING
    session.onFinish = function()
        print("GameApp: chapter finished " .. definition.id)
        if self.playHud then
            self.playHud:ShowFinish()
        end
    end
    if self.playHud then
        self.playHud:Show(definition)
    end
    return true
end

function GameApp:EnterEditor()
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    if not self.menuScene or not self.menuCameraNode or not self.menuCamera or not self.menuViewport then
        self:ShowLevelSelect("无法打开编辑器：菜单场景未初始化")
        return false
    end
    print("GameApp: entering standalone level editor")
    if self.selectUI then
        self.selectUI:Hide()
    end
    self:DisposeSession()
    local grid = TriPrismGrid.New(self.edgeLength, self.voxelHeight)
    local document, loadWarning = StarterLevel.LoadOrCreate(grid)
    if not document then
        self:ShowLevelSelect("无法打开编辑器：" .. tostring(loadWarning))
        return false
    end
    self.editorDocument = document
    LookApplier.ApplyAtmosphere(self.menuScene, document.atmosphere)
    self.levelEditor = LevelEditor.New(
        self.menuScene,
        self.menuCameraNode,
        self.menuCamera,
        self.menuViewport,
        document,
        self.edgeLength,
        self.voxelHeight
    )
    self.levelEditor:Start()
    self.state = STATE_EDITOR
    return true
end

function GameApp:DisposeSession()
    if self.playHud then
        self.playHud:Hide()
    end
    if self.session then
        self.session:Dispose()
        self.session = nil
    end
end

function GameApp:StopEditor()
    if self.levelEditor then
        self.levelEditor:Stop()
        self.levelEditor = nil
    end
    self.editorDocument = nil
    if self.menuScene then
        LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())
    end
end

function GameApp:BackToLevelSelect()
    if self.state == STATE_PLAYING then
        self:DisposeSession()
        self:ShowLevelSelect("已返回选关")
        return
    end
    if self.state == STATE_EDITOR then
        self:StopEditor()
        self:ShowLevelSelect("已退出关卡编辑器")
    end
end

function GameApp:Update(timeStep)
    if self.state == STATE_PLAYING then
        if input:GetKeyPress(KEY_ESCAPE) then
            self:BackToLevelSelect()
            return
        end
        if self.session then
            self.session:Update(timeStep)
        end
        return
    end
    if self.state == STATE_EDITOR and self.levelEditor then
        local modeBefore = self.levelEditor.mode
        self.levelEditor:Refresh(timeStep)
        -- Preview 自己用 Esc 退出试玩；只有 Level/Part 编辑态 Esc 才回选关。
        if self.levelEditor and modeBefore ~= "preview" and input:GetKeyPress(KEY_ESCAPE) then
            self:BackToLevelSelect()
        end
    end
end

function GameApp:Stop()
    self:DisposeSession()
    self:StopEditor()
    if self.selectUI then
        self.selectUI:Destroy()
        self.selectUI = nil
    end
    if self.playHud then
        self.playHud:Hide()
        self.playHud = nil
    end
    UI.Shutdown()
    if self.menuScene then
        self.menuScene:Clear(true, true)
        self.menuScene = nil
    end
    self.menuCameraNode = nil
    self.menuCamera = nil
    self.menuViewport = nil
    self.state = STATE_LEVEL_SELECT
end

return GameApp
