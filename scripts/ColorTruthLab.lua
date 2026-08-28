-- 隔离实验：找出能拿到真实 RGB 的路径，并把雾 / HDR / tonemap 握在脚本手里。
-- 不加载 LightGroup。自己建 Zone。实验稳定前不回关卡编辑器。

local UI = require("urhox-libs/UI")

local ColorTruthLab = {}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Zone|nil
local zone_ = nil
---@type Material|nil
local sourceMat_ = nil
---@type Material|nil
local rawMat_ = nil
local statusLabel_ = nil

local TARGET = Color(0.95686275, 0.2627451, 0.21176471, 1.0)
local TARGET_HEX = "#F44336"

local PRESETS = {
    { id = "baseline", title = "1 基线: 无雾 HDR关 TONEMAP_NONE" },
    { id = "fog", title = "2 加亮蓝雾 density=0.85 start=8" },
    { id = "fogfar", title = "3 雾推远 start=1000 density=0" },
    { id = "hdr", title = "4 无雾 + HDR开 + TONEMAP_NONE" },
    { id = "aces", title = "5 无雾 + HDR开 + ACES" },
}

local presetIndex_ = 1

local function CreateUnlit(shaderPath, useSourceColor)
    local material = Material:new()
    local ok = material:SetSurfaceShader(shaderPath)
    print("ColorTruthLab: SetSurfaceShader " .. shaderPath .. " = " .. tostring(ok))
    if not ok then
        material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        material:SetShaderParameter("MatDiffColor", Variant(TARGET))
        return material
    end
    material:SetShaderParameter("base_color", Variant(TARGET))
    print("ColorTruthLab: " .. (useSourceColor and "source_color" or "raw vec4") .. " " .. TARGET_HEX)
    return material
end

local function PlaceBox(parent, name, x, material)
    local node = parent:CreateChild(name)
    node.position = Vector3(x, 0.5, 0)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(material)
    return node
end

local function DisablePost(zone)
    zone.autoExposureEnabled = false
    zone.bloomPlusEnabled = false
    zone.vignetteEnabled = false
    zone.ssrEnabled = false
    zone.ssgiEnabled = false
    zone.motionBlurEnabled = false
    zone.fxaaEnabled = false
    zone.volumetricFogEnabled = false
    zone.tonemapLUTEnabled = false
end

local function ApplyPreset(id)
    if not zone_ then
        return
    end
    renderer.hdrRendering = false
    zone_.tonemapMode = TONEMAP_MODE_NONE
    zone_.fogColor = Color(0.08, 0.09, 0.11, 1.0)
    zone_.fogStart = 1000.0
    zone_.fogEnd = 2000.0
    zone_.fogDensity = 0.0
    zone_.heightFog = false
    DisablePost(zone_)

    if id == "fog" then
        zone_.fogColor = Color(0.122, 0.580, 0.953, 1.0)
        zone_.fogStart = 8.0
        zone_.fogEnd = 42.0
        zone_.fogDensity = 0.85
    elseif id == "fogfar" then
        zone_.fogColor = Color(0.122, 0.580, 0.953, 1.0)
        zone_.fogStart = 1000.0
        zone_.fogEnd = 2000.0
        zone_.fogDensity = 0.0
    elseif id == "hdr" then
        renderer.hdrRendering = true
        zone_.tonemapMode = TONEMAP_MODE_NONE
    elseif id == "aces" then
        renderer.hdrRendering = true
        zone_.tonemapMode = TONEMAP_MODE_ACES
    end

    print(string.format(
        "ColorTruthLab: preset=%s hdr=%s tonemap=%s fogStart=%.1f fogEnd=%.1f density=%.2f fog=%s",
        id,
        tostring(renderer.hdrRendering),
        tostring(zone_.tonemapMode),
        zone_.fogStart,
        zone_.fogEnd,
        zone_.fogDensity,
        string.format("#%02X%02X%02X",
            math.floor(zone_.fogColor.r * 255.0 + 0.5),
            math.floor(zone_.fogColor.g * 255.0 + 0.5),
            math.floor(zone_.fogColor.b * 255.0 + 0.5))
    ))
end

local function RefreshStatus()
    if not statusLabel_ then
        return
    end
    local preset = PRESETS[presetIndex_]
    statusLabel_:SetText(
        "目标 " .. TARGET_HEX .. "  左UI色块  中source_color  右raw vec4\n" ..
        preset.title .. "   点按钮或按 1-5。对齐=真RGB  发粉/发白=雾或映射"
    )
end

local function SelectPreset(index)
    presetIndex_ = index
    ApplyPreset(PRESETS[index].id)
    RefreshStatus()
end

function ColorTruthLab.Start()
    graphics.windowTitle = "Color Truth Lab"
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    zone_ = scene_:CreateComponent("Zone")
    zone_:SetBoundingBox(BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000)))
    zone_.priority = 0
    zone_.override = true
    zone_.ambientSource = AMBIENT_COLOR
    zone_.ambientColor = Color(0, 0, 0, 1)
    ApplyPreset("baseline")

    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, 0.5, -4.0)
    cameraNode_:LookAt(Vector3(0, 0.5, 0))
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 4.0
    camera_.nearClip = 0.1
    camera_.farClip = 50.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))

    sourceMat_ = CreateUnlit("Shaders/BLGL/LabTrueRgbSource.shader", true)
    rawMat_ = CreateUnlit("Shaders/BLGL/LabTrueRgbRaw.shader", false)

    local root = scene_:CreateChild("LabRoot")
    PlaceBox(root, "SourceColorBox", -1.2, sourceMat_)
    PlaceBox(root, "RawVec4Box", 1.2, rawMat_)

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    local uiSwatch = UI.Panel {
        width = 72,
        height = 72,
        backgroundColor = { 244, 67, 54, 255 },
        borderRadius = 6,
    }
    statusLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = { 240, 240, 245, 255 },
        whiteSpace = "normal",
        flexGrow = 1,
    }

    local buttons = {}
    for i = 1, #PRESETS do
        local index = i
        buttons[i] = UI.Button {
            text = tostring(i),
            width = 40,
            height = 36,
            onClick = function()
                SelectPreset(index)
            end,
        }
    end

    UI.SetRoot(UI.Panel {
        width = "100%",
        height = 148,
        padding = 12,
        gap = 10,
        backgroundColor = { 12, 16, 24, 220 },
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 12,
                children = { uiSwatch, statusLabel_ },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = buttons,
            },
        },
    })
    RefreshStatus()

    SubscribeToEvent("Update", "HandleColorTruthLabUpdate")
    print("ColorTruthLab: target " .. TARGET_HEX)
    print("ColorTruthLab: left UI NanoVG, mid source_color Unlit, right raw vec4 Unlit")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleColorTruthLabUpdate(eventType, eventData)
    eventData["TimeStep"]:GetFloat()
    if input:GetKeyPress(KEY_1) then
        SelectPreset(1)
    elseif input:GetKeyPress(KEY_2) then
        SelectPreset(2)
    elseif input:GetKeyPress(KEY_3) then
        SelectPreset(3)
    elseif input:GetKeyPress(KEY_4) then
        SelectPreset(4)
    elseif input:GetKeyPress(KEY_5) then
        SelectPreset(5)
    end
end

function ColorTruthLab.Stop()
    UI.Shutdown()
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    zone_ = nil
    sourceMat_ = nil
    rawMat_ = nil
    statusLabel_ = nil
end

return ColorTruthLab
