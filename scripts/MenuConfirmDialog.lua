-- 选关二级确认。叠在菜单之上，不关一级菜单。
-- 只负责文案、排版和淡入放大；打开/关闭由 MenuHud 驱动。

local UI = require("urhox-libs/UI")
local MenuTextItem = require "MenuTextItem"
local MenuHoverTint = require "MenuHoverTint"

local MenuConfirmDialog = {}

local TITLE_COLOR = { 255, 248, 236, 255 }
local BODY_COLOR = { 232, 220, 200, 255 }
local OVERLAY_COLOR = { 6, 5, 4, 236 }
local OPEN_SECONDS = 0.22
local START_SCALE = 0.92

local COPY = {
    reset = {
        title = "确定清除全部进度？",
        body = "走过的关卡记录将无法恢复。",
    },
    unlock = {
        title = "确定解锁全部关卡？",
        body = "解锁后可自由进入后续章节，但可能会错过沿途的故事与记忆。",
    },
}

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

function MenuConfirmDialog.Build(props)
    props = props or {}
    local hoverColor = props.hoverColor or MenuHoverTint.FromFog(nil)
    local title = UI.Label {
        text = COPY.reset.title,
        width = "100%",
        fontSize = 32,
        fontColor = TITLE_COLOR,
        fontWeight = "bold",
        textAlign = "center",
        pointerEvents = "none",
    }
    local body = UI.Label {
        text = COPY.reset.body,
        width = "100%",
        fontSize = 20,
        fontColor = BODY_COLOR,
        fontWeight = "bold",
        textAlign = "center",
        pointerEvents = "none",
        whiteSpace = "normal",
    }
    local cancelItem = MenuTextItem {
        text = "取消",
        width = 200,
        onSelect = props.onCancel,
    }
    cancelItem:SetHoverColor(hoverColor)
    local confirmItem = MenuTextItem {
        text = "确定",
        width = 200,
        onSelect = props.onConfirm,
    }
    confirmItem:SetHoverColor(hoverColor)
    local panel = UI.Panel {
        width = 640,
        alignItems = "center",
        gap = 28,
        opacity = 0.0,
        scale = START_SCALE,
        pointerEvents = "none",
        children = {
            title,
            body,
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                gap = 80,
                marginTop = 20,
                children = {
                    cancelItem,
                    confirmItem,
                },
            },
        },
    }
    local root = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        borderRadius = 0,
        backgroundColor = OVERLAY_COLOR,
        visible = false,
        opacity = 0.0,
        pointerEvents = "none",
        onClick = function()
            if props.onOverlay then
                props.onOverlay()
            elseif props.onCancel then
                props.onCancel()
            end
        end,
        children = {
            UI.Panel {
                pointerEvents = "auto",
                children = {
                    panel,
                },
            },
        },
    }
    return {
        root = root,
        panel = panel,
        title = title,
        body = body,
        cancelItem = cancelItem,
        confirmItem = confirmItem,
        kind = nil,
        open = false,
        amount = 0.0,
        from = 0.0,
        to = 0.0,
        elapsed = 0.0,
        duration = 0.0,
        pendingConfirm = false,
    }
end

function MenuConfirmDialog.ApplyVisual(dialog)
    local t = EaseOutCubic(dialog.amount)
    if dialog.root then
        dialog.root:SetStyle({ opacity = t })
        dialog.root:SetVisible(t > 0.001)
        dialog.root:SetProp("pointerEvents", t > 0.05 and "auto" or "none")
    end
    if dialog.panel then
        dialog.panel:SetStyle({
            opacity = t,
            scale = START_SCALE + (1.0 - START_SCALE) * t,
        })
        dialog.panel:SetProp("pointerEvents", dialog.open and "auto" or "none")
    end
end

function MenuConfirmDialog.SetCopy(dialog, kind)
    local copy = COPY[kind] or COPY.reset
    dialog.kind = kind
    if dialog.title then
        dialog.title:SetText(copy.title)
    end
    if dialog.body then
        dialog.body:SetText(copy.body)
    end
end

function MenuConfirmDialog.SetOpen(dialog, open, instant)
    local target = open == true
    dialog.open = target
    dialog.from = dialog.amount
    dialog.to = target and 1.0 or 0.0
    if instant then
        dialog.amount = dialog.to
        dialog.duration = 0.0
        dialog.elapsed = 0.0
        MenuConfirmDialog.ApplyVisual(dialog)
        return
    end
    dialog.elapsed = 0.0
    dialog.duration = OPEN_SECONDS
    MenuConfirmDialog.ApplyVisual(dialog)
end

function MenuConfirmDialog.Update(dialog, timeStep)
    if not dialog or dialog.duration <= 0.0 then
        return false
    end
    dialog.elapsed = dialog.elapsed + timeStep
    local t = Clamp01(dialog.elapsed / dialog.duration)
    dialog.amount = dialog.from + (dialog.to - dialog.from) * t
    MenuConfirmDialog.ApplyVisual(dialog)
    if t < 1.0 then
        return false
    end
    dialog.amount = dialog.to
    dialog.duration = 0.0
    MenuConfirmDialog.ApplyVisual(dialog)
    return true
end

return MenuConfirmDialog
