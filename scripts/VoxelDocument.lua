-- 三棱柱体素文档与 JSON 持久化。
-- 文档是编辑器真相源，场景节点和合并网格都由文档重建。

local VoxelDocument = {}
VoxelDocument.__index = VoxelDocument

local FORMAT_VERSION = 1

local function CopyCell(cell)
    return {
        i = cell.i,
        j = cell.j,
        parity = cell.parity,
        layer = cell.layer,
        rotation = cell.rotation,
        material = cell.material,
    }
end

local function CellKey(i, j, parity, layer)
    return tostring(i) .. ":" .. tostring(j) .. ":" .. tostring(parity) .. ":" .. tostring(layer)
end

function VoxelDocument.New(grid)
    local self = setmetatable({}, VoxelDocument)
    self.grid = grid
    self.version = FORMAT_VERSION
    self.path = "tri_voxel_sandbox.json"
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

function VoxelDocument:Key(i, j, parity, layer)
    return CellKey(i, j, parity, layer)
end

function VoxelDocument:Get(i, j, parity, layer)
    return self.cells[CellKey(i, j, parity, layer)]
end

function VoxelDocument:Set(cell)
    local copy = CopyCell(cell)
    copy.parity = copy.parity % 2
    copy.rotation = copy.rotation % 3
    self.cells[CellKey(copy.i, copy.j, copy.parity, copy.layer)] = copy
    self.dirty = true
    return copy
end

function VoxelDocument:Remove(i, j, parity, layer)
    local key = CellKey(i, j, parity, layer)
    local cell = self.cells[key]
    if cell then
        self.cells[key] = nil
        self.dirty = true
    end
    return cell
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

function VoxelDocument:ToTable()
    local cells = {}
    self:ForEach(function(cell)
        cells[#cells + 1] = CopyCell(cell)
    end)
    table.sort(cells, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.j ~= b.j then return a.j < b.j end
        if a.i ~= b.i then return a.i < b.i end
        return a.parity < b.parity
    end)

    return {
        format = "tri-prism-voxel-document",
        version = FORMAT_VERSION,
        grid = {
            edgeLength = self.grid.edgeLength,
            voxelHeight = self.grid.voxelHeight,
            packing = "triangular_tiling_extrusion",
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

    self.cells = {}
    if type(data.materials) == "table" then
        self.materials = data.materials
    end
    if type(data.camera) == "table" then
        self.camera = data.camera
    end

    for _, cell in ipairs(data.cells) do
        if cell.i and cell.j and cell.parity and cell.layer then
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
    file:WriteString(cjson.encode(self:ToTable()))
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
