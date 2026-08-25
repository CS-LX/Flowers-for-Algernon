-- B 方案初始关卡工厂。
-- 只在关卡文件不存在时生成一个静态基座 Part 和一个 Rotator 塔 Part；
-- 已保存的关卡与局部体素资源永不由本模块覆盖。

local LevelDocument = require "LevelDocument"
local PartDefinition = require "PartDefinition"
local PartEditSession = require "PartEditSession"

local StarterLevel = {}

local LEVEL_PATH = "levels/default-level.json"

local function CreateStaticBaseSession(grid)
    local session = PartEditSession.New(grid, {
        id = "part_static_base",
        name = "静态基座",
        path = "parts/static-base.json",
    })

    for sector = 0, 5 do
        session.document:Set({
            hexQ = 0,
            hexR = 0,
            sector = sector,
            layer = 0,
            rotation = 0,
            material = sector + 1,
        })
    end
    session.document:Set({ hexQ = 1, hexR = 0, sector = 3, layer = 0, rotation = 0, material = 2 })
    session.document:Set({ hexQ = 0, hexR = 1, sector = 4, layer = 0, rotation = 0, material = 3 })
    session.document.dirty = true
    return session
end

local function CreateRotatorTowerSession(grid)
    local session = PartEditSession.New(grid, {
        id = "part_rotator_tower",
        name = "旋转塔",
        path = "parts/rotator-tower.json",
    })

    for layer = 0, 3 do
        for sector = 0, 5 do
            session.document:Set({
                hexQ = 0,
                hexR = 0,
                sector = sector,
                layer = layer,
                rotation = 0,
                material = (sector + layer) % 6 + 1,
            })
        end
    end
    session.document:Set({ hexQ = 1, hexR = 0, sector = 3, layer = 3, rotation = 0, material = 5 })
    session.document.dirty = true
    return session
end

local function SaveStarterPart(session)
    if fileSystem:FileExists(session.path) then
        return true
    end
    return session:Save()
end

function StarterLevel.LoadOrCreate(grid)
    local level = LevelDocument.New(LEVEL_PATH)
    if fileSystem:FileExists(LEVEL_PATH) then
        local loaded, errorMessage = level:Load()
        if loaded then
            return level
        end
        return nil, errorMessage
    end

    local baseSession = CreateStaticBaseSession(grid)
    local towerSession = CreateRotatorTowerSession(grid)
    local baseSaved, baseError = SaveStarterPart(baseSession)
    if not baseSaved then
        return nil, baseError
    end
    local towerSaved, towerError = SaveStarterPart(towerSession)
    if not towerSaved then
        return nil, towerError
    end

    level.name = "静态基座与旋转塔"
    level.fixedCamera = {
        projection = "orthographic",
        pitch = 30,
        yaw = 30,
        orthoSize = 12.0,
        nearClip = 0.1,
        farClip = 100.0,
        target = { x = 0, y = 1.2, z = 0 },
    }

    local baseAdded, baseAddError = level:AddPart(PartDefinition.New({
        id = baseSession.id,
        name = baseSession.name,
        localVoxelPath = baseSession.path,
        transform = {
            position = { x = 0, y = 0, z = 0 },
            rotation = { yawSteps = 0, pitchSteps = 0, rollSteps = 0 },
            scale = { x = 1, y = 1, z = 1 },
        },
        transformCapabilities = {
            move = true,
            rotate = true,
            scale = false,
        },
        behaviorModes = {},
        behaviors = {},
    }))
    if not baseAdded then
        return nil, baseAddError
    end

    local towerAdded, towerAddError = level:AddPart(PartDefinition.New({
        id = towerSession.id,
        name = towerSession.name,
        localVoxelPath = towerSession.path,
        pivot = {
            mode = "cell_center",
            cell = { hexQ = 0, hexR = 0, sector = 0, layer = 0 },
        },
        transform = {
            position = { x = 0, y = 0, z = 0 },
            rotation = { yawSteps = 0, pitchSteps = 0, rollSteps = 0 },
            scale = { x = 1, y = 1, z = 1 },
        },
        transformCapabilities = {
            move = true,
            rotate = true,
            scale = false,
        },
        behaviorModes = {
            PartDefinition.MODE_ROTATOR,
        },
        behaviors = {
            rotator = {
                state = 0,
                duration = 0.45,
                allowedSteps = { 0, 1, 2, 3, 4, 5 },
            },
        },
    }))
    if not towerAdded then
        return nil, towerAddError
    end

    local candidateAdded, candidateError = level:AddPathCandidate({
        id = "candidate_base_to_rotator",
        from = {
            partId = baseSession.id,
            nodeId = "static_base_top_0",
        },
        to = {
            partId = towerSession.id,
            nodeId = "rotator_tower_top_0",
        },
        kind = "visual_candidate",
        direction = "bidirectional",
        enabled = true,
    })
    if not candidateAdded then
        return nil, candidateError
    end

    local spawnSet, spawnError = level:SetSpawnNodeKey(
        baseSession.id .. ":static_base_top_0"
    )
    if not spawnSet then
        return nil, spawnError
    end

    local saved, saveError = level:Save()
    if not saved then
        return nil, saveError
    end
    print("Created starter level B: StaticBase + RotatorTower")
    return level
end

return StarterLevel
