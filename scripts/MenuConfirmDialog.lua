-- 重置进度确认。叠在菜单之上，不关菜单。

local UI = require("urhox-libs/UI")
local MenuTextItem = require "MenuTextItem"
local MenuHoverTint = require "MenuHoverTint"

local MenuConfirmDialog = {}

local TITLE_COLOR = { 255, 248, 236, 255 }
local BODY_COLOR = { 214, 196, 168, 230 }

function MenuConfirmDialog.Build(props)
    props = props or {}
    local hoverColor = props.hoverColor or MenuHoverTint.FromFog(nil)
    local cancelItem = MenuTextItem {
        text = "取消",
        width = 180,
        onSelect = props.onCancel,
    }
    cancelItem:SetHoverColor(hoverColor)
    local confirmItem = MenuTextItem {
        text = "确定",
        width = 180,
        onSelect = props.onConfirm,
    }
    confirmItem:SetHoverColor(hoverColor)
    local root = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        alignItems = "center",
        justifyContent = "center",
        borderRadius = 0,
        backgroundColor = { 6, 5, 4, 236 },
        visible = false,
        pointerEvents = "none",
        children = {
            UI.Panel {
                width = 560,
                alignItems = "center",
                gap = 10,
                pointerEvents = "auto",
                children = {
                    UI.Label {
                        text = "确定清除全部进度？",
                        width = "100%",
                        fontSize = 28,
                        fontColor = TITLE_COLOR,
                        fontWeight = "bold",
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "关卡记录将无法恢复。",
                        width = "100%",
                        fontSize = 18,
                        fontColor = BODY_COLOR,
                        textAlign = "center",
                        marginBottom = 18,
                        pointerEvents = "none",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 48,
                        children = {
                            cancelItem,
                            confirmItem,
                        },
                    },
                },
            },
        },
    }
    return {
        root = root,
        cancelItem = cancelItem,
        confirmItem = confirmItem,
    }
end

return MenuConfirmDialog
