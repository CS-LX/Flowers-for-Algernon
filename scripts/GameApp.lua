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
local MenuHud = require "MenuHud"
local PlayerTelemetry = require "PlayerTelemetry"
local AudioSettings = require "AudioSettings"
local ControlSettings = require "ControlSettings"
local BootHint = require "BootHint"
local FeelCalibrate = require "FeelCalibrate"
local Sfx = require "Sfx"
local UI = require("urhox-libs/UI")

local function DiscardBgmSnapshot(snapshot)
    if not snapshot then
        return
    end
    if snapshot.source then
        snapshot.source:Stop()
    end
    if snapshot.node then
        snapshot.node:Remove()
    end
end

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
---@field menuHud MenuHud|nil
---@field playHud PlayHud|nil
---@field session table|nil
---@field levelEditor LevelEditor|nil
---@field editorDocument table|nil
---@field pendingEnter LevelDefinition|nil
---@field clusterHold number
---@field lastDefinition LevelDefinition|nil
local GameApp = {}
GameApp.__index = GameApp

local STATE_BOOT = "boot"
local STATE_FEEL = "feel"
local STATE_LEVEL_SELECT = "levelselect"
local STATE_PLAYING = "playing"
local STATE_CREDITS = "credits"
local STATE_EDITOR = "editor"
local CREDITS_CONCEAL_DURATION = 5.0
local MENU_CAMERA_DISTANCE = 3.2
local MENU_CAMERA_ORTHO = 3.2
local MENU_CAMERA_PITCH = 10.0
local MENU_CAMERA_VIEW_MASK = 2

function GameApp.New()
    local self = setmetatable({}, GameApp)
    self.state = STATE_BOOT
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
    ---@type MenuHud|nil
    self.menuHud = nil
    ---@type table|nil
    self.bootHint = nil
    ---@type Widget|nil
    self.bootOverlay = nil
    self.bootOverlayClock = 0.0
    self.bootOverlayDuration = 0.6
    self.bootOverlayStart = 1.0
    ---@type table|nil
    self.feelCalibrate = nil
    self.feelFromMenu = false
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
    self.pendingFeel = false
    self.wantMenuRise = false
    ---@type LevelDefinition|nil
    self.lastDefinition = nil
    self.creditsCanSkip = false
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
    Sfx.BindUiScene(self.menuScene)
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
        if self.state == STATE_CREDITS then
            self:SkipCredits()
            return
        end
        self:BackToLevelSelect()
    end)
    self.playHud.onSkip = function()
        local director = self.session and self.session.director
        if director then
            director:SkipStoryModals()
        end
    end
    AudioSettings.Load(function()
        if self.menuHud then
            self.menuHud:SyncVolumes()
        end
    end)
    PlayerTelemetry.Load(function()
        if self.state == STATE_LEVEL_SELECT then
            self:RefreshMenuTape()
            if self.menuHud then
                self.menuHud:SetMenuHintVisible(PlayerTelemetry.ShouldShowMenuHint())
            end
        else
            LevelCatalog.BuildMenuTape(PlayerTelemetry.GetCleared())
        end
    end)
    ControlSettings.Load()
    self:ShowBootHint()
    print("GameApp: started boot hint")
end

function GameApp:ShowBootHint()
    self:HideMenuHud()
    self.state = STATE_BOOT
    if self.bootHint then
        self.bootHint:Hide()
    end
    self.bootHint = BootHint.New()
    self.bootHint.onFinished = function()
        self:OnBootHintFinished()
    end
    self.bootHint:Show()
end

function GameApp:OnBootHintFinished()
    local cover = nil
    local coverOpacity = 1.0
    if self.bootHint then
        cover, coverOpacity = self.bootHint:ReleaseCover()
        self.bootHint = nil
    end
    if ControlSettings.HasCalibrated() then
        self.wantMenuRise = true
        self:ShowLevelSelect()
        self:AttachBootOverlay(cover, coverOpacity)
        print("GameApp: boot done, skip feel calibrate")
        return
    end
    self:ShowFeelCalibrate(false)
    self:AttachBootOverlay(cover, coverOpacity)
end

function GameApp:FinishBootOverlay()
    local overlay = self.bootOverlay
    self.bootOverlay = nil
    self.bootOverlayClock = 0.0
    if not overlay then
        return
    end
    if overlay.parent then
        overlay.parent:RemoveChild(overlay)
    end
    overlay:Destroy()
    print("GameApp: boot overlay removed")
end

function GameApp:AttachBootOverlay(cover, startOpacity)
    self:FinishBootOverlay()
    if self.feelCalibrate then
        self.feelCalibrate:AllowFogReveal()
    end
    if not cover then
        return
    end
    local host = UI.GetRoot()
    if not host then
        cover:Destroy()
        return
    end
    local opacity = startOpacity or 1.0
    if opacity < 0.0 then
        opacity = 0.0
    elseif opacity > 1.0 then
        opacity = 1.0
    end
    cover.props.onClick = nil
    cover:SetStyle({
        position = "absolute",
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        opacity = opacity,
        zIndex = 1000,
        pointerEvents = "auto",
    })
    host:AddChild(cover)
    self.bootOverlay = cover
    self.bootOverlayClock = 0.0
    self.bootOverlayDuration = 0.6
    self.bootOverlayStart = opacity
    print("GameApp: boot overlay attached")
end

function GameApp:UpdateBootOverlay(timeStep)
    local overlay = self.bootOverlay
    if not overlay then
        return
    end
    local duration = self.bootOverlayDuration
    if duration <= 0.0 then
        self:FinishBootOverlay()
        return
    end
    local clock = self.bootOverlayClock + timeStep
    self.bootOverlayClock = clock
    local t = clock / duration
    if t >= 1.0 then
        self:FinishBootOverlay()
        return
    end
    local startOpacity = self.bootOverlayStart or 1.0
    overlay:SetStyle({ opacity = startOpacity * (1.0 - t) })
end

function GameApp:EnterFeelCalibrate()
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    if self.menuHud then
        self.menuHud:BeginExitFade()
    end
    if self.menuPrism then
        self.pendingFeel = true
        print("GameApp: begin menu exit to feel calibrate")
        return self.menuPrism:BeginExitDrop(self.menuPrism:FrontLevel())
    end
    return self:ShowFeelCalibrate(true)
end

function GameApp:ShowFeelCalibrate(fromMenu)
    self.feelFromMenu = fromMenu == true
    self.pendingFeel = false
    self:HideMenuHud()
    self:DestroyMenuPrism()
    self:DestroyMenuClusters()
    if self.feelCalibrate then
        self.feelCalibrate:Stop()
        self.feelCalibrate = nil
    end
    self.state = STATE_FEEL
    self.feelCalibrate = FeelCalibrate.New()
    self.feelCalibrate.onFogCoverFinished = function()
        self:OnFeelCalibrateFinished()
    end
    self.feelCalibrate.onFinished = function()
        self:OnFeelCalibrateFinished()
    end
    if not self.feelFromMenu then
        self.feelCalibrate.delayReveal = true
    end
    self.feelCalibrate:Start()
    print("GameApp: feel calibrate fromMenu=" .. tostring(self.feelFromMenu))
    return true
end

function GameApp:OnFeelCalibrateFinished()
    if self.feelCalibrate then
        self.feelCalibrate:Stop()
        self.feelCalibrate = nil
    end
    self.wantMenuRise = true
    self:ShowLevelSelect("手感已保存")
    print("GameApp: feel calibrate finished")
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
        if self.pendingFeel then
            self:ShowFeelCalibrate(true)
            return
        end
        self.pendingEnter = definition
    end
    self.menuPrism.onFogColorChanged = function(color)
        if self.menuHud then
            self.menuHud:SetFogColor(color)
        end
    end
    -- Build 默认对准第一章。先建棱柱，再挂簇回调，避免回选关时先冒出第一章簇。
    self.menuPrism:Build()
    self:EnsureMenuClusters()
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
            if self.menuHud then
                self.menuHud:BeginExitFade()
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

function GameApp:HideMenuHud()
    if self.menuHud then
        self.menuHud:Hide()
        self.menuHud = nil
    end
end

function GameApp:UnlockAllLevels()
    local ids = {}
    local levels = LevelCatalog.GetAll()
    for i = 1, #levels do
        local definition = levels[i]
        if LevelCatalog.IsPlayable(definition) then
            ids[#ids + 1] = definition.id
        end
    end
    PlayerTelemetry.UnlockLevels(ids)
    self:RefreshMenuTape()
end

function GameApp:ResetProgress()
    PlayerTelemetry.ResetProgress()
    self:RefreshMenuTape(LevelCatalog.FirstPlayable())
    if self.menuHud then
        self.menuHud:SetMenuHintVisible(true)
    end
end

function GameApp:QuitGame()
    print("GameApp: quit")
    engine:Exit()
end

function GameApp:EnsureMenuHud()
    if self.menuHud then
        return
    end
    self.menuHud = MenuHud.New()
    self.menuHud.onOpenChanged = function(open)
        if self.menuPrism and self.menuPrism.SetInputLocked then
            self.menuPrism:SetInputLocked(open)
        end
        if open then
            PlayerTelemetry.MarkMenuHintSeen()
            self.menuHud:SetMenuHintVisible(false)
        end
    end
    self.menuHud.onUnlockAll = function()
        self:UnlockAllLevels()
    end
    self.menuHud.onResetProgress = function()
        self:ResetProgress()
    end
    self.menuHud.onCredits = function()
        self:PlayMenuCredits()
    end
    self.menuHud.onFeel = function()
        self:EnterFeelCalibrate()
    end
    self.menuHud.onQuit = function()
        self:QuitGame()
    end
    self.menuHud:Show()
    self.menuHud:SetMenuHintVisible(PlayerTelemetry.ShouldShowMenuHint())
    if self.menuPrism then
        local front = self.menuPrism:FrontLevel()
        self.menuHud:SetFogColor(self:FogColorFor(front))
    end
end

function GameApp:FogColorFor(definition)
    return LevelCatalog.GetFogColor(definition, LevelCatalog.CONFIG.placeholderFogColor)
end

function GameApp:RefreshMenuTape(focusDefinition)
    LevelCatalog.BuildMenuTape(PlayerTelemetry.GetCleared())
    if not self.menuPrism then
        return
    end
    if focusDefinition then
        self.menuPrism:FocusLevel(focusDefinition, self:FogColorFor(focusDefinition))
        return
    end
    self.menuPrism:UpdateFrontFaceColors()
end

function GameApp:ShowLevelSelect(status, returnDefinition)
    self.state = STATE_LEVEL_SELECT
    self:RestoreMenuCamera()
    self:BindMenuViewport()
    local atmosphere = LookApplier.DefaultAtmosphere()
    local fogSource = nil
    if self.menuPrism then
        fogSource = self.menuPrism:FrontLevel()
    end
    fogSource = fogSource or returnDefinition
    local fogColor = fogSource and self:FogColorFor(fogSource) or nil
    if fogColor then
        atmosphere.fog = atmosphere.fog or {}
        atmosphere.fog.color = string.format("#%02X%02X%02X",
            math.floor(fogColor.r * 255.0 + 0.5),
            math.floor(fogColor.g * 255.0 + 0.5),
            math.floor(fogColor.b * 255.0 + 0.5))
    end
    LookApplier.ApplyAtmosphere(self.menuScene, atmosphere)
    self:RefreshMenuTape()
    self:EnsureMenuPrism()
    self:EnsureMenuHud()
    if self.menuHud then
        self.menuHud:BeginEnterFade()
    end
    local shouldRise = self.wantMenuRise == true or returnDefinition ~= nil
    self.wantMenuRise = false
    if returnDefinition and self.menuPrism then
        self.menuPrism:FocusLevel(returnDefinition, self:FogColorFor(returnDefinition))
    end
    if shouldRise and self.menuPrism then
        self.menuPrism:BeginEnterRise()
    elseif self.menuClusters and self.menuPrism then
        local front = self.menuPrism:FrontLevel()
        self.menuClusters:SetChapter(front and front.chapter or nil, true)
    end
    if status then
        print("GameApp: levelselect " .. tostring(status))
    end
end

function GameApp:EnterLevel(definition)
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    if self.menuHud then
        self.menuHud:BeginExitFade()
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
    self:HideMenuHud()
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
    if session.preview and session.preview.PlayChapterBgm then
        session.preview:PlayChapterBgm(definition.chapter)
    end
    self:BindTelemetry(session, definition)
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
    if self.menuHud then
        self.menuHud:BeginExitFade()
    end
    self:HideMenuHud()
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

function GameApp:BindTelemetry(session, definition)
    if not session or not definition then
        return
    end
    local preview = session.preview
    local spawnNodeKey = preview and preview.spawnNodeKey or nil
    PlayerTelemetry.BeginLevel(definition.id, spawnNodeKey)
    if preview and preview.player and preview.player.AddOnArrived then
        preview.player:AddOnArrived(function(nodeKey)
            PlayerTelemetry.RecordNode(nodeKey)
        end)
    end
end

function GameApp:CompleteLevel(definition)
    print("GameApp: chapter finished " .. definition.id)
    PlayerTelemetry.ClearLevel(definition.id)
    local nextDefinition = LevelCatalog.GetNext(definition.id)
    if nextDefinition then
        self:EnterNextLevel(nextDefinition)
        return
    end
    local replay = PlayerTelemetry.HasFinishedGame()
    PlayerTelemetry.FinishGame()
    self:BeginCredits(definition, replay)
end

function GameApp:BeginCredits(definition, canSkip)
    if self.state ~= STATE_PLAYING then
        return false
    end
    self.creditsCanSkip = canSkip == true
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
            self.playHud:BeginExitFade()
        end
        preview.onFogCoverFinished = function()
            if preview.PlayCreditsBgm then
                preview:PlayCreditsBgm()
            end
            self:ShowCredits()
        end
        print("GameApp: conceal 5-3 then credits")
        return preview:BeginFogConceal(nil, CREDITS_CONCEAL_DURATION)
    end
    self:ShowCredits()
    return true
end

function GameApp:ShowCredits()
    self.state = STATE_CREDITS
    if self.playHud and self.playHud.ShowCredits then
        self.playHud:ShowCredits(function()
            self:FinishCredits()
        end, function(duration)
            local preview = self.session and self.session.preview
            if preview and preview.FadeOutBgm then
                preview:FadeOutBgm(duration)
            elseif self.menuPrism and self.menuPrism.FadeOutBgm then
                self.menuPrism:FadeOutBgm(duration)
            end
        end, self.creditsCanSkip == true)
        return true
    end
    self:FinishCredits()
    return true
end

function GameApp:PlayMenuCredits()
    if self.state ~= STATE_LEVEL_SELECT then
        return false
    end
    self.creditsCanSkip = true
    if self.menuHud then
        self.menuHud:SetOpen(false, true)
        self.menuHud:BeginExitFade()
        self:HideMenuHud()
    end
    if self.menuPrism and self.menuPrism.PlayCreditsBgm then
        self.menuPrism:PlayCreditsBgm()
    end
    print("GameApp: menu credits")
    return self:ShowCredits()
end

function GameApp:SkipCredits()
    if self.state ~= STATE_CREDITS then
        return false
    end
    if not self.playHud or not self.playHud.SkipCredits then
        return false
    end
    return self.playHud:SkipCredits()
end

function GameApp:FinishCredits()
    print("GameApp: credits finished, return to level select")
    local preview = self.session and self.session.preview
    if preview and preview.FadeOutBgm then
        preview:FadeOutBgm()
    elseif self.menuPrism and self.menuPrism.FadeOutBgm then
        self.menuPrism:FadeOutBgm()
    end
    self:FinishBackToLevelSelect()
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
    local oldSession = self.session
    local sameChapter = oldSession ~= nil
        and self.lastDefinition ~= nil
        and self.lastDefinition.chapter == definition.chapter
    local session = LevelSession.New(definition, self.edgeLength, self.voxelHeight)
    local started, errorMessage = session:Init()
    if not started then
        print("GameApp: next level init failed: " .. tostring(errorMessage))
        self:DisposeSession()
        self:ShowLevelSelect("进入失败：" .. tostring(errorMessage))
        return false
    end
    local snap = nil
    if sameChapter and oldSession and oldSession.preview and oldSession.preview.ReleaseBgm then
        snap = oldSession.preview:ReleaseBgm()
    end
    if snap and session.preview and session.preview.AdoptBgm and session.preview:AdoptBgm(snap) then
        snap = nil
    end
    DiscardBgmSnapshot(snap)
    self:DisposeSession()
    self.session = session
    self.lastDefinition = definition
    self.state = STATE_PLAYING
    session.onFinish = function()
        self:CompleteLevel(definition)
    end
    if session.preview and session.preview.PlayChapterBgm then
        session.preview:PlayChapterBgm(definition.chapter)
    end
    self:BindTelemetry(session, definition)
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
            self.playHud:BeginExitFade()
        end
        if preview.FadeOutBgm
            and nextDefinition.chapter ~= (self.lastDefinition and self.lastDefinition.chapter) then
            preview:FadeOutBgm()
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
    PlayerTelemetry.AbandonLevel()
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
            self.playHud:BeginExitFade()
        end
        if preview.FadeOutBgm then
            preview:FadeOutBgm()
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

function GameApp:Update(timeStep)
    PlayerTelemetry.Update(timeStep)
    AudioSettings.Update(timeStep)
    ControlSettings.Update(timeStep)
    self:UpdateBootOverlay(timeStep)
    if self.state == STATE_BOOT then
        if self.bootHint then
            self.bootHint:Update(timeStep)
        end
        return
    end
    if self.state == STATE_FEEL then
        if self.feelCalibrate then
            self.feelCalibrate:Update(timeStep)
        end
        return
    end
    if self.state == STATE_LEVEL_SELECT then
        if self.menuHud then
            self.menuHud:Update(timeStep)
        end
        local pending = self.pendingEnter
        if pending then
            if self.menuPrism then
                self.menuPrism:UpdateBgm(timeStep)
            end
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
        if input:GetKeyPress(KEY_ESCAPE) then
            if self.menuHud and self.menuHud:HandleEscape() then
                return
            end
        end
        if self.menuPrism then
            self.menuPrism:Update(timeStep)
        end
        if self.menuClusters then
            self.menuClusters:Update(timeStep)
        end
        local prismBusy = self.menuPrism ~= nil
            and (self.menuPrism.phase == "enter" or self.menuPrism.phase == "exit")
        local menuOpen = self.menuHud ~= nil and self.menuHud:IsOpen()
        if self.menuHud then
            self.menuHud:SetToggleArmed(not prismBusy)
        end
        if self.menuPrism and self.menuPrism.SetInputLocked then
            self.menuPrism:SetInputLocked(prismBusy or menuOpen)
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
        if self.playHud and self.playHud.Update then
            self.playHud:Update(timeStep)
        end
        return
    end
    if self.state == STATE_CREDITS then
        if input:GetKeyPress(KEY_ESCAPE) then
            self:SkipCredits()
        end
        if self.session then
            self.session:Update(timeStep)
        elseif self.menuPrism and self.menuPrism.UpdateBgm then
            self.menuPrism:UpdateBgm(timeStep)
        end
        if self.playHud and self.playHud.Update then
            self.playHud:Update(timeStep)
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
    PlayerTelemetry.AbandonLevel()
    if self.bootHint then
        self.bootHint:Hide()
        self.bootHint = nil
    end
    self:FinishBootOverlay()
    if self.feelCalibrate then
        self.feelCalibrate:Stop()
        self.feelCalibrate = nil
    end
    self:DisposeSession()
    self:StopEditor()
    if self.playHud then
        self.playHud:Hide()
        self.playHud = nil
    end
    self:HideMenuHud()
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
