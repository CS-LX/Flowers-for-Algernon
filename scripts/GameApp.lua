-- 玩法入口状态机。
-- levelselect <-> playing / editor。
-- 章节进关只读游戏内配置 JSON；关卡编辑器独立，不挂在任何一章上。
-- 编辑器加载仍走 StarterLevel / levels/default-level.json。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local LevelCatalog = require "LevelCatalog"
local LevelSession = require "LevelSession"
local PlayHud = require "PlayHud"
local LevelEditor = require "LevelEditor"
local StarterLevel = require "StarterLevel"
local TriPrismGrid = require "TriPrismGrid"
local MenuPrism = require "MenuPrism"
local UI = require("urhox-libs/UI")

---@class GameApp
---@field state string
---@field edgeLength number
---@field voxelHeight number
---@field menuScene Scene|nil
---@field menuCameraNode Node|nil
---@field menuCamera Camera|nil
---@field menuViewport Viewport|nil
---@field menuPrism MenuPrism|nil
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
    ---@type MenuPrism|nil
    self.menuPrism = nil
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
    local prismHeight = VoxelRenderer.DEFAULT_HEIGHT * 1.5
    local eyeHeight = prismHeight * 0.5
    self.menuCameraNode.position = Vector3(0.0, eyeHeight, -3.2)
    self.menuCameraNode:LookAt(Vector3(0.0, eyeHeight, 0.0))
    self.menuCamera = self.menuCameraNode:CreateComponent("Camera")
    self.menuCamera.orthographic = true
    self.menuCamera.orthoSize = 3.2
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
    self.playHud = PlayHud.New(function()
        self:BackToLevelSelect()
    end)
    self:ShowLevelSelect()
    print("GameApp: started in levelselect, chapters=" .. tostring(#LevelCatalog.GetAll()))
end

function GameApp:EnsureMenuPrism()
    if self.menuPrism or not self.menuScene or not self.menuCamera then
        return
    end
    self.menuPrism = MenuPrism.New(self.menuScene, self.menuCamera)
    self.menuPrism:Build()
end

function GameApp:DestroyMenuPrism()
    if self.menuPrism then
        self.menuPrism:Destroy()
        self.menuPrism = nil
    end
end

function GameApp:ShowLevelSelect(status)
    self.state = STATE_LEVEL_SELECT
    self:BindMenuViewport()
    LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())
    self:EnsureMenuPrism()
    if status then
        print("GameApp: levelselect " .. tostring(status))
    end
end

function GameApp:EnterLevel(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    print("GameApp: entering chapter " .. definition.id .. " source=" .. definition.sourcePath)
    self:DestroyMenuPrism()
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
        self:CompleteLevel(definition)
    end
    self:PresentSession(session, definition)
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
    self:DestroyMenuPrism()
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

function GameApp:CompleteLevel(definition)
    print("GameApp: chapter finished " .. definition.id)
    local nextDefinition = LevelCatalog.GetNext(definition.id)
    if nextDefinition then
        self:EnterNextLevel(nextDefinition)
        return
    end
    if self.playHud then
        self.playHud:ShowFinish()
    end
end

function GameApp:EnterNextLevel(definition)
    print("GameApp: entering next chapter " .. definition.id)
    self:DisposeSession()
    local session = LevelSession.New(definition, self.edgeLength, self.voxelHeight)
    local started, errorMessage = session:Init()
    if not started then
        print("GameApp: next level init failed: " .. tostring(errorMessage))
        self:ShowLevelSelect("进入失败：" .. tostring(errorMessage))
        return false
    end
    self.session = session
    self.state = STATE_PLAYING
    session.onFinish = function()
        self:CompleteLevel(definition)
    end
    self:PresentSession(session, definition)
    return true
end

function GameApp:PresentSession(session, definition)
    if self.playHud then
        self.playHud:Show(definition)
    end
    session:CreateDirector()
    if session.director and self.playHud and self.playHud.storyView then
        session.director:AttachStoryView(self.playHud.storyView)
    end
    session:StartDirector()
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

-- 选关无 UI。1/2/3 分别进第一章的 1-1 / 1-2 / 1-3。
function GameApp:HandleLevelSelectHotkeys()
    if input:GetKeyPress(KEY_1) then
        local definition = LevelCatalog.GetById("ch1_1")
        if definition then
            self:EnterLevel(definition)
        end
        return
    end
    if input:GetKeyPress(KEY_2) then
        local definition = LevelCatalog.GetById("ch1_2")
        if definition then
            self:EnterLevel(definition)
        end
        return
    end
    if input:GetKeyPress(KEY_3) then
        local definition = LevelCatalog.GetById("ch1_3")
        if definition then
            self:EnterLevel(definition)
        end
        return
    end
    if input:GetKeyPress(KEY_E) then
        self:EnterEditor()
    end
end

function GameApp:Update(timeStep)
    if self.state == STATE_LEVEL_SELECT then
        if self.menuPrism then
            self.menuPrism:Update(timeStep)
        end
        self:HandleLevelSelectHotkeys()
        return
    end
    if self.state == STATE_PLAYING then
        if input:GetKeyPress(KEY_ESCAPE) then
            local director = self.session and self.session.director
            if director and director:IsStoryPlaying() then
                director:StopStory()
            else
                self:BackToLevelSelect()
            end
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
        -- Preview / Part 各自消费 Esc；只有关卡 Object Tree 态才回选关。
        if self.levelEditor and modeBefore == "level" and input:GetKeyPress(KEY_ESCAPE) then
            self:BackToLevelSelect()
        end
    end
end

function GameApp:Stop()
    self:DisposeSession()
    self:StopEditor()
    if self.playHud then
        self.playHud:Hide()
        self.playHud = nil
    end
    UI.Shutdown()
    self:DestroyMenuPrism()
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
