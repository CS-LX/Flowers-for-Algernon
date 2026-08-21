-- 可复用的 PNG 图标主题工具栏。
-- 工具主题显示在左侧窄轨；子模式在主题按钮右侧绝对定位展开。

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")

local IconToolPalette = {}
IconToolPalette.__index = IconToolPalette

local PALETTE_BG = { 20, 25, 34, 245 }
local BUTTON_BG = { 16, 20, 27, 250 }
local BUTTON_HOVER = { 35, 43, 57, 255 }
local ACTIVE_BG = { 70, 121, 215, 255 }
local ACTIVE_HOVER = { 88, 143, 235, 255 }
local BORDER = { 81, 95, 116, 220 }
local ACTIVE_BORDER = { 160, 204, 255, 255 }
local MENU_BG = { 19, 25, 35, 252 }
local TEXT = { 225, 234, 246, 255 }
local MUTED = { 153, 168, 188, 255 }
local ICON_ROOT = "image/editor-icons/"

local function Color(nvg, color)
    return nvgRGBA(color[1], color[2], color[3], color[4] or 255)
end

local function DrawImage(nvg, path, rect, tint)
    local handle = ImageCache.Get(path)
    if not handle or handle <= 0 then
        return false
    end
    local paint = nvgImagePattern(nvg, rect.x, rect.y, rect.w, rect.h, 0, handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, rect.x, rect.y, rect.w, rect.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    return true
end

local function DrawChevron(nvg, x, y, size, color)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x - size, y - size * 0.35)
    nvgLineTo(nvg, x, y + size * 0.55)
    nvgLineTo(nvg, x + size, y - size * 0.35)
    nvgStrokeColor(nvg, Color(nvg, color))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

local IconToolButton = Widget:Extend("IconToolButton")

function IconToolButton:Init(props)
    props = props or {}
    props.width = props.width or 48
    props.height = props.height or 48
    props.borderRadius = props.borderRadius or 6
    props.pointerEvents = "auto"
    self.state = { hovered = false, pressed = false }
    self:ApplyStyleToYoga(props)
    self:ProcessChildren(props)
end

function IconToolButton:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local active = props.active == true
    local bg = active and ACTIVE_BG or BUTTON_BG
    if self.state.hovered then
        bg = active and ACTIVE_HOVER or BUTTON_HOVER
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, props.borderRadius or 6)
    nvgFillColor(nvg, Color(nvg, bg))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x + 0.5, l.y + 0.5, l.w - 1, l.h - 1, props.borderRadius or 6)
    nvgStrokeColor(nvg, Color(nvg, active and ACTIVE_BORDER or BORDER))
    nvgStrokeWidth(nvg, active and 1.5 or 1)
    nvgStroke(nvg)
    DrawImage(nvg, props.iconPath, {
        x = l.x + 8, y = l.y + 8, w = l.w - 16, h = l.h - 16,
    }, props.disabled and MUTED or TEXT)
    if props.hasModes then
        DrawChevron(nvg, l.x + l.w - 8, l.y + l.h - 7, 3.2, props.disabled and MUTED or TEXT)
    end
end

function IconToolButton:OnMouseEnter()
    self.state.hovered = not self.props.disabled
end

function IconToolButton:OnMouseLeave()
    self.state.hovered = false
    self.state.pressed = false
end

function IconToolButton:OnPointerDown(event)
    if event and event:IsPrimaryAction() and not self.props.disabled then
        self.state.pressed = true
    end
end

function IconToolButton:OnPointerUp(event)
    if event and event:IsPrimaryAction() then
        self.state.pressed = false
    end
end

function IconToolButton:OnClick(event)
    if self.props.disabled then
        return
    end
    local l = self:GetAbsoluteLayout()
    local menuClick = self.props.hasModes and event
        and event.x >= l.x + l.w - 16
        and event.y >= l.y + l.h - 16
    if menuClick then
        self.props.onOpenModes(self)
    elseif self.props.onActivate then
        self.props.onActivate(self)
    end
end

function IconToolButton:OnLongPressStart(event)
    if not self.props.disabled and self.props.hasModes then
        self.props.onOpenModes(self, event)
    end
end

local IconModeButton = Widget:Extend("IconModeButton")

function IconModeButton:Init(props)
    props = props or {}
    props.width = props.width or 172
    props.height = props.height or 34
    props.borderRadius = props.borderRadius or 5
    props.pointerEvents = "auto"
    self.state = { hovered = false }
    self:ApplyStyleToYoga(props)
    self:ProcessChildren(props)
end

function IconModeButton:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local bg = props.selected and ACTIVE_BG or BUTTON_BG
    if self.state.hovered then
        bg = props.selected and ACTIVE_HOVER or BUTTON_HOVER
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 5)
    nvgFillColor(nvg, Color(nvg, bg))
    nvgFill(nvg)
    DrawImage(nvg, props.iconPath, {
        x = l.x + 6, y = l.y + 5, w = 24, h = 24,
    }, TEXT)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Color(nvg, TEXT))
    nvgText(nvg, l.x + 38, l.y + l.h * 0.5, props.label, nil)
end

function IconModeButton:OnMouseEnter()
    self.state.hovered = not self.props.disabled
end

function IconModeButton:OnMouseLeave()
    self.state.hovered = false
end

function IconModeButton:OnClick()
    if not self.props.disabled and self.props.onSelect then
        self.props.onSelect(self.props.modeId)
    end
end

function IconToolPalette.New(config)
    local self = setmetatable({}, IconToolPalette)
    self.config = config or {}
    self.activeToolId = self.config.activeToolId
    self.activeModes = self.config.activeModes or {}
    self.buttonWidgets = {}
    self.modePanels = {}
    self.modePanelAnchors = {}
    self.root = nil
    return self
end

function IconToolPalette:Select(toolId, modeId)
    self.activeToolId = toolId
    self.activeModes[toolId] = modeId
    if self.config.onSelect then
        self.config.onSelect(toolId, modeId)
    end
    for _, panel in pairs(self.modePanels) do
        panel:Hide()
    end
    self:Refresh()
end

function IconToolPalette:OpenModes(toolId)
    for id, panel in pairs(self.modePanels) do
        if id == toolId then
            local buttonLayout = self.buttonWidgets[id]:GetAbsoluteLayout()
            local rootLayout = self.root:GetAbsoluteLayout()
            local viewportWidth, viewportHeight = UI.GetViewportSize()
            local width = 184
            local height = math.min(316, 10 + #self.config.toolsById[id].modes * 37)
            local screenLeft = buttonLayout.x + buttonLayout.w + 6
            local screenTop = buttonLayout.y
            if screenLeft + width > viewportWidth - 8 then
                screenLeft = math.max(8, buttonLayout.x - width - 6)
            end
            if screenTop + height > viewportHeight - 8 then
                screenTop = math.max(8, viewportHeight - height - 8)
            end
            panel:SetStyle({
                position = "absolute",
                left = screenLeft - rootLayout.x,
                top = screenTop - rootLayout.y,
                width = width,
                height = height,
                maxHeight = height,
                overflow = "hidden",
                zIndex = 1000,
            })
            panel:SetVisible(not panel:IsVisible())
        else
            panel:Hide()
        end
    end
end

function IconToolPalette:Refresh()
    for toolId, button in pairs(self.buttonWidgets) do
        button.props.active = toolId == self.activeToolId
    end
    for toolId, panel in pairs(self.modePanels) do
        local tool = self.config.toolsById[toolId]
        if tool then
            panel:ClearChildren()
            local selected = self.activeModes[toolId] or tool.modes[1].id
            for _, mode in ipairs(tool.modes) do
                panel:AddChild(IconModeButton {
                    modeId = mode.id,
                    label = mode.label,
                    iconPath = ICON_ROOT .. mode.icon .. ".png",
                    selected = mode.id == selected,
                    onSelect = function(modeId)
                        self:Select(toolId, modeId)
                    end,
                })
            end
        end
    end
end

function IconToolPalette:Build()
    local tools = self.config.tools or {}
    self.config.toolsById = {}
    local children = {}
    local row = 0
    for _, tool in ipairs(tools) do
        self.config.toolsById[tool.id] = tool
        local modeCount = #(tool.modes or {})
        local button = IconToolButton {
            id = "icon-tool-" .. tool.id,
            iconPath = ICON_ROOT .. tool.icon .. ".png",
            active = tool.id == self.activeToolId,
            hasModes = modeCount > 1,
            onActivate = function()
                self:Select(tool.id, self.activeModes[tool.id] or tool.modes[1].id)
            end,
            onOpenModes = function()
                self:OpenModes(tool.id)
            end,
        }
        self.buttonWidgets[tool.id] = button
        children[#children + 1] = button
        if modeCount > 1 then
            local panel = UI.Panel {
                position = "absolute",
                left = 68,
                top = 7 + row * 54,
                width = 184,
                maxHeight = 300,
                padding = 5,
                gap = 3,
                overflow = "hidden",
                zIndex = 1000,
                visible = false,
                backgroundColor = MENU_BG,
                borderColor = BORDER,
                borderWidth = 1,
                borderRadius = 6,
                boxShadow = { { x = 0, y = 4, blur = 10, color = { 0, 0, 0, 100 } } },
            }
            self.modePanels[tool.id] = panel
            children[#children + 1] = panel
        end
        row = row + 1
    end
    self.root = UI.Panel {
        position = "relative",
        width = 62,
        padding = 7,
        gap = 6,
        backgroundColor = PALETTE_BG,
        borderColor = BORDER,
        borderWidth = 1,
        borderRadius = 8,
        alignItems = "center",
        overflow = "visible",
        children = children,
    }
    self:Refresh()
    return self.root
end

return IconToolPalette
