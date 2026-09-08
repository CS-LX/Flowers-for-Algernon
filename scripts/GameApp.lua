-- 玩法入口状态机。
-- levelselect <-> playing / editor。
-- 章节进关只读游戏内配置 JSON。按住 E 点前台关进编辑器；保存仍写用户档，不覆盖内置关。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local LevelCatalog = require "LevelCatalog"
local LevelSession = require "LevelSession"
local PlayHud = require "PlayHud"
local LevelEditor = require "LevelEditor"
local LevelDocument = require "LevelDocument"
local StarterLevel = require "StarterLevel"
local TriPrismGrid = require "TriPrismGrid"
local MenuPrism = require "MenuPrism"
local MenuClusterBackdrop = require "MenuClusterBackdrop"
local UI = require("urhox-libs/UI")

---@class GameApp
---@field state string
---@field edgeLength number
---@field voxelHeight number
---@field menuScene Scene|nil
---@field menuCameraNode Node|nil
---@field menuCamera Camera|nil
---@field menuViewport Viewport|nil
---@field menuPrism table|nil
---@field menuClusters table|nil
---@field playHud PlayHud|nil
---@field session table|nil
---@field levelEditor LevelEditor|nil
---@field editorDocument table|nil
---@field pendingEnter LevelDefinition|nil
---@field clusterHold number
---@field lastDefinition LevelDefinition|nil
local GameApp = {}
GameApp.__index = GameApp

local STATE_LEVEL_SELECT = "levelselect"
local STATE_PLAYING = "playing"
local STATE_EDITOR = "editor"
local MENU_CAMERA_DISTANCE = 3.2
local MENU_CAMERA_ORTHO = 3.2
local MENU_CAMERA_PITCH = 10.0
local MENU_CAMERA_VIEW_MASK = 2

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
    ---@type table|nil
    self.menuPrism = nil
    ---@type table|nil
    self.menuClusters = nil
    ---@type PlayHud|nil
    self.playHud = nil
    ---@type table|nil
    self.session = nil
    ---@type LevelEditor|nil
    self.levelEditor = nil
    ---@type table|nil
    self.editorDocument = nil
    ---@type LevelDefinition|nil
    self.pendingEnter = nil
    self.clusterHold = 0.0
    ---@type LevelDefinition|nil
    self.lastDefinition = nil
    return self
end

function GameApp:MenuEyeHeight()
    local prismHeight = VoxelRenderer.DEFAULT_HEIGHT * 1.5
    return prismHeight * 0.5 - 0.55 + 0.50
end

function GameApp:RestoreMenuCamera()
    if not self.menuCameraNode or not self.menuCamera then
        return
    end
    local eyeHeight = self:MenuEyeHeight()
    self.menuCameraNode.position = Vector3(0.0, eyeHeight, -MENU_CAMERA_DISTANCE)
    self.menuCameraNode.rotation = Quaternion(MENU_CAMERA_PITCH, Vector3.RIGHT)
    self.menuCamera.orthographic = true
    self.menuCamera.viewMask = MENU_CAMERA_VIEW_MASK
    self.menuCamera.orthoSize = MENU_CAMERA_ORTHO
    self.menuCamera.nearClip = 0.1
    self.menuCamera.farClip = 100.0
    self.menuCamera.fov = 45.0
    print(string.format("GameApp: menu camera restored y=%.3f pitch=%.1f", eyeHeight, MENU_CAMERA_PITCH))
end

function GameApp:CreateMenuScene()
    self.menuScene = Scene()
    self.menuScene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())

    self.menuCameraNode = self.menuScene:CreateChild("MenuCamera")
    self.menuCamera = self.menuCameraNode:CreateComponent("Camera")
    self:RestoreMenuCamera()

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
    if self.menuPrism or not self.menuScene or not self.menuCamera or not self.menuViewport then
        return
    end
    self.menuPrism = MenuPrism.New(self.menuScene, self.menuCamera, self.menuCameraNode, self.menuViewport)
    self.menuPrism.onFrontEditClicked = function(definition)
        self:EnterEditor(definition)
    end
    self.menuPrism.onExitReady = function(definition)
        self.pendingEnter = definition
    end
    self:EnsureMenuClusters()
    self.menuPrism:Build()
    local front = self.menuPrism:FrontLevel()
    if self.menuClusters then
        self.menuClusters:SetChapter(front and front.chapter or nil, true)
    end
end

function GameApp:EnsureMenuClusters()
    if self.menuClusters or not self.menuScene then
        return
    end
    self.menuClusters = MenuClusterBackdrop.New(self.menuScene)
    if self.menuPrism then
        self.menuPrism.onFrontChapterChanged = function(chapter)
            if self.menuClusters then
                self.menuClusters:SetChapter(chapter, false)
            end
        end
        self.menuPrism.onExitDropStarted = function()
            if self.menuClusters then
                self.menuClusters:BeginExitDrop()
            end
            self.clusterHold = 0.85
        end
        self.menuPrism.onEnterRiseStarted = function(chapter)
            if self.menuClusters then
                self.menuClusters:BeginEnterRise(chapter)
            end
        end
    end
end

function GameApp:DestroyMenuClusters()
    if self.menuClusters then
        self.menuClusters:Destroy()
        self.menuClusters = nil
    end
end

function GameApp:DestroyMenuPrism()
    if self.menuPrism then
        self.menuPrism:Destroy()
        self.menuPrism = nil
    end
end

function GameApp:FogColorFor(definition)
    return LevelCatalog.GetFogColor(definition, LevelCatalog.CONFIG.placeholderFogColor)
end

function GameApp:ShowLevelSelect(status, returnDefinition)
    self.state = STATE_LEVEL_SELECT
    self:RestoreMenuCamera()
    self:BindMenuViewport()
    LookApplier.ApplyAtmosphere(self.menuScene, LookApplier.DefaultAtmosphere())
    self:EnsureMenuPrism()
    if returnDefinition and self.menuPrism then
        self.menuPrism:FocusLevel(returnDefinition, self:FogColorFor(returnDefinition))
        self.menuPrism:BeginEnterRise()
    end
    if status then
        print("GameApp: levelselect " .. tostring(status))
    end
end

function GameApp:EnterLevel(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    if self.menuPrism then
        print("GameApp: begin menu exit " .. definition.id)
        return self.menuPrism:BeginExitDrop(definition)
    end
    return self:FinishEnterLevel(definition)
end

function GameApp:FinishEnterLevel(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    print("GameApp: entering chapter " .. definition.id .. " source=" .. definition.sourcePath)
    self:DestroyMenuPrism()
    self:DestroyMenuClusters()
    self:DisposeSession()
    local session = LevelSession.New(definition, self.edgeLength, self.voxelHeight)
    local started, errorMessage = session:Init()
    if not started then
        print("GameApp: level init failed: " .. tostring(errorMessage))
        self:ShowLevelSelect("进入失败：" .. tostring(errorMessage))
        return false
    end
    self.session = session
    self.lastDefinition = definition
    self.state = STATE_PLAYING
    session.onFinish = function()
        self:CompleteLevel(definition)
    end
    self:PresentSession(session, definition, self:FogColorFor(definition))
    return true
end

function GameApp:LoadEditorDocument(grid, definition)
    if definition and LevelCatalog.IsPlayable(definition) then
        local json, readError = LevelCatalog.ReadSourceJson(definition.sourcePath)
        if json then
            local document = LevelDocument.New()
            local imported, importError = document:ImportInlineJson(json, grid)
            if imported then
                print("GameApp: editor start from " .. definition.code .. " save=" .. document.path)
                return document
            end
            print("GameApp: editor import failed " .. tostring(importError) .. ", fallback whitebox")
        else
            print("GameApp: editor source missing " .. tostring(readError) .. ", fallback whitebox")
        end
    else
        print("GameApp: editor start whitebox, front has no playable source")
    end
    return StarterLevel.LoadOrCreate(grid)
end

function GameApp:EnterEditor(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    if not self.menuScene or not self.menuCameraNode or not self.menuCamera or not self.menuViewport then
        self:ShowLevelSelect("无法打开编辑器：菜单场景未初始化")
        return false
    end
    print("GameApp: entering standalone level editor")
    self:DestroyMenuPrism()
    self:DestroyMenuClusters()
    self:DisposeSession()
    local grid = TriPrismGrid.New(self.edgeLength, self.voxelHeight)
    local document, loadWarning = self:LoadEditorDocument(grid, definition)
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
    local director = self.session and self.session.director
    if director then
        director:Halt()
    end
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
    self:RestoreMenuCamera()
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
    print("GameApp: conceal then enter next chapter " .. definition.id)
    self:BeginLevelTransition(definition)
    return true
end

function GameApp:PresentSession(session, definition, coverColor)
    if self.playHud then
        self.playHud:Show(definition)
    end
    session:CreateDirector()
    if session.director and self.playHud and self.playHud.storyView then
        session.director:AttachStoryView(self.playHud.storyView)
    end
    if session.preview then
        session.preview.onLevelSettled = function()
            session:StartDirector()
            local director = session.director
            if director and director:ShouldRunDuringFogReveal() then
                director:BeginRun()
            end
        end
        session.preview.onFogRevealFinished = function()
            if not session:RunDirector() then
                session.preview:SetInputLocked(false)
            end
        end
        session.preview:BeginFogCover(coverColor)
    else
        session:RunDirector()
    end
end

function GameApp:StartNextSession(definition, coverColor)
    self:DisposeSession()
    local session = LevelSession.New(definition, self.edgeLength, self.voxelHeight)
    local started, errorMessage = session:Init()
    if not started then
        print("GameApp: next level init failed: " .. tostring(errorMessage))
        self:ShowLevelSelect("进入失败：" .. tostring(errorMessage))
        return false
    end
    self.session = session
    self.lastDefinition = definition
    self.state = STATE_PLAYING
    session.onFinish = function()
        self:CompleteLevel(definition)
    end
    self:PresentSession(session, definition, coverColor)
    return true
end

function GameApp:BeginLevelTransition(nextDefinition)
    if self.state ~= STATE_PLAYING then
        return false
    end
    local preview = self.session and self.session.preview
    local nextColor = self:FogColorFor(nextDefinition)
    if preview and preview.BeginFogConceal then
        if preview.fogReveal and preview.fogReveal.conceal then
            return true
        end
        local director = self.session and self.session.director
        if director and not director:ShouldContinueDuringFogConceal() then
            director:Halt()
        end
        if self.playHud then
            self.playHud:Hide()
        end
        preview.onFogCoverFinished = function()
            self:StartNextSession(nextDefinition, nextColor)
        end
        print("GameApp: conceal current level then enter " .. nextDefinition.id)
        return preview:BeginFogConceal(nextColor)
    end
    return self:StartNextSession(nextDefinition, nextColor)
end

function GameApp:FinishBackToLevelSelect()
    local definition = self.lastDefinition
    self:DisposeSession()
    self:ShowLevelSelect("已返回选关", definition)
end

function GameApp:BeginExitToLevelSelect()
    if self.state ~= STATE_PLAYING then
        return false
    end
    local preview = self.session and self.session.preview
    if preview and preview.BeginFogConceal then
        if preview.fogReveal and preview.fogReveal.conceal then
            return true
        end
        local director = self.session and self.session.director
        if director then
            director:Halt()
        end
        if self.playHud then
            self.playHud:Hide()
        end
        preview.onFogCoverFinished = function()
            self:FinishBackToLevelSelect()
        end
        print("GameApp: conceal level then return to menu")
        return preview:BeginFogConceal()
    end
    self:FinishBackToLevelSelect()
    return true
end

function GameApp:BackToLevelSelect()
    if self.state == STATE_PLAYING then
        self:BeginExitToLevelSelect()
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
end

function GameApp:Update(timeStep)
    if self.state == STATE_LEVEL_SELECT then
        local pending = self.pendingEnter
        if pending then
            if self.clusterHold > 0.0 then
                self.clusterHold = self.clusterHold - timeStep
                if self.menuClusters then
                    self.menuClusters:Update(timeStep)
                end
                if self.clusterHold > 0.0 then
                    return
                end
            end
            self.pendingEnter = nil
            self.clusterHold = 0.0
            self:FinishEnterLevel(pending)
            return
        end
        if self.menuPrism then
            self.menuPrism:Update(timeStep)
        end
        if self.menuClusters then
            self.menuClusters:Update(timeStep)
        end
        if not (self.menuPrism and self.menuPrism.phase == "enter") then
            self:HandleLevelSelectHotkeys()
        end
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
    self:DestroyMenuClusters()
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
