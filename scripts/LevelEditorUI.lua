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
local COMPONENT_HEADER = { 29, 36, 50, 255 }
local COMPONENT_ACCENT = { 78, 132, 194, 255 }

local function ModeText(part)
    if #part.behaviorModes == 0 then
        return "无运行时行为"
    end
    return table.concat(part.behaviorModes, " + ")
end

local function InspectorComponentHeader(icon, title)
    return UI.Panel {
        height = 29,
        paddingHorizontal = 8,
        flexDirection = "row",
        alignItems = "center",
        gap = 7,
        backgroundColor = COMPONENT_HEADER,
        borderTopWidth = 1,
        borderBottomWidth = 1,
        borderTopColor = BORDER,
        borderBottomColor = BORDER,
        children = {
            UI.Label { text = "▾", width = 10, fontSize = 10, fontColor = MUTED },
            UI.Label { text = icon, width = 16, fontSize = 12, fontColor = COMPONENT_ACCENT },
            UI.Label { text = title, flexGrow = 1, fontSize = 11, fontWeight = "bold", fontColor = TEXT },
            UI.Label { text = "?  ⋮", fontSize = 10, fontColor = MUTED },
        },
    }
end

local function InspectorFieldRow(label, content)
    return UI.Panel {
        minHeight = 28,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label { text = label, width = 62, flexShrink = 0, fontSize = 10, fontColor = MUTED },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                minWidth = 0,
                children = { content },
            },
        },
    }
end

local function IsPointerInsideWidget(widget)
    local scale = UI.GetScale()
    local mouse = input:GetMousePosition()
    local x = mouse.x / scale
    local y = mouse.y / scale
    local layout = widget:GetAbsoluteLayoutForHitTest()
    return x >= layout.x and x <= layout.x + layout.w
        and y >= layout.y and y <= layout.y + layout.h
end

function LevelEditorUI.New(editor)
    local self = setmetatable({}, LevelEditorUI)
    self.editor = editor
    self.root = nil
    self.pathNodeLabel = nil
    self.pathNodeDropdown = nil
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

    self.tree = UI.Tree {
        nodes = {},
        size = "sm",
        height = "100%",
        flexGrow = 1,
        flexShrink = 1,
        showLines = true,
        defaultExpandAll = false,
        selectedBgColor = COMPONENT_ACCENT,
        onSelect = function(_, _, node)
            if node and node.id then
                editor:SelectPart(node.id)
            end
        end,
    }
    self.nameField = UI.TextField {
        value = "",
        placeholder = "Part 名称",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedPartName(value) end,
    }
    self.parentDropdown = UI.Dropdown {
        options = {},
        value = "__root__",
        placeholder = "父级",
        height = 28,
        fontSize = 11,
        onChange = function(_, value) editor:SetSelectedParent(value == "__root__" and nil or value) end,
    }
    self.scaleField = UI.TextField {
        value = "1.0",
        placeholder = "Scale",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedScale(value) end,
    }
    self.rotatorToggle = UI.Checkbox {
        checked = false,
        label = "Rotator",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedBehaviorMode("rotator", checked) end,
    }
    self.triggerableToggle = UI.Checkbox {
        checked = false,
        label = "Triggerable",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedBehaviorMode("triggerable", checked) end,
    }
    self.rotatorDurationField = UI.TextField {
        value = "0.45",
        placeholder = "Duration",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedRotatorDuration(value) end,
    }
    self.triggerIdField = UI.TextField {
        value = "",
        placeholder = "Trigger ID",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedTriggerId(value) end,
    }
    self.pivotModeDropdown = UI.Dropdown {
        options = {
            { value = "origin", label = "Origin" },
            { value = "cell_center", label = "Cell Center" },
        },
        value = "origin",
        height = 26,
        fontSize = 10,
        onChange = function(_, value) editor:SetSelectedPivotMode(value) end,
    }
    self.pivotQField = UI.TextField {
        value = "0", placeholder = "Q", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("hexQ", value) end,
        onBlur = function(self) editor:SetSelectedPivotCoordinate("hexQ", self:GetValue()) end,
    }
    self.pivotRField = UI.TextField {
        value = "0", placeholder = "R", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("hexR", value) end,
        onBlur = function(self) editor:SetSelectedPivotCoordinate("hexR", self:GetValue()) end,
    }
    self.pivotSectorField = UI.TextField {
        value = "0", placeholder = "Sector", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("sector", value) end,
        onBlur = function(self) editor:SetSelectedPivotCoordinate("sector", self:GetValue()) end,
    }
    self.pivotLayerField = UI.TextField {
        value = "0", placeholder = "Layer", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("layer", value) end,
        onBlur = function(self) editor:SetSelectedPivotCoordinate("layer", self:GetValue()) end,
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
    self.previewButton = UI.Button {
        text = "游戏预览",
        height = 30,
        fontSize = 11,
        variant = "primary",
        onClick = function()
            editor:StartGamePreview()
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
                    self.tree,
                    self.createButton,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.duplicateButton,
                        self.deleteButton,
                    } },
                    UI.Divider { thickness = 1, color = BORDER, spacing = 2 },
                    UI.Label { text = "当前为最小总装闭环：选择、查看、打开 Part。", fontSize = 10, fontColor = MUTED, whiteSpace = "normal" },
                },
            },
            UI.ScrollView {
                id = "inspectorScroll",
                position = "absolute", top = 56, right = 8, width = 300, bottom = 44,
                padding = 0,
                gap = 0,
                flexBasis = 0,
                scrollY = true,
                scrollX = false,
                showScrollbar = true,
                scrollbarInteractive = true,
                bounces = false,
                backgroundColor = PANEL, borderColor = BORDER, borderWidth = 1, borderRadius = 3,
                children = {
                    UI.Panel {
                        padding = 8,
                        gap = 5,
                        borderBottomWidth = 1,
                        borderBottomColor = BORDER,
                        children = {
                            UI.Panel { flexDirection = "row", alignItems = "center", gap = 7, children = {
                                UI.Label { text = "◇", width = 24, fontSize = 20, fontColor = MUTED },
                                UI.Checkbox { checked = true, size = 15, height = 24, onChange = function() end },
                                self.nameField,
                            } },
                            InspectorFieldRow("Parent", self.parentDropdown),
                        },
                    },
                    InspectorComponentHeader("◈", "Transform"),
                    UI.Panel {
                        padding = 8,
                        gap = 4,
                        borderBottomWidth = 1,
                        borderBottomColor = BORDER,
                        children = {
                            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                                UI.Label { text = "Position", width = 62, fontSize = 10, fontColor = MUTED },
                                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, flexDirection = "row", gap = 3, children = {
                                    UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.gridQField } },
                                    UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.gridRField } },
                                    UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.layerField } },
                                } },
                            } },
                            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                                UI.Label { text = "Rotation", width = 62, fontSize = 10, fontColor = MUTED },
                                UI.Panel { width = 80, flexShrink = 0, children = { self.yawField } },
                                UI.Label { text = "六向 0..5", fontSize = 9, fontColor = MUTED },
                            } },
                            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                                UI.Label { text = "Scale", width = 62, fontSize = 10, fontColor = MUTED },
                                UI.Panel { width = 80, flexShrink = 0, children = { self.scaleField } },
                                self.scaleLabel,
                            } },
                            self.positionLabel,
                            self.rotationLabel,
                            UI.Label { text = "Pivot", width = 62, fontSize = 10, fontColor = MUTED },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotModeDropdown } },
                            UI.Label { text = "Cell", fontSize = 9, fontColor = MUTED },
                            UI.Panel { flexDirection = "row", gap = 3, children = {
                                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotQField } },
                                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotRField } },
                                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotSectorField } },
                                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotLayerField } },
                            } },
                            UI.Button {
                                text = "Snap to Tri-Prism Grid",
                                height = 25,
                                fontSize = 10,
                                variant = "secondary",
                                onClick = function() editor:SnapSelectedPartToGrid() end,
                            },
                        },
                    },
                    InspectorComponentHeader("⚙", "Part Behavior"),
                    UI.Panel {
                        padding = 8,
                        gap = 4,
                        borderBottomWidth = 1,
                        borderBottomColor = BORDER,
                        children = {
                            UI.Panel { flexDirection = "row", gap = 10, children = { self.rotatorToggle, self.triggerableToggle } },
                            InspectorFieldRow("Duration", self.rotatorDurationField),
                            InspectorFieldRow("Trigger ID", self.triggerIdField),
                            self.modeLabel,
                            self.capabilityLabel,
                        },
                    },
                    InspectorComponentHeader("◉", "Editor Preview Camera"),
                    UI.Panel {
                        padding = 8,
                        gap = 5,
                        borderBottomWidth = 1,
                        borderBottomColor = BORDER,
                        children = {
                            self.cameraLabel,
                            UI.Panel { flexDirection = "row", gap = 4, children = {
                                UI.Button { text = "投影", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleEditorProjection() end },
                                UI.Button { text = "聚焦", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:FocusSelectedPart() end },
                                UI.Button { text = "重置", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:ResetEditorCamera(); editor:RefreshLevelUI("已恢复固定 30° 正交编辑基准") end },
                            } },
                            UI.Label { text = "RMB 旋转 · MMB 平移 · Wheel 缩放", fontSize = 9, fontColor = MUTED },
                        },
                    },
                    UI.Panel {
                        padding = 10,
                        gap = 6,
                        children = {
                            self.openButton,
                            self.previewButton,
                            self.saveButton,
                        },
                    },
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
    self.inspectorScroll = self.root:FindById("inspectorScroll")
    self.inspectorScroll.OnWheel = function(_, dx, dy)
        if not IsPointerInsideWidget(self.inspectorScroll) then
            return false
        end
        self.inspectorScroll:ScrollBy(-dx * 40, -dy * 40)
        return true
    end
    self:Refresh()
end

function LevelEditorUI:Refresh()
    self.tree:SetNodes(self.editor.levelDocument:GetTreeNodes())
    self.tree:ExpandAll()

    local part = self.editor:GetSelectedPart()
    if not part then
        self.selectionLabel:SetText("未选择 Part")
        self.positionLabel:SetText("World Position：—")
        self.rotationLabel:SetText("Rotation：—")
        self.scaleLabel:SetText("Scale：—")
        self.nameField:SetValue("")
        self.parentDropdown:SetOptions({ { value = "__root__", label = "LevelRoot" } })
        self.parentDropdown:SetValue("__root__")
        self.gridQField:SetValue("")
        self.gridRField:SetValue("")
        self.layerField:SetValue("")
        self.yawField:SetValue("")
        self.scaleField:SetValue("")
        self.capabilityLabel:SetText("—")
        self.modeLabel:SetText("—")
        self.rotatorToggle:SetChecked(false)
        self.triggerableToggle:SetChecked(false)
        self.rotatorDurationField:SetValue("")
        self.triggerIdField:SetValue("")
        self.pivotModeDropdown.props.value = "origin"
        self.pivotModeDropdown:SetDisabled(true)
        self.pivotQField:SetValue("")
        self.pivotQField:SetDisabled(true)
        self.pivotRField:SetValue("")
        self.pivotRField:SetDisabled(true)
        self.pivotSectorField:SetValue("")
        self.pivotSectorField:SetDisabled(true)
        self.pivotLayerField:SetValue("")
        self.pivotLayerField:SetDisabled(true)
        self.openButton:SetDisabled(true)
        self.previewButton:SetDisabled(true)
        self.saveButton:SetDisabled(true)
        self.duplicateButton:SetDisabled(true)
        self.deleteButton:SetDisabled(true)
        return
    end

    local parentOptions = { { value = "__root__", label = "LevelRoot" } }
    for _, candidate in ipairs(self.editor.levelDocument:GetParts()) do
        if candidate.id ~= part.id and not self.editor.levelDocument:IsDescendant(candidate.id, part.id) then
            parentOptions[#parentOptions + 1] = { value = candidate.id, label = candidate.name }
        end
    end
    self.parentDropdown:SetOptions(parentOptions)
    self.parentDropdown:SetValue(part.parentId or "__root__")
    self.nameField:SetValue(part.name)

    local transform = part.transform
    local grid = self.editor.transformGrid
    self.gridQField:SetValue(tostring(grid.hexQ))
    self.gridRField:SetValue(tostring(grid.hexR))
    self.layerField:SetValue(tostring(grid.layer))
    self.yawField:SetValue(tostring(transform.rotation.yawSteps))
    self.scaleField:SetValue(string.format("%.2f", transform.scale.x))
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
    self.rotatorToggle:SetChecked(part:HasBehavior("rotator"))
    self.triggerableToggle:SetChecked(part:HasBehavior("triggerable"))
    self.rotatorDurationField:SetValue(part.behaviors.rotator and tostring(part.behaviors.rotator.duration) or "")
    self.triggerIdField:SetValue(part.behaviors.triggerable and part.behaviors.triggerable.triggerId or "")
    local pivotCell = part:GetPivotCell()
    local usesCellPivot = part:GetPivotMode() == "cell_center"
    self.pivotModeDropdown:SetDisabled(false)
    self.pivotModeDropdown.props.value = part:GetPivotMode()
    self.pivotQField:SetValue(pivotCell and tostring(pivotCell.hexQ) or "0")
    self.pivotQField:SetDisabled(not usesCellPivot)
    self.pivotRField:SetValue(pivotCell and tostring(pivotCell.hexR) or "0")
    self.pivotRField:SetDisabled(not usesCellPivot)
    self.pivotSectorField:SetValue(pivotCell and tostring(pivotCell.sector) or "0")
    self.pivotSectorField:SetDisabled(not usesCellPivot)
    self.pivotLayerField:SetValue(pivotCell and tostring(pivotCell.layer) or "0")
    self.pivotLayerField:SetDisabled(not usesCellPivot)
    local editorCamera = self.editor.editorCamera
    self.cameraLabel:SetText(string.format(
        "%s  Yaw %.0f°  Pitch %.0f°  Zoom %.1f",
        editorCamera.projection == "orthographic" and "正交" or "透视",
        editorCamera.yaw,
        editorCamera.pitch,
        editorCamera.projection == "orthographic" and editorCamera.orthoSize or editorCamera.distance
    ))
    self.openButton:SetDisabled(false)
    self.previewButton:SetDisabled(false)
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
