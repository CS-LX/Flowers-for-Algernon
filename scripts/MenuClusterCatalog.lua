-- 选关页模型簇目录。
-- 每章一份布局；MenuClusterBackdrop 只按 chapter 查表，不读关卡 JSON。

local MenuClusterCatalog = {}

local WORLD_BIT = 2

-- 颜色/grade 共用；高度雾由 Backdrop 按对齐后的包围盒底写入第一 tint 槽。
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

-- 菜单正交视野约 3.2。建筑铺在棱柱脚下偏后/两侧，不挡滚筒。
-- 各楼包围盒底由 Backdrop 对齐到同一世界高度，不再单独写 y。
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
---@field items table[]
---@field look table<string, string>
---@field viewMask number

---@type table<number, MenuClusterDefinition>
local CHAPTERS = {
    [3] = {
        id = "chapter3_city",
        items = CHAPTER_3_ITEMS,
        look = CITY_LOOK,
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
