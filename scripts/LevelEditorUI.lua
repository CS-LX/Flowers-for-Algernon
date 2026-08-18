-- Level View 的 Yoga UI。
-- 只渲染 Object Tree 与 Inspector，并把用户操作转发给 LevelEditor。

local UI = require("urhox-libs/UI")

local LevelEditorUI = {}
LevelEditorUI.__index = LevelEditorUI

local PANEL = { 21, 27, 38, 244 }
local PANEL_LIGHT = { 32, 41, 56, 248 }
local BORDER = { 92, 112, 140, 180 }
local TEXT = { 231, 238, 248, 255 }
local MUTED = { 145, 160, 184, 255 }
local SELECTED = { 41, 101, 169, 255 }

local function ModeText(part)
    if #part.behaviorModes == 0 then
        return "无运行时行为"
    end
    return table.concat(part.behaviorModes, " + ")
end

function LevelEditorUI.New(editor)
    local self = setmetatable({}, LevelEditorUI)
    self.editor = editor
    self.root = nil
    self.partButtons = {}
    return self
end

function LevelEditorUI:Build()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    local editor = self.editor
    self.titleLabel = UI.Label {
        text = "LEVEL OBJECT TREE",
        fontSize = 17,
        fontWeight = "bold",
        fontColor = TEXT,
    }
    self.statusLabel = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = MUTED,
    }
    self.selectionLabel = UI.Label {
        text = "未选择 Part",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = TEXT,
    }
    self.positionLabel = UI.Label { text = "", fontSize = 11, fontColor = MUTED }
    self.rotationLabel = UI.Label { text = "", fontSize = 11, fontColor = MUTED }
    self.scaleLabel = UI.Label { text = "", fontSize = 11, fontColor = MUTED }
    self.capabilityLabel = UI.Label { text = "", fontSize = 11, fontColor = MUTED, whiteSpace = "normal" }
    self.modeLabel = UI.Label { text = "", fontSize = 11, fontColor = { 157, 220, 255, 255 }, whiteSpace = "normal" }

    self.partList = UI.Panel {
        gap = 5,
        flexGrow = 1,
        flexShrink = 1,
    }

    self.openButton = UI.Button {
        text = "打开 Part 编辑器",
        height = 32,
        fontSize = 12,
        variant = "primary",
        disabled = true,
        onClick = function()
            editor:OpenSelectedPart()
        end,
    }
    self.rotateButton = UI.Button {
        text = "旋转 +60°",
        height = 30,
        fontSize = 11,
        variant = "secondary",
        disabled = true,
        onClick = function()
            editor:RotateSelectedPart()
        end,
    }

    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8, right = 8, height = 40,
                paddingHorizontal = 12, flexDirection = "row", alignItems = "center", gap = 16,
                backgroundColor = PANEL, borderColor = BORDER, borderWidth = 1, borderRadius = 6,
                children = {
                    self.titleLabel,
                    UI.Label { text = "关卡总装 / 固定 30° 正交视图", fontSize = 11, fontColor = MUTED },
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    UI.Label { text = "F9：UI 检查器", fontSize = 10, fontColor = MUTED },
                },
            },
            UI.Panel {
                position = "absolute", top = 56, left = 8, width = 210, bottom = 44,
                padding = 10, gap = 8,
                backgroundColor = PANEL, borderColor = BORDER, borderWidth = 1, borderRadius = 6,
                children = {
                    UI.Label { text = "OBJECT TREE", fontSize = 11, fontWeight = "bold", fontColor = TEXT },
                    UI.Label { text = "LevelRoot", fontSize = 12, fontWeight = "bold", fontColor = { 180, 201, 226, 255 } },
                    self.partList,
                    UI.Divider { thickness = 1, color = BORDER, spacing = 2 },
                    UI.Label { text = "当前为最小总装闭环：选择、查看、打开 Part。", fontSize = 10, fontColor = MUTED, whiteSpace = "normal" },
                },
            },
            UI.Panel {
                position = "absolute", top = 56, right = 8, width = 254, bottom = 44,
                padding = 11, gap = 8,
                backgroundColor = PANEL, borderColor = BORDER, borderWidth = 1, borderRadius = 6,
                children = {
                    UI.Label { text = "PART INSPECTOR", fontSize = 11, fontWeight = "bold", fontColor = TEXT },
                    self.selectionLabel,
                    UI.Divider { thickness = 1, color = BORDER, spacing = 1 },
                    UI.Label { text = "Transform", fontSize = 10, fontColor = MUTED },
                    self.positionLabel,
                    self.rotationLabel,
                    self.scaleLabel,
                    UI.Label { text = "Transform Capabilities", fontSize = 10, fontColor = MUTED },
                    self.capabilityLabel,
                    UI.Label { text = "Behavior Modes", fontSize = 10, fontColor = MUTED },
                    self.modeLabel,
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    self.rotateButton,
                    self.openButton,
                },
            },
            UI.Panel {
                position = "absolute", left = 8, right = 8, bottom = 8, height = 28,
                paddingHorizontal = 10, flexDirection = "row", alignItems = "center",
                backgroundColor = PANEL, borderColor = BORDER, borderWidth = 1, borderRadius = 5,
                children = {
                    self.statusLabel,
                    UI.Panel { flexGrow = 1 },
                    UI.Label { text = "选择 Part 查看属性；打开后进入局部三棱柱体素编辑。", fontSize = 10, fontColor = MUTED },
                },
            },
        },
    }
    UI.SetRoot(self.root, true)
    self:Refresh()
end

function LevelEditorUI:Refresh()
    self.partList:ClearChildren()
    self.partButtons = {}
    local selectedId = self.editor.selectedPartId
    for _, part in ipairs(self.editor.levelDocument:GetParts()) do
        local button = UI.Button {
            text = "▸ " .. part.name,
            height = 31,
            fontSize = 12,
            variant = "secondary",
            backgroundColor = part.id == selectedId and SELECTED or PANEL_LIGHT,
            transition = "backgroundColor 0.18s easeOut",
            onClick = function()
                self.editor:SelectPart(part.id)
            end,
        }
        self.partButtons[part.id] = button
        self.partList:AddChild(button)
    end

    local part = self.editor:GetSelectedPart()
    if not part then
        self.selectionLabel:SetText("未选择 Part")
        self.positionLabel:SetText("Position：—")
        self.rotationLabel:SetText("Rotation：—")
        self.scaleLabel:SetText("Scale：—")
        self.capabilityLabel:SetText("—")
        self.modeLabel:SetText("—")
        self.openButton:SetDisabled(true)
        self.rotateButton:SetDisabled(true)
        return
    end

    local transform = part.transform
    self.selectionLabel:SetText(part.name .. "  [" .. part.id .. "]")
    self.positionLabel:SetText(string.format(
        "Position：X %.2f  Y %.2f  Z %.2f",
        transform.position.x, transform.position.y, transform.position.z
    ))
    self.rotationLabel:SetText(string.format(
        "Rotation：Yaw %d (%d°)  Pitch %d  Roll %d",
        transform.rotation.yawSteps,
        transform.rotation.yawSteps * 60,
        transform.rotation.pitchSteps,
        transform.rotation.rollSteps
    ))
    self.scaleLabel:SetText(string.format(
        "Scale：%.2f, %.2f, %.2f%s",
        transform.scale.x,
        transform.scale.y,
        transform.scale.z,
        part:CanTransform("scale") and "" or "  [锁定]"
    ))
    self.capabilityLabel:SetText(string.format(
        "move=%s  rotate=%s  scale=%s",
        tostring(part:CanTransform("move")),
        tostring(part:CanTransform("rotate")),
        tostring(part:CanTransform("scale"))
    ))
    self.modeLabel:SetText(ModeText(part))
    self.openButton:SetDisabled(false)
    self.rotateButton:SetDisabled(not part:HasBehavior("rotator"))
end

function LevelEditorUI:SetStatus(text)
    self.statusLabel:SetText(text)
end

function LevelEditorUI:Destroy()
    self.root = nil
    UI.Shutdown()
end

return LevelEditorUI
