-- Level Object Tree Inspector 的共享样式与小工具。
-- 不持有关卡数据；只给关卡 Tab 和 Part Tab 复用绘制约定。

local UI = require("urhox-libs/UI")

local Shared = {}

Shared.PANEL = { 21, 27, 38, 244 }
Shared.BORDER = { 92, 112, 140, 180 }
Shared.TEXT = { 231, 238, 248, 255 }
Shared.MUTED = { 145, 160, 184, 255 }
Shared.COMPONENT_HEADER = { 29, 36, 50, 255 }
Shared.COMPONENT_ACCENT = { 78, 132, 194, 255 }
-- 原 Inspector 滚轮倍率为 40，按 0.01 降低灵敏度。
Shared.WHEEL_SCALE = 0.4
-- ColorPicker 弹层固定画在字段下方，底部留空才能滚进视口。
Shared.COLOR_POPUP_SPACER = 280

function Shared.ColorPopupSpacer()
    return UI.Panel {
        width = "100%",
        height = Shared.COLOR_POPUP_SPACER,
        flexShrink = 0,
    }
end

function Shared.ModeText(part)
    if not part or #part.behaviorModes == 0 then
        return "无运行时行为"
    end
    return table.concat(part.behaviorModes, " + ")
end

function Shared.ComponentHeader(icon, title)
    return UI.Panel {
        height = 29,
        paddingHorizontal = 8,
        flexDirection = "row",
        alignItems = "center",
        gap = 7,
        backgroundColor = Shared.COMPONENT_HEADER,
        borderTopWidth = 1,
        borderBottomWidth = 1,
        borderTopColor = Shared.BORDER,
        borderBottomColor = Shared.BORDER,
        children = {
            UI.Label { text = "▾", width = 10, fontSize = 10, fontColor = Shared.MUTED },
            UI.Label { text = icon, width = 16, fontSize = 12, fontColor = Shared.COMPONENT_ACCENT },
            UI.Label { text = title, flexGrow = 1, fontSize = 11, fontWeight = "bold", fontColor = Shared.TEXT },
            UI.Label { text = "?  ⋮", fontSize = 10, fontColor = Shared.MUTED },
        },
    }
end

function Shared.HexToRgb(hex)
    hex = tostring(hex or ""):gsub("#", "")
    if #hex < 6 then
        return { r = 255, g = 255, b = 255, a = 255 }
    end
    return {
        r = tonumber(hex:sub(1, 2), 16) or 255,
        g = tonumber(hex:sub(3, 4), 16) or 255,
        b = tonumber(hex:sub(5, 6), 16) or 255,
        a = 255,
    }
end

function Shared.ColorField(opts)
    opts = opts or {}
    return UI.ColorPicker {
        size = "sm",
        height = 26,
        fontSize = 10,
        width = "100%",
        showAlpha = false,
        showPresets = true,
        value = Shared.HexToRgb(opts.color or "#FFFFFF"),
        onChange = opts.onChange,
        onClose = opts.onClose,
    }
end

function Shared.FieldRow(label, content)
    return UI.Panel {
        minHeight = 28,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label { text = label, width = 62, flexShrink = 0, fontSize = 10, fontColor = Shared.MUTED },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                minWidth = 0,
                children = { content },
            },
        },
    }
end

function Shared.IsPointerInsideWidget(widget)
    local scale = UI.GetScale()
    local mouse = input:GetMousePosition()
    local x = mouse.x / scale
    local y = mouse.y / scale
    local layout = widget:GetAbsoluteLayoutForHitTest()
    return x >= layout.x and x <= layout.x + layout.w
        and y >= layout.y and y <= layout.y + layout.h
end

function Shared.BindSlowWheel(scroll)
    scroll.OnWheel = function(_, dx, dy)
        if not Shared.IsPointerInsideWidget(scroll) then
            return false
        end
        scroll:ScrollBy(-dx * Shared.WHEEL_SCALE, -dy * Shared.WHEEL_SCALE)
        return true
    end
end

return Shared
