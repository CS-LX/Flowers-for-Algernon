-- 静物 Inspector。
-- 只编辑装饰物的名称、父级和局部任意坐标；不能打开体素编辑器。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"

local StillObjectInspector = {}
StillObjectInspector.__index = StillObjectInspector

function StillObjectInspector.New(editor)
    local self = setmetatable({}, StillObjectInspector)
    self.editor = editor
    self.scroll = nil
    self.selectionLabel = nil
    self.nameField = nil
    self.parentDropdown = nil
    self.posXField = nil
    self.posYField = nil
    self.posZField = nil
    self.rotYField = nil
    self.scaleField = nil
    self.modelLabel = nil
    self.triggerableToggle = nil
    self.triggerIdField = nil
    self.interactionLabel = nil
    return self
end

function StillObjectInspector:Build()
    local editor = self.editor
    self.selectionLabel = UI.Label {
        text = "未选择静物",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = Shared.TEXT,
    }
    self.nameField = UI.TextField {
        value = "",
        placeholder = "静物名称",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillName(value) end,
    }
    self.parentDropdown = UI.Dropdown {
        options = {},
        value = "",
        placeholder = "父级",
        height = 28,
        fontSize = 11,
        onChange = function(_, value) editor:SetSelectedStillParent(value == "" and nil or value) end,
    }
    self.posXField = UI.TextField {
        value = "0", placeholder = "X", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("x", value) end,
    }
    self.posYField = UI.TextField {
        value = "0", placeholder = "Y", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("y", value) end,
    }
    self.posZField = UI.TextField {
        value = "0", placeholder = "Z", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("z", value) end,
    }
    self.rotYField = UI.TextField {
        value = "0", placeholder = "Yaw", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillYaw(value) end,
    }
    self.scaleField = UI.TextField {
        value = "1.0", placeholder = "Scale", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillScale(value) end,
    }
    self.modelLabel = UI.Label {
        text = "占位模型：Box",
        fontSize = 10,
        fontColor = Shared.MUTED,
        whiteSpace = "normal",
    }
    self.triggerableToggle = UI.Checkbox {
        checked = false,
        label = "Triggerable",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedStillInteraction("triggerable", checked) end,
    }
    self.triggerIdField = UI.TextField {
        value = "",
        placeholder = "Trigger ID",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillTriggerId(value) end,
    }
    self.interactionLabel = UI.Label {
        text = "静物只能挂交互组件，不能挂 rotator / mover。",
        fontSize = 9,
        fontColor = Shared.MUTED,
        whiteSpace = "normal",
    }

    self.scroll = UI.ScrollView {
        width = "100%",
        height = "100%",
        padding = 0,
        gap = 0,
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        scrollY = true,
        scrollX = false,
        showScrollbar = true,
        scrollbarInteractive = true,
        bounces = false,
        backgroundColor = Shared.PANEL,
        children = {
            UI.Panel {
                padding = 8,
                gap = 5,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    self.selectionLabel,
                    Shared.FieldRow("Name", self.nameField),
                    Shared.FieldRow("Parent", self.parentDropdown),
                },
            },
            Shared.ComponentHeader("◈", "Local Transform"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label { text = "不吸附网格，坐标是父节点局部米制。", fontSize = 9, fontColor = Shared.MUTED, whiteSpace = "normal" },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label { text = "Position", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, flexDirection = "row", gap = 3, children = {
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posXField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posYField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posZField } },
                        } },
                    } },
                    Shared.FieldRow("Yaw", self.rotYField),
                    Shared.FieldRow("Scale", self.scaleField),
                },
            },
            Shared.ComponentHeader("⌁", "Interaction"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    self.triggerableToggle,
                    Shared.FieldRow("Trigger ID", self.triggerIdField),
                    self.interactionLabel,
                },
            },
            Shared.ComponentHeader("▣", "Presentation"),
            UI.Panel {
                padding = 8,
                gap = 4,
                children = {
                    self.modelLabel,
                    UI.Label {
                        text = "静物没有体素、PathNode 和机关。自己不会移动，只跟随父级 Transform。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                },
            },
        },
    }
    Shared.BindSlowWheel(self.scroll)
    return self.scroll
end

function StillObjectInspector:Clear()
    self.selectionLabel:SetText("未选择静物")
    self.nameField:SetValue("")
    self.parentDropdown:SetOptions({ { value = "", label = "LevelRoot" } })
    self.parentDropdown.props.value = ""
    self.posXField:SetValue("")
    self.posYField:SetValue("")
    self.posZField:SetValue("")
    self.rotYField:SetValue("")
    self.scaleField:SetValue("")
    self.modelLabel:SetText("占位模型：Box")
    self.triggerableToggle:SetChecked(false)
    self.triggerIdField:SetValue("")
    self.triggerIdField:SetDisabled(true)
end

function StillObjectInspector:Refresh()
    local editor = self.editor
    local object = editor:GetSelectedStillObject()
    if not object then
        self:Clear()
        return
    end
    local parentOptions = { { value = "", label = "LevelRoot" } }
    for _, part in ipairs(editor.levelDocument:GetParts()) do
        if not editor.levelDocument:IsDescendant(part.id, object.id) then
            parentOptions[#parentOptions + 1] = { value = part.id, label = "[Part] " .. part.name }
        end
    end
    for _, still in ipairs(editor.levelDocument:GetStillObjects()) do
        if still.id ~= object.id and not editor.levelDocument:IsDescendant(still.id, object.id) then
            parentOptions[#parentOptions + 1] = { value = still.id, label = "[Still] " .. still.name }
        end
    end
    self.parentDropdown:SetOptions(parentOptions)
    self.parentDropdown.props.value = object.parentId or ""
    self.selectionLabel:SetText(object.name .. "  [" .. object.id .. "]")
    self.nameField:SetValue(object.name)
    local position = object.transform.position
    local rotation = object.transform.rotation
    local scale = object.transform.scale
    self.posXField:SetValue(string.format("%.3f", position.x))
    self.posYField:SetValue(string.format("%.3f", position.y))
    self.posZField:SetValue(string.format("%.3f", position.z))
    self.rotYField:SetValue(string.format("%.1f", rotation.y or 0))
    self.scaleField:SetValue(string.format("%.2f", scale.x))
    self.modelLabel:SetText(object:HasModel() and ("模型：" .. object.modelPath) or "占位模型：Box（尚未导入正式模型）")
    local hasTrigger = object:HasBehavior("triggerable")
    self.triggerableToggle:SetChecked(hasTrigger)
    self.triggerIdField:SetDisabled(not hasTrigger)
    self.triggerIdField:SetValue(hasTrigger and object.behaviors.triggerable.triggerId or "")
end

return StillObjectInspector
