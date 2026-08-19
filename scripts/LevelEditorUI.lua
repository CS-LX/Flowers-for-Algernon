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
    self.positionLabel = UI.Label { text = "", fontSize = 10, fontColor = MUTED, whiteSpace = "normal" }
    self.rotationLabel = UI.Label { text = "", fontSize = 10, fontColor = MUTED }
    self.scaleLabel = UI.Label { text = "", fontSize = 10, fontColor = MUTED }
    self.gridQField = UI.TextField {
        value = "0",
        placeholder = "Q",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedGridCoordinate("hexQ", value) end,
    }
    self.gridRField = UI.TextField {
        value = "0",
        placeholder = "R",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedGridCoordinate("hexR", value) end,
    }
    self.layerField = UI.TextField {
        value = "0",
        placeholder = "Layer",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedGridCoordinate("layer", value) end,
    }
    self.yawField = UI.TextField {
        value = "0",
        placeholder = "Yaw 0..5",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedYawSteps(value) end,
    }
    self.capabilityLabel = UI.Label { text = "", fontSize = 11, fontColor = MUTED, whiteSpace = "normal" }
    self.modeLabel = UI.Label { text = "", fontSize = 11, fontColor = { 157, 220, 255, 255 }, whiteSpace = "normal" }
    self.cameraLabel = UI.Label { text = "", fontSize = 10, fontColor = { 173, 214, 255, 255 } }

    self.partList = UI.Panel {
        gap = 5,
        flexGrow = 1,
        flexShrink = 1,
    }
    self.createButton = UI.Button {
        text = "+ 新建 Part",
        height = 30,
        fontSize = 11,
        variant = "primary",
        onClick = function() editor:CreateEmptyPart() end,
    }
    self.duplicateButton = UI.Button {
        text = "复制",
        flexGrow = 1,
        height = 28,
        fontSize = 10,
        variant = "secondary",
        onClick = function() editor:DuplicateSelectedPart() end,
    }
    self.deleteButton = UI.Button {
        text = "删除",
        flexGrow = 1,
        height = 28,
        fontSize = 10,
        variant = "danger",
        onClick = function()
            local part = editor:GetSelectedPart()
            if not part then return end
            UI.Modal.Confirm({
                title = "从关卡移除 Part",
                message = "确定移除“" .. part.name .. "”吗？局部体素 JSON 会保留，不会物理删除。",
                confirmText = "移除",
                cancelText = "取消",
                onConfirm = function() editor:DeleteSelectedPart() end,
            })
        end,
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
    self.saveButton = UI.Button {
        text = "保存关卡",
        height = 30,
        fontSize = 11,
        variant = "success",
        onClick = function()
            editor:SaveLevel()
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
                    self.createButton,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.duplicateButton,
                        self.deleteButton,
                    } },
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
                    UI.Label { text = "Grid Position  (0.5 step, hex snap)", fontSize = 9, fontColor = { 157, 220, 255, 255 } },
                    UI.Panel { flexDirection = "row", gap = 5, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, gap = 2, children = { UI.Label { text = "Q", fontSize = 9, fontColor = MUTED }, self.gridQField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, gap = 2, children = { UI.Label { text = "R", fontSize = 9, fontColor = MUTED }, self.gridRField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, gap = 2, children = { UI.Label { text = "Layer", fontSize = 9, fontColor = MUTED }, self.layerField } },
                    } },
                    self.positionLabel,
                    UI.Button {
                        text = "Snap Current to Tri-Prism Grid",
                        height = 26,
                        fontSize = 10,
                        variant = "secondary",
                        onClick = function() editor:SnapSelectedPartToGrid() end,
                    },
                    UI.Label { text = "Rotation  (6-way snap)", fontSize = 9, fontColor = { 157, 220, 255, 255 } },
                    UI.Panel { flexDirection = "row", gap = 5, alignItems = "flex-end", children = {
                        UI.Panel { width = 78, gap = 2, children = { UI.Label { text = "Yaw Step", fontSize = 9, fontColor = MUTED }, self.yawField } },
                        UI.Label { text = "0..5  =  0°..300°", flexGrow = 1, flexShrink = 1, fontSize = 9, fontColor = MUTED, whiteSpace = "normal" },
                    } },
                    self.rotationLabel,
                    self.scaleLabel,
                    UI.Label { text = "Transform Capabilities", fontSize = 10, fontColor = MUTED },
                    self.capabilityLabel,
                    UI.Label { text = "Behavior Modes", fontSize = 10, fontColor = MUTED },
                    self.modeLabel,
                    UI.Divider { thickness = 1, color = BORDER, spacing = 1 },
                    UI.Label { text = "Editor Preview Camera", fontSize = 10, fontColor = MUTED },
                    self.cameraLabel,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "投影", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleEditorProjection() end },
                        UI.Button { text = "聚焦", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:FocusSelectedPart() end },
                        UI.Button { text = "重置", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:ResetEditorCamera(); editor:RefreshLevelUI("已恢复固定 30° 正交编辑基准") end },
                    } },
                    UI.Label { text = "RMB 旋转 · MMB 平移 · Wheel 缩放", fontSize = 9, fontColor = MUTED },
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    self.saveButton,
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
        self.positionLabel:SetText("World Position：—")
        self.rotationLabel:SetText("Rotation：—")
        self.scaleLabel:SetText("Scale：—")
        self.gridQField:SetValue("")
        self.gridRField:SetValue("")
        self.layerField:SetValue("")
        self.yawField:SetValue("")
        self.capabilityLabel:SetText("—")
        self.modeLabel:SetText("—")
        self.openButton:SetDisabled(true)
        self.saveButton:SetDisabled(true)
        self.duplicateButton:SetDisabled(true)
        self.deleteButton:SetDisabled(true)
        return
    end

    local transform = part.transform
    local grid = self.editor.transformGrid
    self.gridQField:SetValue(tostring(grid.hexQ))
    self.gridRField:SetValue(tostring(grid.hexR))
    self.layerField:SetValue(tostring(grid.layer))
    self.yawField:SetValue(tostring(transform.rotation.yawSteps))
    self.selectionLabel:SetText(part.name .. "  [" .. part.id .. "]")
    self.positionLabel:SetText(string.format(
        "World Position  X %.3f  Y %.3f  Z %.3f",
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
    local editorCamera = self.editor.editorCamera
    self.cameraLabel:SetText(string.format(
        "%s  Yaw %.0f°  Pitch %.0f°  Zoom %.1f",
        editorCamera.projection == "orthographic" and "正交" or "透视",
        editorCamera.yaw,
        editorCamera.pitch,
        editorCamera.projection == "orthographic" and editorCamera.orthoSize or editorCamera.distance
    ))
    self.openButton:SetDisabled(false)
    self.saveButton:SetDisabled(false)
    self.duplicateButton:SetDisabled(false)
    self.deleteButton:SetDisabled(false)
end

function LevelEditorUI:SetCameraState(camera)
    self.cameraLabel:SetText(string.format(
        "%s  Yaw %.0f°  Pitch %.0f°  Zoom %.1f",
        camera.projection == "orthographic" and "正交" or "透视",
        camera.yaw,
        camera.pitch,
        camera.projection == "orthographic" and camera.orthoSize or camera.distance
    ))
end

function LevelEditorUI:SetStatus(text)
    self.statusLabel:SetText(text)
end

function LevelEditorUI:Destroy()
    self.root = nil
    UI.Shutdown()
end

return LevelEditorUI
