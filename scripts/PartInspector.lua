-- Part 级 Inspector。
-- 负责选中 Part 的 Transform、Pivot、Behavior 和打开局部体素编辑器。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"

local PartInspector = {}
PartInspector.__index = PartInspector

function PartInspector.New(editor)
    local self = setmetatable({}, PartInspector)
    self.editor = editor
    self.scroll = nil
    self.selectionLabel = nil
    self.positionLabel = nil
    self.rotationLabel = nil
    self.scaleLabel = nil
    self.gridQField = nil
    self.gridRField = nil
    self.layerField = nil
    self.yawField = nil
    self.capabilityLabel = nil
    self.modeLabel = nil
    self.nameField = nil
    self.parentDropdown = nil
    self.scaleField = nil
    self.rotatorToggle = nil
    self.moverToggle = nil
    self.moverQToggle = nil
    self.moverRToggle = nil
    self.moverLayerToggle = nil
    self.triggerableToggle = nil
    self.triggerIdField = nil
    self.pivotModeDropdown = nil
    self.pivotQField = nil
    self.pivotRField = nil
    self.pivotSectorField = nil
    self.pivotLayerField = nil
    self.openButton = nil
    return self
end

function PartInspector:Build()
    local editor = self.editor
    self.selectionLabel = UI.Label {
        text = "未选择 Part",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = Shared.TEXT,
    }
    self.positionLabel = UI.Label { text = "", fontSize = 10, fontColor = Shared.MUTED, whiteSpace = "normal" }
    self.rotationLabel = UI.Label { text = "", fontSize = 10, fontColor = Shared.MUTED }
    self.scaleLabel = UI.Label { text = "", fontSize = 10, fontColor = Shared.MUTED }
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
    self.capabilityLabel = UI.Label { text = "", fontSize = 11, fontColor = Shared.MUTED, whiteSpace = "normal" }
    self.modeLabel = UI.Label { text = "", fontSize = 11, fontColor = { 157, 220, 255, 255 }, whiteSpace = "normal" }
    self.nameField = UI.TextField {
        value = "",
        placeholder = "Part 名称",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedPartName(value) end,
    }
    self.parentDropdown = UI.Dropdown {
        options = {},
        value = "",
        placeholder = "父级",
        height = 28,
        fontSize = 11,
        onChange = function(_, value) editor:SetSelectedParent(value == "" and nil or value) end,
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
    self.moverToggle = UI.Checkbox {
        checked = false,
        label = "Mover",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedBehaviorMode("mover", checked) end,
    }
    self.moverQToggle = UI.Checkbox {
        checked = true,
        label = "Q",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedMoverAxis("q", checked) end,
    }
    self.moverRToggle = UI.Checkbox {
        checked = true,
        label = "R",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedMoverAxis("r", checked) end,
    }
    self.moverLayerToggle = UI.Checkbox {
        checked = true,
        label = "Layer",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedMoverAxis("layer", checked) end,
    }
    self.triggerableToggle = UI.Checkbox {
        checked = false,
        label = "Triggerable",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedBehaviorMode("triggerable", checked) end,
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
        onBlur = function(field) editor:SetSelectedPivotCoordinate("hexQ", field:GetValue()) end,
    }
    self.pivotRField = UI.TextField {
        value = "0", placeholder = "R", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("hexR", value) end,
        onBlur = function(field) editor:SetSelectedPivotCoordinate("hexR", field:GetValue()) end,
    }
    self.pivotSectorField = UI.TextField {
        value = "0", placeholder = "Sector", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("sector", value) end,
        onBlur = function(field) editor:SetSelectedPivotCoordinate("sector", field:GetValue()) end,
    }
    self.pivotLayerField = UI.TextField {
        value = "0", placeholder = "Layer", height = 26, fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPivotCoordinate("layer", value) end,
        onBlur = function(field) editor:SetSelectedPivotCoordinate("layer", field:GetValue()) end,
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
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 7, children = {
                        UI.Label { text = "◇", width = 24, fontSize = 20, fontColor = Shared.MUTED },
                        self.selectionLabel,
                    } },
                    Shared.FieldRow("Name", self.nameField),
                    Shared.FieldRow("Parent", self.parentDropdown),
                },
            },
            Shared.ComponentHeader("◈", "Transform"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label { text = "Position", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, flexDirection = "row", gap = 3, children = {
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.gridQField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.gridRField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.layerField } },
                        } },
                    } },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label { text = "Rotation", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                        UI.Panel { width = 80, flexShrink = 0, children = { self.yawField } },
                        UI.Label { text = "六向 0..5", fontSize = 9, fontColor = Shared.MUTED },
                    } },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label { text = "Scale", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                        UI.Panel { width = 80, flexShrink = 0, children = { self.scaleField } },
                        self.scaleLabel,
                    } },
                    self.positionLabel,
                    self.rotationLabel,
                    UI.Label { text = "Pivot", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                    UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotModeDropdown } },
                    UI.Label { text = "Cell  Q / R / Sector / Layer", fontSize = 9, fontColor = Shared.MUTED },
                    UI.Panel { flexDirection = "row", gap = 3, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotQField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotRField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotSectorField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.pivotLayerField } },
                    } },
                    UI.Label {
                        text = "Q / R / Layer 支持 0.5 步进；Sector 仍是 0..5。不必是已有体素。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    UI.Button {
                        text = "Snap to Tri-Prism Grid",
                        height = 25,
                        fontSize = 10,
                        variant = "secondary",
                        onClick = function() editor:SnapSelectedPartToGrid() end,
                    },
                },
            },
            Shared.ComponentHeader("⚙", "Part Behavior"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Panel { flexDirection = "row", gap = 10, children = { self.rotatorToggle, self.moverToggle, self.triggerableToggle } },
                    UI.Panel { flexDirection = "row", gap = 10, children = { self.moverQToggle, self.moverRToggle, self.moverLayerToggle } },
                    Shared.FieldRow("Trigger ID", self.triggerIdField),
                    self.modeLabel,
                    self.capabilityLabel,
                },
            },
            UI.Panel {
                padding = 10,
                gap = 6,
                children = {
                    self.openButton,
                },
            },
        },
    }
    Shared.BindSlowWheel(self.scroll)
    return self.scroll
end

function PartInspector:Clear()
    self.selectionLabel:SetText("未选择 Part")
    self.positionLabel:SetText("World Position：—")
    self.rotationLabel:SetText("Rotation：—")
    self.scaleLabel:SetText("Scale：—")
    self.nameField:SetValue("")
    self.parentDropdown:SetOptions({ { value = "", label = "LevelRoot" } })
    self.parentDropdown.props.value = ""
    self.gridQField:SetValue("")
    self.gridRField:SetValue("")
    self.layerField:SetValue("")
    self.yawField:SetValue("")
    self.scaleField:SetValue("")
    self.capabilityLabel:SetText("—")
    self.modeLabel:SetText("—")
    self.rotatorToggle:SetChecked(false)
    self.moverToggle:SetChecked(false)
    self.moverQToggle:SetChecked(false)
    self.moverRToggle:SetChecked(false)
    self.moverLayerToggle:SetChecked(false)
    self.moverQToggle:SetDisabled(true)
    self.moverRToggle:SetDisabled(true)
    self.moverLayerToggle:SetDisabled(true)
    self.triggerableToggle:SetChecked(false)
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
end

function PartInspector:Refresh()
    local editor = self.editor
    local part = editor:GetSelectedPart()
    if not part then
        self:Clear()
        return
    end

    local parentOptions = { { value = "", label = "LevelRoot" } }
    for _, candidate in ipairs(editor.levelDocument:GetParts()) do
        if candidate.id ~= part.id and not editor.levelDocument:IsDescendant(candidate.id, part.id) then
            parentOptions[#parentOptions + 1] = { value = candidate.id, label = candidate.name }
        end
    end
    self.parentDropdown:SetOptions(parentOptions)
    self.parentDropdown.props.value = part.parentId or ""
    self.nameField:SetValue(part.name)

    local transform = part.transform
    local grid = editor.transformGrid
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
    self.modeLabel:SetText(Shared.ModeText(part))
    self.rotatorToggle:SetChecked(part:HasBehavior("rotator"))
    self.moverToggle:SetChecked(part:HasBehavior("mover"))
    local hasMover = part:HasBehavior("mover")
    local moverAxes = part.behaviors.mover and part.behaviors.mover.axes or {}
    self.moverQToggle:SetDisabled(not hasMover)
    self.moverRToggle:SetDisabled(not hasMover)
    self.moverLayerToggle:SetDisabled(not hasMover)
    self.moverQToggle:SetChecked(hasMover and moverAxes.q == true)
    self.moverRToggle:SetChecked(hasMover and moverAxes.r == true)
    self.moverLayerToggle:SetChecked(hasMover and moverAxes.layer == true)
    self.triggerableToggle:SetChecked(part:HasBehavior("triggerable"))
    self.triggerIdField:SetValue(part.behaviors.triggerable and part.behaviors.triggerable.triggerId or "")
    local pivotCell = part:GetPivotCell()
    local usesCellPivot = part:GetPivotMode() == "cell_center"
    self.pivotModeDropdown:SetDisabled(false)
    self.pivotModeDropdown.props.value = part:GetPivotMode()
    self.pivotQField:SetValue(pivotCell and string.format("%.1f", pivotCell.hexQ) or "0.0")
    self.pivotQField:SetDisabled(not usesCellPivot)
    self.pivotRField:SetValue(pivotCell and string.format("%.1f", pivotCell.hexR) or "0.0")
    self.pivotRField:SetDisabled(not usesCellPivot)
    self.pivotSectorField:SetValue(pivotCell and tostring(pivotCell.sector) or "0")
    self.pivotSectorField:SetDisabled(not usesCellPivot)
    self.pivotLayerField:SetValue(pivotCell and string.format("%.1f", pivotCell.layer) or "0.0")
    self.pivotLayerField:SetDisabled(not usesCellPivot)
    self.openButton:SetDisabled(false)
end

return PartInspector
