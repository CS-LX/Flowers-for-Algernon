-- Part 级 Inspector。
-- 负责选中 Part 的 Transform、Pivot、Behavior 和打开局部体素编辑器。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"
local LookApplier = require "LookApplier"

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
    self.moverMinQField = nil
    self.moverMaxQField = nil
    self.moverMinRField = nil
    self.moverMaxRField = nil
    self.moverMinLayerField = nil
    self.moverMaxLayerField = nil
    self.moverQLimitRow = nil
    self.moverRLimitRow = nil
    self.moverLayerLimitRow = nil
    self.triggerableToggle = nil
    self.triggerIdField = nil
    self.pivotModeDropdown = nil
    self.pivotQField = nil
    self.pivotRField = nil
    self.pivotSectorField = nil
    self.pivotLayerField = nil
    self.openButton = nil
    self.lookShaderDropdown = nil
    self.lookNegPicker = nil
    self.lookMidPicker = nil
    self.lookPosPicker = nil
    self.lookAxisXField = nil
    self.lookAxisYField = nil
    self.lookAxisZField = nil
    self.lookFogPanel = nil
    self.lookFogColorPicker = nil
    self.lookFogUpXField = nil
    self.lookFogUpYField = nil
    self.lookFogUpZField = nil
    self.lookFogHeightAField = nil
    self.lookFogHeightBField = nil
    self.lookAOToggle = nil
    self.lookAOColorPicker = nil
    self.lookAOSmoothField = nil
    self.lookAOBlendField = nil
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
    local function LimitField(placeholder, name)
        return UI.TextField {
            value = "",
            placeholder = placeholder,
            height = 26,
            fontSize = 10,
            onSubmit = function(_, value) editor:SetSelectedMoverLimit(name, value) end,
            onBlur = function(field) editor:SetSelectedMoverLimit(name, field:GetValue()) end,
        }
    end
    self.moverMinQField = LimitField("MinQ 留空不限", "minQ")
    self.moverMaxQField = LimitField("MaxQ 留空不限", "maxQ")
    self.moverMinRField = LimitField("MinR 留空不限", "minR")
    self.moverMaxRField = LimitField("MaxR 留空不限", "maxR")
    self.moverMinLayerField = LimitField("MinLayer 留空不限", "minLayer")
    self.moverMaxLayerField = LimitField("MaxLayer 留空不限", "maxLayer")
    self.moverQLimitRow = UI.Panel {
        flexDirection = "row",
        gap = 6,
        children = {
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMinQField } },
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMaxQField } },
        },
    }
    self.moverRLimitRow = UI.Panel {
        flexDirection = "row",
        gap = 6,
        children = {
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMinRField } },
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMaxRField } },
        },
    }
    self.moverLayerLimitRow = UI.Panel {
        flexDirection = "row",
        gap = 6,
        children = {
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMinLayerField } },
            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.moverMaxLayerField } },
        },
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
    self.lookShaderDropdown = UI.Dropdown {
        options = LookApplier.SHADER_OPTIONS,
        value = LookApplier.SHADER_TRI_PRISM_LOOK,
        height = 26,
        fontSize = 10,
        onChange = function(_, value) editor:SetSelectedPartLookShader(value) end,
    }
    self.lookNegPicker = Shared.ColorField {
        color = "#8F8478",
        onClose = function(picker)
            editor:SetSelectedPartLookColor("colorNeg", picker:GetHex())
        end,
    }
    self.lookMidPicker = Shared.ColorField {
        color = "#C4B6A6",
        onClose = function(picker)
            editor:SetSelectedPartLookColor("colorMid", picker:GetHex())
        end,
    }
    self.lookPosPicker = Shared.ColorField {
        color = "#F1E6D5",
        onClose = function(picker)
            editor:SetSelectedPartLookColor("colorPos", picker:GetHex())
        end,
    }
    self.lookAxisXField = UI.TextField {
        value = "0.35",
        placeholder = "X",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookAxis("x", value) end,
        onBlur = function(field) editor:SetSelectedPartLookAxis("x", field:GetValue()) end,
    }
    self.lookAxisYField = UI.TextField {
        value = "1.0",
        placeholder = "Y",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookAxis("y", value) end,
        onBlur = function(field) editor:SetSelectedPartLookAxis("y", field:GetValue()) end,
    }
    self.lookAxisZField = UI.TextField {
        value = "0.25",
        placeholder = "Z",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookAxis("z", value) end,
        onBlur = function(field) editor:SetSelectedPartLookAxis("z", field:GetValue()) end,
    }
    self.lookFogColorPicker = Shared.ColorField {
        color = "#C9C2B4",
        onClose = function(picker)
            editor:SetSelectedPartLookFogColor(picker:GetHex())
        end,
    }
    self.lookFogUpXField = UI.TextField {
        value = "0.00",
        placeholder = "X",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookFogUp("x", value) end,
        onBlur = function(field) editor:SetSelectedPartLookFogUp("x", field:GetValue()) end,
    }
    self.lookFogUpYField = UI.TextField {
        value = "1.00",
        placeholder = "Y",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookFogUp("y", value) end,
        onBlur = function(field) editor:SetSelectedPartLookFogUp("y", field:GetValue()) end,
    }
    self.lookFogUpZField = UI.TextField {
        value = "0.00",
        placeholder = "Z",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookFogUp("z", value) end,
        onBlur = function(field) editor:SetSelectedPartLookFogUp("z", field:GetValue()) end,
    }
    self.lookFogHeightAField = UI.TextField {
        value = "4.00",
        placeholder = "A",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookFogNumber("fogHeightA", value) end,
        onBlur = function(field) editor:SetSelectedPartLookFogNumber("fogHeightA", field:GetValue()) end,
    }
    self.lookFogHeightBField = UI.TextField {
        value = "0.00",
        placeholder = "B",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookFogNumber("fogHeightB", value) end,
        onBlur = function(field) editor:SetSelectedPartLookFogNumber("fogHeightB", field:GetValue()) end,
    }
    self.lookAOToggle = UI.Checkbox {
        checked = true,
        label = "AO",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedPartLookAOEnabled(checked) end,
    }
    self.lookAOColorPicker = Shared.ColorField {
        color = "#2A1F1A",
        onClose = function(picker)
            editor:SetSelectedPartLookAOColor(picker:GetHex())
        end,
    }
    self.lookAOSmoothField = UI.TextField {
        value = "0.18",
        placeholder = "Smooth",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookAOSmooth(value) end,
        onBlur = function(field) editor:SetSelectedPartLookAOSmooth(field:GetValue()) end,
    }
    self.lookAOBlendField = UI.TextField {
        value = "1.00",
        placeholder = "Blend",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookAOBlend(value) end,
        onBlur = function(field) editor:SetSelectedPartLookAOBlend(field:GetValue()) end,
    }
    self.lookEmissionColorPicker = Shared.ColorField {
        color = "#FFF4D2",
        onClose = function(picker)
            editor:SetSelectedPartLookEmissionColor(picker:GetHex())
        end,
    }
    self.lookEmissionStrengthField = UI.TextField {
        value = "0.25",
        placeholder = "Strength",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedPartLookEmissionStrength(value) end,
        onBlur = function(field) editor:SetSelectedPartLookEmissionStrength(field:GetValue()) end,
    }
    self.lookFogPanel = UI.Panel {
        gap = 4,
        children = {
            UI.Label {
                text = "高度雾：沿 fog_up 轴向，从 Height A 过渡到 Height B。B 低于 A 时雾在低处更浓。",
                fontSize = 9,
                fontColor = Shared.MUTED,
                whiteSpace = "normal",
            },
            Shared.FieldRow("Fog", self.lookFogColorPicker),
            UI.Label { text = "Fog Up  X / Y / Z", fontSize = 9, fontColor = Shared.MUTED },
            UI.Panel { flexDirection = "row", gap = 3, children = {
                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookFogUpXField } },
                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookFogUpYField } },
                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookFogUpZField } },
            } },
            UI.Label { text = "Height A / Height B", fontSize = 9, fontColor = Shared.MUTED },
            UI.Panel { flexDirection = "row", gap = 3, children = {
                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookFogHeightAField } },
                UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookFogHeightBField } },
            } },
        },
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
                    self.moverQLimitRow,
                    self.moverRLimitRow,
                    self.moverLayerLimitRow,
                    Shared.FieldRow("Trigger ID", self.triggerIdField),
                    self.modeLabel,
                    self.capabilityLabel,
                },
            },
            Shared.ComponentHeader("◐", "Part Look"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label {
                        text = "Unlit 分面：dot(世界法线, lightAxis) 从 -1 到 1 在 Neg / Mid / Pos 间渐变。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    Shared.FieldRow("Shader", self.lookShaderDropdown),
                    Shared.FieldRow("Neg", self.lookNegPicker),
                    Shared.FieldRow("Mid", self.lookMidPicker),
                    Shared.FieldRow("Pos", self.lookPosPicker),
                    UI.Label { text = "Light Axis  X / Y / Z", fontSize = 9, fontColor = Shared.MUTED },
                    UI.Panel { flexDirection = "row", gap = 3, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookAxisXField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookAxisYField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.lookAxisZField } },
                    } },
                    self.lookAOToggle,
                    Shared.FieldRow("AO Color", self.lookAOColorPicker),
                    Shared.FieldRow("AO Smooth", self.lookAOSmoothField),
                    Shared.FieldRow("AO Blend", self.lookAOBlendField),
                    Shared.FieldRow("Hover Color", self.lookEmissionColorPicker),
                    Shared.FieldRow("Hover Strength", self.lookEmissionStrengthField),
                    UI.Label {
                        text = "接触 AO：只画台阶和内凹折角。Smooth 是带宽，Blend 是对原色的影响力度。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = "Hover Emission：Preview 里可拖动时悬停才亮，走路锁住则不亮。0.5 秒可打断 fade。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    self.lookFogPanel,
                },
            },
            UI.Panel {
                padding = 10,
                gap = 6,
                children = {
                    self.openButton,
                },
            },
            Shared.ColorPopupSpacer(),
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
    self.moverMinQField:SetValue("")
    self.moverMaxQField:SetValue("")
    self.moverMinRField:SetValue("")
    self.moverMaxRField:SetValue("")
    self.moverMinLayerField:SetValue("")
    self.moverMaxLayerField:SetValue("")
    self.moverQLimitRow:SetVisible(false)
    self.moverRLimitRow:SetVisible(false)
    self.moverLayerLimitRow:SetVisible(false)
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
    self.lookShaderDropdown.props.value = LookApplier.SHADER_TRI_PRISM_LOOK
    self.lookNegPicker:SetHex("#8F8478")
    self.lookMidPicker:SetHex("#C4B6A6")
    self.lookPosPicker:SetHex("#F1E6D5")
    self.lookAxisXField:SetValue("")
    self.lookAxisYField:SetValue("")
    self.lookAxisZField:SetValue("")
    self.lookFogColorPicker:SetHex("#C9C2B4")
    self.lookFogUpXField:SetValue("")
    self.lookFogUpYField:SetValue("")
    self.lookFogUpZField:SetValue("")
    self.lookFogHeightAField:SetValue("")
    self.lookFogHeightBField:SetValue("")
    self.lookAOToggle:SetChecked(true)
    self.lookAOColorPicker:SetHex("#2A1F1A")
    self.lookAOSmoothField:SetValue("")
    self.lookAOBlendField:SetValue("")
    self.lookFogPanel:SetVisible(false)
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
    local mover = part.behaviors.mover or {}
    local function LimitText(value)
        return value == nil and "" or tostring(value)
    end
    self.moverMinQField:SetValue(LimitText(mover.minQ))
    self.moverMaxQField:SetValue(LimitText(mover.maxQ))
    self.moverMinRField:SetValue(LimitText(mover.minR))
    self.moverMaxRField:SetValue(LimitText(mover.maxR))
    self.moverMinLayerField:SetValue(LimitText(mover.minLayer))
    self.moverMaxLayerField:SetValue(LimitText(mover.maxLayer))
    self.moverQLimitRow:SetVisible(hasMover and moverAxes.q == true)
    self.moverRLimitRow:SetVisible(hasMover and moverAxes.r == true)
    self.moverLayerLimitRow:SetVisible(hasMover and moverAxes.layer == true)
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
    local look = LookApplier.CopyPartLook(part.look)
    self.lookShaderDropdown.props.value = look.shader
    self.lookNegPicker:SetHex(look.colorNeg)
    self.lookMidPicker:SetHex(look.colorMid)
    self.lookPosPicker:SetHex(look.colorPos)
    self.lookAxisXField:SetValue(string.format("%.2f", look.lightAxis.x))
    self.lookAxisYField:SetValue(string.format("%.2f", look.lightAxis.y))
    self.lookAxisZField:SetValue(string.format("%.2f", look.lightAxis.z))
    self.lookFogColorPicker:SetHex(look.fogColor)
    self.lookFogUpXField:SetValue(string.format("%.2f", look.fogUp.x))
    self.lookFogUpYField:SetValue(string.format("%.2f", look.fogUp.y))
    self.lookFogUpZField:SetValue(string.format("%.2f", look.fogUp.z))
    self.lookFogHeightAField:SetValue(string.format("%.2f", look.fogHeightA))
    self.lookFogHeightBField:SetValue(string.format("%.2f", look.fogHeightB))
    self.lookAOToggle:SetChecked(look.aoEnabled == true)
    self.lookAOColorPicker:SetHex(look.aoColor)
    self.lookAOSmoothField:SetValue(string.format("%.2f", look.aoSmooth))
    self.lookAOBlendField:SetValue(string.format("%.2f", look.aoBlend))
    self.lookEmissionColorPicker:SetHex(look.emissionColor)
    self.lookEmissionStrengthField:SetValue(string.format("%.2f", look.emissionStrength))
    self.lookFogPanel:SetVisible(LookApplier.UsesHeightFog(look))
end

return PartInspector
