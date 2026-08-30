-- 玩法入口状态机。
-- levelselect <-> playing。进入关卡走 LevelSession:Init，退出走 Dispose。
-- 不加载 LevelEditor；编辑器是独立工具，不是玩法驱动。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local LevelCatalog = require "LevelCatalog"
local LevelSelectUI = require "LevelSelectUI"
local LevelSession = require "LevelSession"
local PlayHud = require "PlayHud"

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
---@field session LevelSession|nil
local GameApp = {}
GameApp.__index = GameApp

local STATE_LEVEL_SELECT = "levelselect"
local STATE_PLAYING = "playing"

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
    ---@type LevelSession|nil
    self.session = nil
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
    end)
    self.playHud = PlayHud.New(function()
        self:BackToLevelSelect()
    end)
    self:ShowLevelSelect("选择一章进入白膜关卡")
    print("GameApp: started in levelselect, chapters=" .. tostring(#LevelCatalog.GetAll()))
end

function GameApp:ShowLevelSelect(status)
    self.state = STATE_LEVEL_SELECT
    self:BindMenuViewport()
    if self.selectUI then
        self.selectUI:Show()
        if status then
            self.selectUI:SetStatus(status)
        end
    end
end

function GameApp:EnterLevel(definition)
    if self.state == STATE_PLAYING then
        return false
    end
    print("GameApp: entering " .. definition.id)
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
    if self.playHud then
        self.playHud:Show(definition)
    end
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

function GameApp:BackToLevelSelect()
    if self.state ~= STATE_PLAYING then
        return
    end
    self:DisposeSession()
    self:ShowLevelSelect("已返回选关")
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
    end
end

function GameApp:Stop()
    self:DisposeSession()
    if self.selectUI then
        self.selectUI:Destroy()
        self.selectUI = nil
    end
    if self.playHud then
        self.playHud:Hide()
        self.playHud = nil
    end
    local UI = require("urhox-libs/UI")
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
