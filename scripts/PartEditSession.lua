-- Part 局部体素编辑会话。
-- 该会话是 Object Tree 将来打开一个 Part 时传给 Part Voxel Editor 的边界；
-- 它持有局部体素文档与存储路径，但不持有关卡层级、场景节点或 Bake 缓存。

local VoxelDocument = require "VoxelDocument"

local PartEditSession = {}
PartEditSession.__index = PartEditSession

local function CreateStarterCells()
    return {
        { hexQ = 0, hexR = 0, sector = 0, layer = 0, rotation = 0, material = 1 },
        { hexQ = 0, hexR = 0, sector = 1, layer = 0, rotation = 0, material = 2 },
        { hexQ = 0, hexR = 0, sector = 2, layer = 0, rotation = 0, material = 3 },
        { hexQ = 0, hexR = 0, sector = 3, layer = 0, rotation = 0, material = 4 },
        { hexQ = 0, hexR = 0, sector = 4, layer = 0, rotation = 0, material = 5 },
        { hexQ = 0, hexR = 0, sector = 5, layer = 0, rotation = 0, material = 6 },
        { hexQ = 1, hexR = 0, sector = 3, layer = 0, rotation = 0, material = 2 },
        { hexQ = 0, hexR = 1, sector = 4, layer = 0, rotation = 0, material = 3 },
        { hexQ = 0, hexR = 0, sector = 0, layer = 1, rotation = 0, material = 2 },
    }
end

function PartEditSession.New(grid, options)
    options = options or {}

    local self = setmetatable({}, PartEditSession)
    self.id = options.id or "part_default"
    self.name = options.name or "默认 Part"
    self.path = options.path or "parts/default-part.json"
    self.document = options.document or VoxelDocument.New(grid, self.path)
    self.document.path = self.path
    return self
end

function PartEditSession.Open(grid, part)
    local session = PartEditSession.New(grid, {
        id = part.id,
        name = part.name,
        path = part.localVoxelPath,
    })
    if type(part.runtimeVoxelDocument) == "table" then
        local loaded, errorMessage = session.document:LoadTable(part.runtimeVoxelDocument)
        if not loaded then
            return nil, errorMessage
        end
        return session
    end
    local loaded, errorMessage = session:Load()
    if not loaded then
        return nil, errorMessage
    end
    return session
end

function PartEditSession.CreateStarter(grid)
    local session = PartEditSession.New(grid, {
        id = "part_default",
        name = "默认 Part",
        path = "parts/default-part.json",
    })

    for _, cell in ipairs(CreateStarterCells()) do
        session.document:Set(cell)
    end
    session.document.dirty = false
    return session
end

function PartEditSession:GetDisplayName()
    return self.name .. " [" .. self.id .. "]"
end

function PartEditSession:Save()
    local directory = self.path:match("^(.*)/[^/]+$")
    if directory and directory ~= "" then
        fileSystem:CreateDir(directory)
    end
    return self.document:Save(self.path)
end

function PartEditSession:Load()
    return self.document:Load(self.path)
end

return PartEditSession
