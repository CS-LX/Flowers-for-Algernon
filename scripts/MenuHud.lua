-- 选关菜单壳。只负责挂 UI、开关和把点击交给回调。
-- 不读写云、不改磁带、不碰棱柱。

local UI = require("urhox-libs/UI")
local MenuHexButton = require "MenuHexButton"
local MenuTextItem = require "MenuTextItem"
local MenuVolumeRow = require "MenuVolumeRow"
local MenuConfirmDialog = require "MenuConfirmDialog"
local MenuHoverTint = require "MenuHoverTint"
local AudioSettings = require "AudioSettings"
local Sfx = require "Sfx"

---@class MenuHud
---@field root Widget|nil
---@field overlay Widget|nil
---@field panel Widget|nil
---@field panelHost Widget|nil
---@field hexButton MenuHexButton|nil
---@field hintLabel Widget|nil
---@field showMenuHint boolean
---@field hintAmount number
---@field hintFrom number
---@field hintTo number
---@field hintElapsed number
---@field hintDuration number
---@field bgmRow MenuVolumeRow|nil
---@field sfxRow MenuVolumeRow|nil
---@field items MenuTextItem[]
---@field confirm table|nil
---@field open boolean
---@field confirmOpen boolean
---@field confirmKind string|nil
---@field toggleArmed boolean
---@field openAmount number
---@field openFrom number
---@field openTo number
---@field openElapsed number
---@field openDuration number
---@field hoverColor number[]
---@field onOpenChanged fun(open: boolean)|nil
---@field onUnlockAll fun()|nil
---@field onResetProgress fun()|nil
---@field onCredits fun()|nil
---@field onQuit fun()|nil
local MenuHud = {}
MenuHud.__index = MenuHud

local OVERLAY_COLOR = { 8, 7, 6, 230 }
local TITLE_COLOR = { 255, 248, 236, 255 }
local LINE_COLOR = { 255, 255, 255, 38 }
local OPEN_SECONDS = 0.2
local PANEL_WIDTH = 820
local BUTTON_FADE = 0.85
local HINT_FADE = 0.35

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/MiSans-Regular.ttf",
                    bold = "Fonts/MiSans-Bold.ttf",
                },
            },
        },
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })
    UI.SetScale(UI.Scale.DESIGN_RESOLUTION(1920, 1080))
end

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function EaseOutCubic(t)
    local inverse = 1.0 - Clamp01(t)
    return 1.0 - inverse * inverse * inverse
end

local function Hairline()
    return UI.Panel {
        width = "100%",
        height = 1,
        backgroundColor = LINE_COLOR,
        pointerEvents = "none",
    }
end

function MenuHud.New()
    local self = setmetatable({}, MenuHud)
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.overlay = nil
    ---@type Widget|nil
    self.panel = nil
    ---@type Widget|nil
    self.panelHost = nil
    ---@type MenuHexButton|nil
    self.hexButton = nil
    ---@type Widget|nil
    self.hintLabel = nil
    self.showMenuHint = false
    self.hintAmount = 0.0
    self.hintFrom = 0.0
    self.hintTo = 0.0
    self.hintElapsed = 0.0
    self.hintDuration = 0.0
    ---@type MenuVolumeRow|nil
    self.bgmRow = nil
    ---@type MenuVolumeRow|nil
    self.sfxRow = nil
    ---@type MenuTextItem[]
    self.items = {}
    ---@type table|nil
    self.confirm = nil
    self.open = false
    self.confirmOpen = false
    ---@type string|nil
    self.confirmKind = nil
    self.toggleArmed = true
    self.openAmount = 0.0
    self.openFrom = 0.0
    self.openTo = 0.0
    self.openElapsed = 0.0
    self.openDuration = 0.0
    self.hoverColor = MenuHoverTint.FromFog(nil)
    ---@type fun(open: boolean)|nil
    self.onOpenChanged = nil
    ---@type fun()|nil
    self.onUnlockAll = nil
    ---@type fun()|nil
    self.onResetProgress = nil
    ---@type fun()|nil
    self.onCredits = nil
    ---@type fun()|nil
    self.onFeel = nil
    ---@type fun()|nil
    self.onQuit = nil
    return self
end

function MenuHud:IsOpen()
    return self.open
end

function MenuHud:IsConfirmOpen()
    return self.confirmOpen
end

function MenuHud:SetToggleArmed(armed)
    self.toggleArmed = armed == true
    if self.hexButton then
        self.hexButton:SetClickArmed(self.toggleArmed)
    end
    self:ApplyHintVisible()
end

function MenuHud:ApplyHoverColor()
    for i = 1, #self.items do
        self.items[i]:SetHoverColor(self.hoverColor)
    end
    if self.bgmRow then
        self.bgmRow:SetThumbColor(self.hoverColor)
    end
    if self.sfxRow then
        self.sfxRow:SetThumbColor(self.hoverColor)
    end
    if self.confirm then
        self.confirm.cancelItem:SetHoverColor(self.hoverColor)
        self.confirm.confirmItem:SetHoverColor(self.hoverColor)
    end
end

function MenuHud:SetFogColor(color)
    self.hoverColor = MenuHoverTint.FromFog(color)
    self:ApplyHoverColor()
end

function MenuHud:ApplyHintVisual()
    if not self.hintLabel then
        return
    end
    local t = EaseOutCubic(self.hintAmount)
    self.hintLabel:SetStyle({ opacity = t })
    self.hintLabel:SetVisible(t > 0.001)
end

function MenuHud:TweenHintTo(target, instant)
    local to = Clamp01(target)
    if instant then
        self.hintAmount = to
        self.hintTo = to
        self.hintDuration = 0.0
        self:ApplyHintVisual()
        return
    end
    if math.abs(self.hintTo - to) < 0.001 and self.hintDuration <= 0.0 then
        return
    end
    self.hintFrom = self.hintAmount
    self.hintTo = to
    self.hintElapsed = 0.0
    self.hintDuration = HINT_FADE
    self:ApplyHintVisual()
end

function MenuHud:ApplyHintVisible()
    local show = self.showMenuHint == true and not self.open and self.toggleArmed
    self:TweenHintTo(show and 1.0 or 0.0, false)
end

function MenuHud:SetMenuHintVisible(visible)
    self.showMenuHint = visible == true
    self:ApplyHintVisible()
end

function MenuHud:SyncVolumes()
    if self.bgmRow then
        self.bgmRow:SetVolume(AudioSettings.BgmVolume())
    end
    if self.sfxRow then
        self.sfxRow:SetVolume(AudioSettings.SfxVolume())
    end
end

function MenuHud:AddItem(text, onSelect)
    local item = MenuTextItem {
        text = text,
        onSelect = function()
            Sfx.PlayModalClick()
            if onSelect then
                onSelect()
            end
        end,
    }
    item:SetHoverColor(self.hoverColor)
    self.items[#self.items + 1] = item
    return item
end

function MenuHud:Build()
    EnsureUI()
    self.items = {}
    self.bgmRow = MenuVolumeRow {
        title = "音乐音量",
        value = AudioSettings.BgmVolume(),
        thumbColor = self.hoverColor,
        onVolume = function(value, persist)
            AudioSettings.SetBgmVolume(value, persist)
        end,
    }
    self.sfxRow = MenuVolumeRow {
        title = "音效音量",
        value = AudioSettings.SfxVolume(),
        thumbColor = self.hoverColor,
        onVolume = function(value, persist)
            AudioSettings.SetSfxVolume(value, persist)
        end,
    }
    local unlockItem = self:AddItem("解锁所有关卡", function()
        self:ShowConfirm("unlock")
    end)
    local resetItem = self:AddItem("重置进度", function()
        self:ShowConfirm("reset")
    end)
    local feelItem = self:AddItem("手感调节", function()
        if self.onFeel then
            self.onFeel()
        end
    end)
    local creditsItem = self:AddItem("播放制作人员名单", function()
        if self.onCredits then
            self.onCredits()
        end
    end)
    local quitItem = self:AddItem("退出游戏", function()
        self:ShowConfirm("quit")
    end)
    self.panel = UI.Panel {
        width = PANEL_WIDTH,
        alignItems = "stretch",
        gap = 28,
        opacity = 0.0,
        pointerEvents = "none",
        children = {
            UI.Label {
                text = "菜单",
                width = "100%",
                fontSize = 44,
                fontColor = TITLE_COLOR,
                fontWeight = "bold",
                textAlign = "center",
                marginBottom = 48,
                pointerEvents = "none",
            },
            self.bgmRow,
            self.sfxRow,
            Hairline(),
            unlockItem,
            Hairline(),
            resetItem,
            Hairline(),
            feelItem,
            Hairline(),
            creditsItem,
            Hairline(),
            quitItem,
            Hairline(),
        },
    }
    self.panelHost = UI.Panel {
        pointerEvents = "none",
        children = {
            self.panel,
        },
    }
    self.overlay = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        borderRadius = 0,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = OVERLAY_COLOR,
        opacity = 0.0,
        pointerEvents = "none",
        onClick = function()
            if self.open and not self.confirmOpen then
                Sfx.PlayModalClick()
                self:Close()
            end
        end,
    }
    self.hexButton = MenuHexButton {
        onToggle = function()
            Sfx.PlayModalClick()
            self:Toggle()
        end,
    }
    self.hintLabel = UI.Label {
        text = "←点击此处可打开菜单，调整音量",
        fontSize = 20,
        fontColor = { 255, 248, 236, 220 },
        fontWeight = "normal",
        pointerEvents = "none",
        opacity = 0.0,
        visible = false,
        marginLeft = 12,
    }
    self.confirm = MenuConfirmDialog.Build({
        hoverColor = self.hoverColor,
        onCancel = function()
            Sfx.PlayModalClick()
            self:HideConfirm()
        end,
        onOverlay = function()
            Sfx.PlayModalClick()
            self:HideConfirm()
        end,
        onConfirm = function()
            Sfx.PlayModalClick()
            self:ConfirmCurrent()
        end,
    })
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        borderRadius = 0,
        pointerEvents = "box-none",
        children = {
            self.overlay,
            UI.Panel {
                position = "absolute",
                left = 0,
                right = 0,
                top = 0,
                bottom = 0,
                alignItems = "center",
                justifyContent = "center",
                pointerEvents = "box-none",
                children = {
                    self.panelHost,
                },
            },
            UI.Panel {
                position = "absolute",
                left = 0,
                top = 0,
                height = 140,
                paddingTop = 24,
                paddingLeft = 24,
                flexDirection = "row",
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    self.hexButton,
                    self.hintLabel,
                },
            },
            self.confirm.root,
        },
    }
    self:ApplyHoverColor()
    self:ApplyOpenVisual()
end

function MenuHud:ApplyOpenVisual()
    local t = EaseOutCubic(self.openAmount)
    if self.overlay then
        self.overlay:SetStyle({ opacity = t })
        self.overlay:SetProp("pointerEvents", t > 0.05 and "auto" or "none")
        self.overlay:SetVisible(t > 0.001)
    end
    if self.panel then
        self.panel:SetStyle({ opacity = t })
        self.panel:SetProp("pointerEvents", self.open and "auto" or "none")
    end
    if self.panelHost then
        self.panelHost:SetProp("pointerEvents", self.open and "auto" or "none")
    end
    if self.hexButton then
        self.hexButton:SetOpened(self.open, self.openDuration <= 0.0)
    end
end

function MenuHud:SetOpen(open, instant)
    local target = open == true
    if self.open == target and self.openDuration <= 0.0 then
        return
    end
    self.open = target
    if not target then
        self:HideConfirm(true)
    end
    self.openFrom = self.openAmount
    self.openTo = target and 1.0 or 0.0
    if instant then
        self.openAmount = self.openTo
        self.openDuration = 0.0
        self:ApplyOpenVisual()
    else
        self.openElapsed = 0.0
        self.openDuration = OPEN_SECONDS
        self:ApplyOpenVisual()
    end
    if self.onOpenChanged then
        self.onOpenChanged(self.open)
    end
    self:ApplyHintVisible()
    print("MenuHud: " .. (self.open and "open" or "close"))
end

function MenuHud:Open()
    if not self.toggleArmed then
        return
    end
    self:SetOpen(true, false)
end

function MenuHud:Close()
    self:SetOpen(false, false)
end

function MenuHud:Toggle()
    if not self.toggleArmed then
        return
    end
    if self.confirmOpen then
        self:HideConfirm()
        return
    end
    self:SetOpen(not self.open, false)
end

function MenuHud:ShowConfirm(kind)
    if not self.confirm then
        return
    end
    self.confirmKind = kind or "reset"
    self.confirm.pendingConfirm = false
    MenuConfirmDialog.SetCopy(self.confirm, self.confirmKind)
    self.confirmOpen = true
    MenuConfirmDialog.SetOpen(self.confirm, true, false)
end

function MenuHud:HideConfirm(instant)
    if not self.confirm then
        self.confirmOpen = false
        self.confirmKind = nil
        return
    end
    self.confirmOpen = false
    if not self.confirm.pendingConfirm then
        self.confirmKind = nil
    end
    MenuConfirmDialog.SetOpen(self.confirm, false, instant == true)
    if instant then
        if self.confirm.pendingConfirm then
            self:FinishConfirm()
            return
        end
        self.confirmKind = nil
    end
end

function MenuHud:ConfirmCurrent()
    if not self.confirm then
        return
    end
    self.confirm.pendingConfirm = true
    self.confirmOpen = false
    MenuConfirmDialog.SetOpen(self.confirm, false, false)
end

function MenuHud:FinishConfirm()
    local kind = self.confirmKind
    local pending = self.confirm and self.confirm.pendingConfirm
    if self.confirm then
        self.confirm.pendingConfirm = false
    end
    self.confirmKind = nil
    if not pending then
        return
    end
    if kind == "unlock" then
        if self.onUnlockAll then
            self.onUnlockAll()
        end
        return
    end
    if kind == "reset" and self.onResetProgress then
        self.onResetProgress()
        return
    end
    if kind == "quit" and self.onQuit then
        self.onQuit()
    end
end

function MenuHud:BeginEnterFade()
    self:SetToggleArmed(true)
    if self.hexButton then
        self.hexButton:SetIconAlpha(0.0)
        self.hexButton:FadeTo(1.0, BUTTON_FADE)
    end
    self:ApplyHintVisible()
    print("MenuHud: hex button fade in")
end

function MenuHud:Show()
    self:Build()
    UI.SetRoot(self.root, true)
    print("MenuHud: shown")
end

function MenuHud:BeginExitFade()
    self:SetToggleArmed(false)
    if self.confirmOpen then
        self:HideConfirm(true)
    end
    if self.open then
        self:SetOpen(false, false)
    end
    if self.hexButton then
        self.hexButton:FadeTo(0.0, BUTTON_FADE)
    end
    self:ApplyHintVisible()
    print("MenuHud: hex button fade out")
end

function MenuHud:Hide()
    self.open = false
    self.confirmOpen = false
    self.confirmKind = nil
    self.openAmount = 0.0
    self.openDuration = 0.0
    self.hintAmount = 0.0
    self.hintDuration = 0.0
    if self.root then
        UI.SetRoot(nil, true)
    end
    self.root = nil
    self.overlay = nil
    self.panel = nil
    self.panelHost = nil
    self.hexButton = nil
    self.hintLabel = nil
    self.bgmRow = nil
    self.sfxRow = nil
    self.items = {}
    self.confirm = nil
end

function MenuHud:HandleEscape()
    if self.confirmOpen then
        Sfx.PlayModalClick()
        self:HideConfirm()
        return true
    end
    if self.open then
        Sfx.PlayModalClick()
        self:Close()
        return true
    end
    if not self.toggleArmed then
        return false
    end
    Sfx.PlayModalClick()
    self:Open()
    return true
end

function MenuHud:Update(timeStep)
    if self.confirm then
        local finished = MenuConfirmDialog.Update(self.confirm, timeStep)
        if finished and not self.confirm.open then
            self:FinishConfirm()
        end
    end
    if self.hintDuration > 0.0 then
        self.hintElapsed = self.hintElapsed + timeStep
        local hintT = Clamp01(self.hintElapsed / self.hintDuration)
        self.hintAmount = self.hintFrom + (self.hintTo - self.hintFrom) * hintT
        self:ApplyHintVisual()
        if hintT >= 1.0 then
            self.hintAmount = self.hintTo
            self.hintDuration = 0.0
            self:ApplyHintVisual()
        end
    end
    if self.openDuration <= 0.0 then
        return
    end
    self.openElapsed = self.openElapsed + timeStep
    local t = Clamp01(self.openElapsed / self.openDuration)
    self.openAmount = self.openFrom + (self.openTo - self.openFrom) * t
    self:ApplyOpenVisual()
    if t >= 1.0 then
        self.openAmount = self.openTo
        self.openDuration = 0.0
        self:ApplyOpenVisual()
    end
end

return MenuHud
