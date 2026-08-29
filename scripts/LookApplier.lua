-- 把关卡 atmosphere 和 Part look 应用到场景。
-- LightGroup 只在路径变化时重载；雾/Bloom/Vignette 覆盖其 Zone，不新建 Zone。
-- Part look 按 shader 预设切换：一份 Material 对应一份 Surface Shader。

local LookApplier = {}

local DEFAULT_LIGHT_GROUP = "LightGroup/Daytime.xml"
local WHITEBOX_COLORS = {
    Color(0.95, 0.29, 0.33, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.87, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
}

LookApplier.SHADER_TRI_PRISM_LOOK = "tri_prism_look"
LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG = "tri_prism_look_height_fog"

LookApplier.SHADER_PATHS = {
    [LookApplier.SHADER_TRI_PRISM_LOOK] = "Shaders/BLGL/TriPrismLook.shader",
    [LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG] = "Shaders/BLGL/TriPrismLookHeightFog.shader",
}

LookApplier.SHADER_OPTIONS = {
    { value = LookApplier.SHADER_TRI_PRISM_LOOK, label = "Tri Prism Look" },
    { value = LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG, label = "Look + Height Fog" },
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

local function CopyAxis(source, fallback)
    source = source or {}
    fallback = fallback or { x = 0, y = 1, z = 0 }
    return {
        x = tonumber(source.x) or fallback.x,
        y = tonumber(source.y) or fallback.y,
        z = tonumber(source.z) or fallback.z,
    }
end

function LookApplier.NormalizeTonemap(value, fallback)
    if value == "none" or value == "aces" or value == "lut" then
        return value
    end
    return fallback or "none"
end

function LookApplier.TonemapModeEnum(value)
    if value == "aces" then
        return TONEMAP_MODE_ACES
    end
    if value == "lut" then
        return TONEMAP_MODE_LUT
    end
    return TONEMAP_MODE_NONE
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

function LookApplier.NormalizeShader(value)
    if value == LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG then
        return LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG
    end
    return LookApplier.SHADER_TRI_PRISM_LOOK
end

function LookApplier.UsesHeightFog(look)
    return LookApplier.NormalizeShader(look and look.shader) == LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG
end

function LookApplier.DefaultAtmosphere()
    return {
        lightGroup = DEFAULT_LIGHT_GROUP,
        fog = {
            color = "#C9C2B4",
            start = 1000.0,
            finish = 2000.0,
            density = 0.0,
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
        tonemap = "none",
    }
end

function LookApplier.DefaultPartLook()
    return {
        shader = LookApplier.SHADER_TRI_PRISM_LOOK,
        colorNeg = "#8F8478",
        colorMid = "#C4B6A6",
        colorPos = "#F1E6D5",
        lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
        fogUp = { x = 0.0, y = 1.0, z = 0.0 },
        fogColor = "#C9C2B4",
        fogHeightA = 4.0,
        fogHeightB = 0.0,
        aoEnabled = true,
        aoColor = "#2A1F1A",
        aoSmooth = 0.18,
        aoBlend = 1.0,
        emissionColor = "#FFF4D2",
        emissionStrength = 0.25,
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
        tonemap = LookApplier.NormalizeTonemap(source.tonemap, defaults.tonemap),
    }
end

function LookApplier.CopyPartLook(source)
    local defaults = LookApplier.DefaultPartLook()
    source = source or {}
    return {
        shader = LookApplier.NormalizeShader(source.shader),
        colorNeg = LookApplier.NormalizeHex(source.colorNeg, defaults.colorNeg),
        colorMid = LookApplier.NormalizeHex(source.colorMid, defaults.colorMid),
        colorPos = LookApplier.NormalizeHex(source.colorPos, defaults.colorPos),
        lightAxis = CopyAxis(source.lightAxis, defaults.lightAxis),
        fogUp = CopyAxis(source.fogUp, defaults.fogUp),
        fogColor = LookApplier.NormalizeHex(source.fogColor, defaults.fogColor),
        fogHeightA = (tonumber(source.fogHeightA) or defaults.fogHeightA) * 1.0,
        fogHeightB = (tonumber(source.fogHeightB) or defaults.fogHeightB) * 1.0,
        aoEnabled = source.aoEnabled ~= false,
        aoColor = LookApplier.NormalizeHex(source.aoColor, defaults.aoColor),
        aoSmooth = (tonumber(source.aoSmooth) or defaults.aoSmooth) * 1.0,
        aoBlend = (tonumber(source.aoBlend) or defaults.aoBlend) * 1.0,
        emissionColor = LookApplier.NormalizeHex(source.emissionColor, defaults.emissionColor),
        emissionStrength = math.max(0.0, (tonumber(source.emissionStrength) or defaults.emissionStrength) * 1.0),
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
    local shaderPath = LookApplier.SHADER_PATHS[look.shader] or LookApplier.SHADER_PATHS[LookApplier.SHADER_TRI_PRISM_LOOK]
    local material = Material:new()
    if not material:SetSurfaceShader(shaderPath) then
        print("LookApplier: failed to load " .. shaderPath)
        return LookApplier.CreateWhiteboxMaterial(1)
    end
    material:SetShaderParameter("color_neg", Variant(HexToColor(look.colorNeg, Color(0.56, 0.52, 0.47, 1))))
    material:SetShaderParameter("color_mid", Variant(HexToColor(look.colorMid, Color(0.77, 0.71, 0.65, 1))))
    material:SetShaderParameter("color_pos", Variant(HexToColor(look.colorPos, Color(0.95, 0.90, 0.84, 1))))
    material:SetShaderParameter("light_axis", Variant(Vector3(look.lightAxis.x, look.lightAxis.y, look.lightAxis.z)))
    material:SetShaderParameter("ao_enabled", Variant(look.aoEnabled and 1.0 or 0.0))
    material:SetShaderParameter("ao_color", Variant(HexToColor(look.aoColor, Color(0.16, 0.12, 0.10, 1))))
    material:SetShaderParameter("ao_smooth", Variant(look.aoSmooth))
    material:SetShaderParameter("ao_blend", Variant(look.aoBlend))
    material:SetShaderParameter("emission_color", Variant(HexToColor(look.emissionColor, Color(1.0, 0.96, 0.82, 1))))
    material:SetShaderParameter("emission_strength", Variant(look.emissionStrength))
    material:SetShaderParameter("hover_amount", Variant(0.0))
    if look.shader == LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG then
        material:SetShaderParameter("fog_up", Variant(Vector3(look.fogUp.x, look.fogUp.y, look.fogUp.z)))
        material:SetShaderParameter("fog_color", Variant(HexToColor(look.fogColor, Color(0.79, 0.76, 0.71, 1))))
        material:SetShaderParameter("fog_height_a", Variant(look.fogHeightA))
        material:SetShaderParameter("fog_height_b", Variant(look.fogHeightB))
        print(string.format(
            "LookApplier: part material shader=%s neg=%s mid=%s pos=%s axis=%.2f,%.2f,%.2f fog=%s up=%.2f,%.2f,%.2f heightA=%.2f heightB=%.2f ao=%s color=%s smooth=%.2f blend=%.2f",
            look.shader,
            look.colorNeg,
            look.colorMid,
            look.colorPos,
            look.lightAxis.x,
            look.lightAxis.y,
            look.lightAxis.z,
            look.fogColor,
            look.fogUp.x,
            look.fogUp.y,
            look.fogUp.z,
            look.fogHeightA,
            look.fogHeightB,
            tostring(look.aoEnabled),
            look.aoColor,
            look.aoSmooth,
            look.aoBlend
        ))
    else
        print(string.format(
            "LookApplier: part material shader=%s neg=%s mid=%s pos=%s axis=%.2f,%.2f,%.2f ao=%s color=%s smooth=%.2f blend=%.2f",
            look.shader,
            look.colorNeg,
            look.colorMid,
            look.colorPos,
            look.lightAxis.x,
            look.lightAxis.y,
            look.lightAxis.z,
            tostring(look.aoEnabled),
            look.aoColor,
            look.aoSmooth,
            look.aoBlend
        ))
    end
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
    zone.heightFog = false
    zone.autoExposureEnabled = false
    zone.tonemapMode = LookApplier.TonemapModeEnum(atmosphere.tonemap)
    zone.tonemapLUTEnabled = atmosphere.tonemap == "lut"
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
