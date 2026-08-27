-- 把关卡 atmosphere 和 Part look 应用到场景。
-- LightGroup 只在路径变化时重载；雾/Bloom/Vignette 覆盖其 Zone，不新建 Zone。

local LookApplier = {}

local DEFAULT_LIGHT_GROUP = "LightGroup/Daytime.xml"
local DEFAULT_SHADER = "Shaders/BLGL/TriPrismLook.shader"
local WHITEBOX_COLORS = {
    Color(0.95, 0.29, 0.33, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.87, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
}

local function HexToColor(hex, fallback)
    if type(hex) ~= "string" then
        return fallback
    end
    local cleaned = hex:gsub("#", "")
    if #cleaned ~= 6 and #cleaned ~= 8 then
        return fallback
    end
    local r = tonumber(cleaned:sub(1, 2), 16)
    local g = tonumber(cleaned:sub(3, 4), 16)
    local b = tonumber(cleaned:sub(5, 6), 16)
    if not r or not g or not b then
        return fallback
    end
    return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
end

function LookApplier.NormalizeHex(hex, fallback)
    local color = HexToColor(hex, nil)
    if not color then
        return fallback
    end
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.r * 255.0 + 0.5),
        math.floor(color.g * 255.0 + 0.5),
        math.floor(color.b * 255.0 + 0.5)
    )
end

function LookApplier.DefaultAtmosphere()
    return {
        lightGroup = DEFAULT_LIGHT_GROUP,
        fog = {
            color = "#C9C2B4",
            start = 8.0,
            finish = 42.0,
            density = 0.85,
            heightFog = false,
        },
        bloom = {
            enabled = false,
            threshold = 1.1,
            intensity = 0.15,
        },
        vignette = {
            enabled = false,
            intensity = 0.08,
        },
    }
end

function LookApplier.DefaultPartLook()
    return {
        colorNeg = "#8F8478",
        colorMid = "#C4B6A6",
        colorPos = "#F1E6D5",
        lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
    }
end

function LookApplier.CopyAtmosphere(source)
    local defaults = LookApplier.DefaultAtmosphere()
    source = source or {}
    local fog = source.fog or {}
    local bloom = source.bloom or {}
    local vignette = source.vignette or {}
    return {
        lightGroup = type(source.lightGroup) == "string" and source.lightGroup or defaults.lightGroup,
        fog = {
            color = LookApplier.NormalizeHex(fog.color, defaults.fog.color),
            start = tonumber(fog.start) or defaults.fog.start,
            finish = tonumber(fog.finish or fog["end"]) or defaults.fog.finish,
            density = tonumber(fog.density) or defaults.fog.density,
            heightFog = fog.heightFog == true,
        },
        bloom = {
            enabled = bloom.enabled == true,
            threshold = tonumber(bloom.threshold) or defaults.bloom.threshold,
            intensity = tonumber(bloom.intensity) or defaults.bloom.intensity,
        },
        vignette = {
            enabled = vignette.enabled == true,
            intensity = tonumber(vignette.intensity) or defaults.vignette.intensity,
        },
    }
end

function LookApplier.CopyPartLook(source)
    local defaults = LookApplier.DefaultPartLook()
    source = source or {}
    local axis = source.lightAxis or {}
    return {
        colorNeg = LookApplier.NormalizeHex(source.colorNeg, defaults.colorNeg),
        colorMid = LookApplier.NormalizeHex(source.colorMid, defaults.colorMid),
        colorPos = LookApplier.NormalizeHex(source.colorPos, defaults.colorPos),
        lightAxis = {
            x = tonumber(axis.x) or defaults.lightAxis.x,
            y = tonumber(axis.y) or defaults.lightAxis.y,
            z = tonumber(axis.z) or defaults.lightAxis.z,
        },
    }
end

function LookApplier.WhiteboxColor(material)
    return WHITEBOX_COLORS[((material or 1) - 1) % #WHITEBOX_COLORS + 1]
end

function LookApplier.CreateWhiteboxMaterial(materialId)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(LookApplier.WhiteboxColor(materialId)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.72))
    return material
end

function LookApplier.CreatePartMaterial(look)
    look = LookApplier.CopyPartLook(look)
    local material = Material:new()
    if not material:SetSurfaceShader(DEFAULT_SHADER) then
        print("LookApplier: failed to load " .. DEFAULT_SHADER)
        return LookApplier.CreateWhiteboxMaterial(1)
    end
    material:SetShaderParameter("color_neg", Variant(HexToColor(look.colorNeg, Color(0.56, 0.52, 0.47, 1))))
    material:SetShaderParameter("color_mid", Variant(HexToColor(look.colorMid, Color(0.77, 0.71, 0.65, 1))))
    material:SetShaderParameter("color_pos", Variant(HexToColor(look.colorPos, Color(0.95, 0.90, 0.84, 1))))
    material:SetShaderParameter("light_axis", Variant(Vector3(look.lightAxis.x, look.lightAxis.y, look.lightAxis.z)))
    print(string.format(
        "LookApplier: part material neg=%s mid=%s pos=%s axis=%.2f,%.2f,%.2f",
        look.colorNeg,
        look.colorMid,
        look.colorPos,
        look.lightAxis.x,
        look.lightAxis.y,
        look.lightAxis.z
    ))
    return material
end

function LookApplier.ApplyAtmosphere(scene, atmosphere)
    if not scene then
        return false
    end
    atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    local lightGroup = scene:GetChild("LightGroup")
    local currentPath = ""
    if lightGroup then
        local pathVar = lightGroup:GetVar("lightGroupPath")
        if pathVar and pathVar:GetType() ~= VAR_NONE then
            currentPath = pathVar:GetString()
        end
    end
    if not lightGroup or currentPath ~= atmosphere.lightGroup then
        if lightGroup then
            lightGroup:Remove()
        end
        local lightGroupFile = cache:GetResource("XMLFile", atmosphere.lightGroup)
        if not lightGroupFile then
            print("LookApplier: missing " .. tostring(atmosphere.lightGroup))
            return false
        end
        lightGroup = scene:CreateChild("LightGroup")
        lightGroup:LoadXML(lightGroupFile:GetRoot())
        lightGroup:SetVar("lightGroupPath", Variant(atmosphere.lightGroup))
    end
    local zone = lightGroup:GetComponent("Zone", true)
    if not zone then
        print("LookApplier: LightGroup has no Zone")
        return false
    end
    zone.fogColor = HexToColor(atmosphere.fog.color, Color(0.79, 0.76, 0.71, 1))
    zone.fogStart = atmosphere.fog.start
    zone.fogEnd = atmosphere.fog.finish
    zone.fogDensity = atmosphere.fog.density
    zone.heightFog = atmosphere.fog.heightFog
    zone.autoExposureEnabled = false
    zone.bloomPlusEnabled = atmosphere.bloom.enabled
    zone.bloomThreshold = atmosphere.bloom.threshold
    zone.bloomPlusIntensity = atmosphere.bloom.intensity
    zone.vignetteEnabled = atmosphere.vignette.enabled
    zone.vignetteIntensity = atmosphere.vignette.intensity
    print(string.format(
        "LookApplier: atmosphere lightGroup=%s fog=%s start=%.1f finish=%.1f bloom=%s vignette=%s",
        atmosphere.lightGroup,
        atmosphere.fog.color,
        atmosphere.fog.start,
        atmosphere.fog.finish,
        tostring(atmosphere.bloom.enabled),
        tostring(atmosphere.vignette.enabled)
    ))
    return true
end

return LookApplier
