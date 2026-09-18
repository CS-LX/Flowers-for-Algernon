-- 选关页模型簇目录。
-- 每章一份布局；MenuClusterBackdrop 只按 chapter 查表，不读关卡 JSON。

local MenuClusterCatalog = {}

local WORLD_BIT = 2

-- 面色/grade 按簇写；高度雾色烘焙在 fog.color，切章时由 Backdrop tween。
local CITY_LOOK = {
    ["slots.wall.colorNeg"] = "#2B6FA8",
    ["slots.wall.colorMid"] = "#7EB7E6",
    ["slots.wall.colorPos"] = "#FFF4E8",
    ["slots.wall.fogColor"] = "#348AA3",
    ["slots.wall.gradeSaturation"] = "0.55",
    ["slots.wall.gradeValue"] = "1.08",
    ["slots.wall.gradeContrast"] = "0.72",
    ["slots.wall.gradeHaze"] = "0.22",
}

local CITY_FOG = { heightA = -1.04, heightB = -1.67, color = "#348AA3" }

-- 颜色/高度雾对齐 1-1 Path look，但不读 level-1-1.json。
local CHAPTER1_VOXEL_LOOK = {
    shader = "tri_prism_look_height_fog",
    colorNeg = "#554C3E",
    colorMid = "#685D4F",
    colorPos = "#FFF7E7",
    fogColor = "#C0B499",
    fogHeightA = -1.25,
    fogHeightB = -1.55,
    aoEnabled = true,
    aoColor = "#2A1F1A",
    aoSmooth = 0.18,
    aoBlend = 1.0,
    emissionColor = "#FFF4D2",
    emissionStrength = 0.25,
    lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
    fogUp = { x = 0.0, y = 1.0, z = 0.0 },
}

-- 菜单尺度的独立体素堆，像 1-1 的折线路但更矮、围在滚筒脚下。
local CHAPTER_1_STACKS = {
    {
        id = "menu_voxel_1",
        x = -2.35, z = 1.55, yaw = 30,
        cells = {
            { q = 0, r = 0, s = 0, l = 0 }, { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 2, l = 0 },
            { q = 0, r = 0, s = 3, l = 0 }, { q = 0, r = 0, s = 4, l = 0 }, { q = 0, r = 0, s = 5, l = 0 },
            { q = 0, r = 0, s = 0, l = 1 }, { q = 0, r = 0, s = 1, l = 1 }, { q = 0, r = 0, s = 5, l = 1 },
            { q = 1, r = -1, s = 3, l = 0 }, { q = 1, r = -1, s = 4, l = 0 }, { q = 1, r = -1, s = 2, l = 0 },
        },
    },
    {
        id = "menu_voxel_2",
        x = -0.90, z = 2.10, yaw = 90,
        cells = {
            { q = 0, r = 0, s = 0, l = 0 }, { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 2, l = 0 },
            { q = 0, r = 0, s = 3, l = 0 }, { q = 0, r = 0, s = 4, l = 0 }, { q = 0, r = 0, s = 5, l = 0 },
            { q = 0, r = 0, s = 2, l = 1 }, { q = 0, r = 0, s = 3, l = 1 },
            { q = -1, r = 1, s = 0, l = 0 }, { q = -1, r = 1, s = 1, l = 0 }, { q = -1, r = 1, s = 5, l = 0 },
        },
    },
    {
        id = "menu_voxel_3",
        x = 0.35, z = 2.25, yaw = 150,
        cells = {
            { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 2, l = 0 }, { q = 0, r = 0, s = 3, l = 0 },
            { q = 0, r = 0, s = 4, l = 0 },
            { q = 0, r = 0, s = 2, l = 1 }, { q = 0, r = 0, s = 3, l = 1 }, { q = 0, r = 0, s = 2, l = 2 },
            { q = 1, r = 0, s = 4, l = 0 }, { q = 1, r = 0, s = 5, l = 0 }, { q = 1, r = 0, s = 3, l = 0 },
        },
    },
    {
        id = "menu_voxel_4",
        x = 1.55, z = 1.95, yaw = 210,
        cells = {
            { q = 0, r = 0, s = 0, l = 0 }, { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 2, l = 0 },
            { q = 0, r = 0, s = 3, l = 0 }, { q = 0, r = 0, s = 4, l = 0 }, { q = 0, r = 0, s = 5, l = 0 },
            { q = 0, r = 0, s = 4, l = 1 }, { q = 0, r = 0, s = 5, l = 1 }, { q = 0, r = 0, s = 0, l = 1 },
            { q = 0, r = 1, s = 1, l = 0 }, { q = 0, r = 1, s = 2, l = 0 },
        },
    },
    {
        id = "menu_voxel_5",
        x = 2.55, z = 1.35, yaw = 270,
        cells = {
            { q = 0, r = 0, s = 0, l = 0 }, { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 5, l = 0 },
            { q = 0, r = 0, s = 0, l = 1 }, { q = 0, r = 0, s = 1, l = 1 },
            { q = 1, r = -1, s = 3, l = 0 }, { q = 1, r = -1, s = 2, l = 0 }, { q = 1, r = -1, s = 4, l = 0 },
            { q = 1, r = -1, s = 3, l = 1 },
        },
    },
    {
        id = "menu_voxel_6",
        x = -2.70, z = 0.15, yaw = 0,
        cells = {
            { q = 0, r = 0, s = 2, l = 0 }, { q = 0, r = 0, s = 3, l = 0 }, { q = 0, r = 0, s = 4, l = 0 },
            { q = 0, r = 0, s = 3, l = 1 },
            { q = -1, r = 0, s = 0, l = 0 }, { q = -1, r = 0, s = 1, l = 0 }, { q = -1, r = 0, s = 5, l = 0 },
            { q = -1, r = 0, s = 0, l = 1 }, { q = -1, r = 0, s = 5, l = 1 },
        },
    },
    {
        id = "menu_voxel_7",
        x = 2.70, z = 0.05, yaw = 330,
        cells = {
            { q = 0, r = 0, s = 0, l = 0 }, { q = 0, r = 0, s = 1, l = 0 }, { q = 0, r = 0, s = 2, l = 0 },
            { q = 0, r = 0, s = 3, l = 0 }, { q = 0, r = 0, s = 4, l = 0 }, { q = 0, r = 0, s = 5, l = 0 },
            { q = 0, r = 0, s = 1, l = 1 }, { q = 0, r = 0, s = 2, l = 1 }, { q = 0, r = 0, s = 1, l = 2 },
        },
    },
    {
        id = "menu_voxel_8",
        x = -2.15, z = -0.80, yaw = 60,
        cells = {
            { q = 0, r = 0, s = 4, l = 0 }, { q = 0, r = 0, s = 5, l = 0 }, { q = 0, r = 0, s = 0, l = 0 },
            { q = 0, r = 0, s = 5, l = 1 },
            { q = 1, r = 0, s = 2, l = 0 }, { q = 1, r = 0, s = 3, l = 0 }, { q = 1, r = 0, s = 1, l = 0 },
        },
    },
}

local DAISY_LOOK = {
    ["slots.wall.colorNeg"] = "#FFFFFF",
    ["slots.wall.colorMid"] = "#FFFFFF",
    ["slots.wall.colorPos"] = "#FFFFFF",
    ["slots.wall.fogColor"] = "#000000",
    ["slots.wall.gradeSaturation"] = "1.00",
    ["slots.wall.gradeValue"] = "0.60",
    ["slots.wall.gradeContrast"] = "1.00",
    ["slots.wall.gradeHaze"] = "0.00",
}

local DAISY_FOG = { heightA = -1.25, heightB = -1.70, color = "#000000" }
local CHAPTER1_FOG = { heightA = -1.25, heightB = -1.55, color = "#C0B499" }
local LAB_FOG = { heightA = -0.80, heightB = -1.34, color = "#102121" }
local LAB_CAMERA_FOG = LAB_FOG
local LAB_DESK_FOG = LAB_FOG
local LAB_MONITOR_FOG = LAB_FOG

-- 实验室簇：左边摄像机朝中心拍，右边桌子上放监视器。槽色走 sidecar。
local LAB_LOOK = {}

local function LabItems(prefix)
    -- 监视器网格中心和屏幕都在 +Z。rootScale 0.01 后再乘条目 scale。
    -- 视觉中心压回桌面中心；yaw 转 180° 让屏幕朝外，不要屁股朝镜头。
    local camX, camZ = -1.55, 1.15
    local deskX, deskZ = 1.60, 1.05
    local deskScale = 0.48
    local monitorScale = 0.22
    local deskLift = 0.28
    local deskTop = 0.981809 * deskScale
    local monitorCenterZ = ((149.75 + 360.0) * 0.5) * 0.01 * monitorScale
    local deskYaw = math.deg(math.atan(-deskX, -deskZ))
    local camYaw = math.deg(math.atan(-camX, -camZ))
    local monitorYaw = deskYaw + 180.0
    local rad = math.rad(monitorYaw)
    local monitorX = deskX - math.sin(rad) * monitorCenterZ
    local monitorZ = deskZ - math.cos(rad) * monitorCenterZ
    return {
        { id = prefix .. "_camera", modelId = "camera_stand", x = camX, z = camZ, yaw = camYaw, scale = 0.38, fog = LAB_CAMERA_FOG },
        { id = prefix .. "_desk", modelId = "lab_desk", x = deskX, z = deskZ, yaw = deskYaw, scale = deskScale, y = deskLift, fog = LAB_DESK_FOG },
        { id = prefix .. "_monitor", modelId = "monitor", x = monitorX, z = monitorZ, yaw = monitorYaw, scale = monitorScale, y = deskTop + deskLift, fog = LAB_MONITOR_FOG },
    }
end

-- 菜单正交视野约 3.2。建筑铺在棱柱脚下偏后/两侧，不挡滚筒。
-- 各楼包围盒底由 Backdrop 对齐到同一世界高度，不再单独写 y。
local CHAPTER_5_ITEMS = {
    { id = "menu_daisy_1", modelId = "daisy", x = -2.40, z =  1.55, yaw =  38, scale = 0.42 },
    { id = "menu_daisy_2", modelId = "daisy", x = -1.05, z =  2.05, yaw = 112, scale = 0.38 },
    { id = "menu_daisy_3", modelId = "daisy", x =  0.20, z =  2.20, yaw = 201, scale = 0.44 },
    { id = "menu_daisy_4", modelId = "daisy", x =  1.40, z =  1.90, yaw = 287, scale = 0.40 },
    { id = "menu_daisy_5", modelId = "daisy", x =  2.55, z =  1.40, yaw =  67, scale = 0.42 },
    { id = "menu_daisy_6", modelId = "daisy", x = -2.70, z =  0.10, yaw = 156, scale = 0.36 },
    { id = "menu_daisy_9", modelId = "daisy", x = -2.20, z = -0.85, yaw = 312, scale = 0.40 },
    { id = "menu_daisy_7", modelId = "daisy", x =  2.75, z =  0.05, yaw = 248, scale = 0.40 },
    { id = "menu_daisy_8", modelId = "daisy", x =  1.70, z = -0.65, yaw =  19, scale = 0.38 },
}

local CHAPTER_3_ITEMS = {
    { id = "menu_city_1", modelId = "small_building_Rq572hdKEz", x = -2.55, z =  1.70, yaw =  37, scale = 0.52 },
    { id = "menu_city_2", modelId = "large_building_h7Jaq7bqMq", x = -1.15, z =  2.15, yaw = 118, scale = 0.42 },
    { id = "menu_city_3", modelId = "skyscraper_XST1j6kYsL",     x =  0.10, z =  2.35, yaw = 203, scale = 0.36 },
    { id = "menu_city_4", modelId = "large_building_3IhrYZp6tP", x =  1.35, z =  2.05, yaw =  71, scale = 0.48 },
    { id = "menu_city_5", modelId = "small_building_Rq572hdKEz", x =  2.60, z =  1.60, yaw = 311, scale = 0.52 },
    { id = "menu_city_6", modelId = "skyscraper_obYD8hWLTZ",     x = -2.80, z =  0.25, yaw = 164, scale = 0.38 },
    { id = "menu_city_7", modelId = "large_building_ppwtREejXg", x =  2.85, z =  0.20, yaw = 248, scale = 0.50 },
    { id = "menu_city_8", modelId = "large_building_sxXonOmtct", x =  1.85, z = -0.70, yaw =  19, scale = 0.52 },
}

---@class MenuClusterDefinition
---@field id string
---@field kind string|nil
---@field items table[]|nil
---@field stacks table[]|nil
---@field look table
---@field fog table
---@field viewMask number

---@type table<number, MenuClusterDefinition>
local CHAPTERS = {
    [1] = {
        id = "chapter1_voxels",
        kind = "voxels",
        stacks = CHAPTER_1_STACKS,
        look = CHAPTER1_VOXEL_LOOK,
        fog = CHAPTER1_FOG,
        viewMask = WORLD_BIT,
    },
    [2] = {
        id = "chapter2_lab",
        items = LabItems("menu_ch2"),
        look = LAB_LOOK,
        fog = LAB_FOG,
        viewMask = WORLD_BIT,
    },
    [3] = {
        id = "chapter3_city",
        items = CHAPTER_3_ITEMS,
        look = CITY_LOOK,
        fog = CITY_FOG,
        viewMask = WORLD_BIT,
    },
    [4] = {
        id = "chapter4_lab",
        items = LabItems("menu_ch4"),
        look = LAB_LOOK,
        fog = LAB_FOG,
        viewMask = WORLD_BIT,
    },
    [5] = {
        id = "chapter5_daisy",
        items = CHAPTER_5_ITEMS,
        look = DAISY_LOOK,
        fog = DAISY_FOG,
        viewMask = WORLD_BIT,
    },
}

function MenuClusterCatalog.Get(chapter)
    local number = tonumber(chapter)
    if not number then
        return nil
    end
    return CHAPTERS[math.floor(number + 0.5)]
end

return MenuClusterCatalog
