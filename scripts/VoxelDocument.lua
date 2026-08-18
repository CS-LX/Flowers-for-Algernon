-- Part 局部三棱柱体素文档与 JSON 持久化。
-- 文档是一个 Part 的正式数据真相源；渲染节点、预览和历史都依赖它。

local VoxelDocument = {}
VoxelDocument.__index = VoxelDocument

local FORMAT_VERSION = 2

local function CopyCell(cell)
    if not cell then
        return nil
    end
    return {
        hexQ = cell.hexQ,
        hexR = cell.hexR,
        sector = cell.sector,
        layer = cell.layer,
        rotation = cell.rotation,
        material = cell.material,
    }
end

function VoxelDocument.New(grid, path)
    local self = setmetatable({}, VoxelDocument)
    self.grid = grid
    self.version = FORMAT_VERSION
    self.path = path or "parts/default-part.json"
    self.cells = {}
    self.materials = {
        { r = 242, g = 75, b = 85, a = 255 },
        { r = 250, g = 148, b = 52, a = 255 },
        { r = 242, g = 222, b = 55, a = 255 },
        { r = 90, g = 199, b = 97, a = 255 },
        { r = 61, g = 166, b = 235, a = 255 },
        { r = 158, g = 97, b = 224, a = 255 },
    }
    self.camera = {
        yaw = 0,
        pitch = 30,
        distance = 15,
        focusX = 0,
        focusY = 0,
        focusZ = 0,
        projection = "orthographic",
        orthoSize = 10,
        fov = 45,
    }
    self.dirty = false
    return self
end

function VoxelDocument:Key(cell)
    return self.grid:CellKey(cell)
end

function VoxelDocument:Get(cell)
    if not cell then
        return nil
    end
    return self.cells[self:Key(cell)]
end

function VoxelDocument:Set(cell)
    local normalized = self.grid:NormalizeCell(cell)
    if not self.grid:IsValid(normalized) then
        return nil
    end
    local copy = CopyCell(normalized)
    self.cells[self:Key(copy)] = copy
    self.dirty = true
    return copy
end

function VoxelDocument:Remove(cell)
    if not cell then
        return nil
    end
    local normalized = self.grid:NormalizeCell(cell)
    local key = self:Key(normalized)
    local previous = self.cells[key]
    if previous then
        self.cells[key] = nil
        self.dirty = true
    end
    return previous
end

function VoxelDocument:Clear()
    self.cells = {}
    self.dirty = true
end

function VoxelDocument:ForEach(callback)
    for _, cell in pairs(self.cells) do
        callback(cell)
    end
end

function VoxelDocument:Count()
    local count = 0
    for _ in pairs(self.cells) do
        count = count + 1
    end
    return count
end

function VoxelDocument:ApplyChanges(changes)
    for _, change in ipairs(changes or {}) do
        if change.after then
            self:Set(change.after)
        elseif change.before then
            self:Remove(change.before)
        end
    end
end

function VoxelDocument:ToTable()
    local cells = {}
    self:ForEach(function(cell)
        cells[#cells + 1] = CopyCell(cell)
    end)
    table.sort(cells, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.hexR ~= b.hexR then return a.hexR < b.hexR end
        if a.hexQ ~= b.hexQ then return a.hexQ < b.hexQ end
        return a.sector < b.sector
    end)

    return {
        format = "tri-prism-voxel-document",
        version = FORMAT_VERSION,
        grid = {
            edgeLength = self.grid.edgeLength,
            voxelHeight = self.grid.voxelHeight,
            packing = "hexagonal_tiling_six_triangular_sectors",
            coordinate = "axial_hex_qr_sector_layer",
        },
        materials = self.materials,
        cells = cells,
        camera = self.camera,
    }
end

function VoxelDocument:LoadTable(data)
    if type(data) ~= "table" or type(data.cells) ~= "table" then
        return false, "invalid document"
    end
    if data.format and data.format ~= "tri-prism-voxel-document" then
        return false, "unsupported document format"
    end

    self.cells = {}
    if type(data.materials) == "table" then
        self.materials = data.materials
    end
    if type(data.camera) == "table" then
        self.camera = data.camera
    end

    for _, cell in ipairs(data.cells) do
        if cell.hexQ ~= nil and cell.hexR ~= nil and cell.sector ~= nil and cell.layer ~= nil then
            self:Set(cell)
        end
    end
    self.dirty = false
    return true
end

function VoxelDocument:Save(path)
    path = path or self.path
    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then
        return false, "cannot open save file"
    end
    file:WriteLine(cjson.encode(self:ToTable()))
    file:Close()
    self.path = path
    self.dirty = false
    return true
end

function VoxelDocument:Load(path)
    path = path or self.path
    if not fileSystem:FileExists(path) then
        return false, "save file does not exist"
    end

    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        return false, "cannot open save file"
    end
    local text = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, text)
    if not ok then
        return false, "invalid JSON"
    end
    local loaded, errorMessage = self:LoadTable(data)
    if loaded then
        self.path = path
    end
    return loaded, errorMessage
end

function VoxelDocument:CloneTable()
    local data = self:ToTable()
    local ok, clone = pcall(cjson.decode, cjson.encode(data))
    if ok then
        return clone
    end
    return data
end

return VoxelDocument
