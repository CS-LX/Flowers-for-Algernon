-- Bloom isolation lab.
-- Left: red Unlit ALBEDO 0.85. Right: yellow ALBEDO 1 + EMISSION 8.
-- Transparent full-screen UI root so 3D is not covered.

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
local statusLabel_ = nil

local PRESETS = {
    { id = "off", title = "1 Bloom关 HDR关" },
    { id = "ldr", title = "2 Bloom开 HDR关" },
    { id = "hdr", title = "3 Bloom开 HDR开" },
}
local presetIndex_ = 1

local function MakeMat(path, label)
    local material = Material:new()
    local ok = material:SetSurfaceShader(path)
    print("BloomLab: " .. label .. " " .. path .. " ok=" .. tostring(ok))
    return material
end

local function PlaceBox(parent, name, x, material)
    local node = parent:CreateChild(name)
    node.position = Vector3(x, 0, 0)
    node.scale = Vector3(1.1, 1.1, 1.1)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(material)
    return node
end

local function ApplyPreset(id)
    if not zone_ then
        return
    end
    zone_.autoExposureEnabled = false
    zone_.vignetteEnabled = false
    zone_.ssrEnabled = false
    zone_.ssgiEnabled = false
    zone_.motionBlurEnabled = false
    zone_.fxaaEnabled = false
    zone_.volumetricFogEnabled = false
    zone_.tonemapLUTEnabled = false
    zone_.tonemapMode = TONEMAP_MODE_NONE
    zone_.fogStart = 50.0
    zone_.fogEnd = 80.0
    zone_.fogDensity = 0.0
    zone_.fogColor = Color(0.55, 0.58, 0.62, 1.0)
    zone_.ambientColor = Color(0.55, 0.58, 0.62, 1.0)
    zone_.bloomPlusEnabled = false
    renderer.hdrRendering = false
    if id == "ldr" or id == "hdr" then
        zone_.bloomPlusEnabled = true
        zone_.bloomMode = BLOOM_MODE_PLUS
        zone_.bloomThreshold = 1.1
        zone_.bloomPlusIntensity = 1.5
    end
    if id == "hdr" then
        renderer.hdrRendering = true
    end
    print(string.format(
        "BloomLab: preset=%s hdr=%s bloom=%s thresh=%.2f intensity=%.2f",
        id,
        tostring(renderer.hdrRendering),
        tostring(zone_.bloomPlusEnabled),
        zone_.bloomThreshold,
        zone_.bloomPlusIntensity
    ))
end

local function RefreshStatus()
    if statusLabel_ then
        statusLabel_:SetText("左红对照 右黄热盒  " .. PRESETS[presetIndex_].title)
    end
end

local function SelectPreset(index)
    presetIndex_ = index
    ApplyPreset(PRESETS[index].id)
    RefreshStatus()
end

function ColorTruthLab.Start()
    graphics.windowTitle = "Bloom Lab"
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local zoneNode = scene_:CreateChild("Zone")
    zone_ = zoneNode:CreateComponent("Zone")
    zone_:SetBoundingBox(BoundingBox(Vector3(-80, -20, -80), Vector3(80, 60, 80)))
    zone_.priority = 0
    zone_.override = true
    zone_.ambientSource = AMBIENT_COLOR
    ApplyPreset("off")

    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, 0.2, -6.0)
    cameraNode_:LookAt(Vector3(0, 0, 0))
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 4.0
    camera_.nearClip = 0.1
    camera_.farClip = 50.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))

    local root = scene_:CreateChild("LabRoot")
    PlaceBox(root, "ControlRed", -1.35, MakeMat("Shaders/BLGL/LabBloomDim.shader", "red"))
    PlaceBox(root, "HotYellow", 1.35, MakeMat("Shaders/BLGL/LabBloomHot.shader", "hot"))

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })
    statusLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = { 240, 240, 245, 255 },
    }
    local buttons = {}
    for i = 1, #PRESETS do
        local index = i
        buttons[i] = UI.Button {
            text = tostring(i),
            width = 44,
            height = 36,
            onClick = function()
                SelectPreset(index)
            end,
        }
    end
    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute",
                left = 12,
                top = 12,
                padding = 10,
                gap = 8,
                backgroundColor = { 12, 16, 24, 210 },
                borderRadius = 8,
                pointerEvents = "auto",
                children = {
                    statusLabel_,
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        children = buttons,
                    },
                },
            },
        },
    })
    RefreshStatus()
    SubscribeToEvent("Update", "HandleColorTruthLabUpdate")
    print("BloomLab: transparent UI root, red vs yellow emission")
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
    end
end

function ColorTruthLab.Stop()
    UI.Shutdown()
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    zone_ = nil
    statusLabel_ = nil
end

return ColorTruthLab
