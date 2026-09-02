-- 三棱柱体素绘制器。
-- 第一版规范：等边三角形边长 a=1.0m，垂直高度 h=1/sqrt(3)m。
-- 当前绘制路径：CustomGeometry + 可选 Part look 材质覆盖。
-- AO 只画凹角/台阶缝：COLOR.rgb 是三条边的敞开度，UV 是重心坐标。
-- 共面缝和外凸角保持敞开，不涂接触暗。

local VoxelRenderer = {}

local SQRT3 = math.sqrt(3.0)
VoxelRenderer.DEFAULT_EDGE = 1.0
VoxelRenderer.DEFAULT_HEIGHT = 1.0 / SQRT3

local FACE_TOP = 1
local FACE_BOTTOM = 2
local FACE_SIDE_INNER = 3
local FACE_SIDE_OUTER = 4
local FACE_SIDE_NEXT = 5
local SIDE_FACES = { FACE_SIDE_INNER, FACE_SIDE_OUTER, FACE_SIDE_NEXT }

local function CreateMaterial(color)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.72))
    return material
end

local function OpenEdges()
    return {
        top = { 1.0, 1.0, 1.0 },
        bottom = { 1.0, 1.0, 1.0 },
        topCorners = { 1.0, 1.0, 1.0 },
        bottomCorners = { 1.0, 1.0, 1.0 },
        sides = {
            { 1.0, 1.0, 1.0, 1.0 },
            { 1.0, 1.0, 1.0, 1.0 },
            { 1.0, 1.0, 1.0, 1.0 },
        },
        sideCorners = {
            { 1.0, 1.0, 1.0, 1.0 },
            { 1.0, 1.0, 1.0, 1.0 },
            { 1.0, 1.0, 1.0, 1.0 },
        },
    }
end

local function Occupied(occupied, grid, cell)
    if not occupied or not cell then
        return false
    end
    return occupied(grid:NormalizeCell(cell)) == true
end

local function Neighbor(grid, cell, face, layer)
    if not grid or not cell or not face then
        return nil
    end
    local neighbor = grid:GetFaceNeighbor(cell, face)
    if not neighbor then
        return nil
    end
    neighbor.layer = layer
    return neighbor
end

local function Has(occupied, grid, cell, face, layer)
    return Occupied(occupied, grid, Neighbor(grid, cell, face, layer))
end

local function Openness(isCavity)
    if isCavity then
        return 0.0
    end
    return 1.0
end

-- 顶/底一条边：只有台阶（对角上层有、正上方没有）才是凹缝。
-- 正上方有体素是被挡住的面，不画；同层邻居是共面缝，不画。
local function HorizontalCavity(occupied, grid, cell, sideFace, above)
    local layer = cell.layer
    if above then
        if Has(occupied, grid, cell, FACE_TOP, layer + 1) then
            return false
        end
        return Has(occupied, grid, cell, sideFace, layer + 1)
    end
    if Has(occupied, grid, cell, FACE_BOTTOM, layer - 1) then
        return false
    end
    return Has(occupied, grid, cell, sideFace, layer - 1)
end

-- 侧面竖边：同层两侧都有才是内凹折角。单侧邻居是外凸，不画。
local function VerticalCavity(occupied, grid, cell, leftFace, rightFace)
    local layer = cell.layer
    return Has(occupied, grid, cell, leftFace, layer)
        and Has(occupied, grid, cell, rightFace, layer)
end

local INCIDENT_FACES = {
    { FACE_SIDE_INNER, FACE_SIDE_NEXT },
    { FACE_SIDE_INNER, FACE_SIDE_OUTER },
    { FACE_SIDE_OUTER, FACE_SIDE_NEXT },
}

local function SamePoint(a, b)
    if not a or not b then
        return false
    end
    local dx = a.x - b.x
    local dz = a.z - b.z
    return dx * dx + dz * dz < 0.00000001
end

-- 相邻三角只共顶点、不共边。本三角的胶囊到网格边就被裁成刀切，
-- 必须在那些相邻三角里给这个顶点补圆。
local function VertexNeedsCap(occupied, grid, cell, vertexIndex, above)
    local faces = INCIDENT_FACES[vertexIndex]
    if HorizontalCavity(occupied, grid, cell, faces[1], above)
        or HorizontalCavity(occupied, grid, cell, faces[2], above) then
        return false
    end
    local origin = grid:GetTriangleVertices(cell)[vertexIndex]
    local layer = cell.layer
    local hexes = { { q = cell.hexQ, r = cell.hexR } }
    for direction = 0, 5 do
        local neighborQ, neighborR = grid:GetHexNeighbor(cell.hexQ, cell.hexR, direction)
        hexes[#hexes + 1] = { q = neighborQ, r = neighborR }
    end
    for _, hex in ipairs(hexes) do
        for sector = 0, 5 do
            local candidate = {
                hexQ = hex.q,
                hexR = hex.r,
                sector = sector,
                layer = layer,
            }
            if Occupied(occupied, grid, candidate)
                and not (
                    candidate.hexQ == cell.hexQ
                    and candidate.hexR == cell.hexR
                    and candidate.sector == cell.sector
                ) then
                local verts = grid:GetTriangleVertices(candidate)
                for other = 1, 3 do
                    if SamePoint(verts[other], origin) then
                        local otherFaces = INCIDENT_FACES[other]
                        if HorizontalCavity(occupied, grid, candidate, otherFaces[1], above)
                            or HorizontalCavity(occupied, grid, candidate, otherFaces[2], above) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function VoxelRenderer.ComputeEdgeAO(grid, cell, occupied)
    if not grid or not cell or not occupied then
        return OpenEdges()
    end
    cell = grid:NormalizeCell(cell)
    local top = {
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_INNER, true)),
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_OUTER, true)),
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_NEXT, true)),
    }
    local bottom = {
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_INNER, false)),
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_OUTER, false)),
        Openness(HorizontalCavity(occupied, grid, cell, FACE_SIDE_NEXT, false)),
    }
    local topCorners = {}
    local bottomCorners = {}
    for vertex = 1, 3 do
        topCorners[vertex] = Openness(VertexNeedsCap(occupied, grid, cell, vertex, true))
        bottomCorners[vertex] = Openness(VertexNeedsCap(occupied, grid, cell, vertex, false))
    end
    local adjacent = {
        { FACE_SIDE_NEXT, FACE_SIDE_OUTER },
        { FACE_SIDE_INNER, FACE_SIDE_NEXT },
        { FACE_SIDE_OUTER, FACE_SIDE_INNER },
    }
    local sides = {}
    local sideCorners = {}
    for index = 1, 3 do
        local face = SIDE_FACES[index]
        local leftFace = adjacent[index][1]
        local rightFace = adjacent[index][2]
        -- 立面只画真正的竖向内凹。台阶顶/底边和顶面圆角都留在水平面上，
        -- 否则会从转角侧面“泄露”出一条水平暗带。
        sides[index] = {
            1.0,
            Openness(VerticalCavity(occupied, grid, cell, face, rightFace)),
            1.0,
            Openness(VerticalCavity(occupied, grid, cell, face, leftFace)),
        }
        sideCorners[index] = {
            1.0,
            1.0,
            1.0,
            1.0,
        }
    end
    return {
        top = top,
        bottom = bottom,
        topCorners = topCorners,
        bottomCorners = bottomCorners,
        sides = sides,
        sideCorners = sideCorners,
    }
end

local function PackCornerCaps(cornerA, cornerB, cornerC)
    local bits = 0
    if (cornerA or 1.0) < 0.5 then
        bits = bits + 1
    end
    if (cornerB or 1.0) < 0.5 then
        bits = bits + 2
    end
    if (cornerC or 1.0) < 0.5 then
        bits = bits + 4
    end
    return bits * (1.0 / 7.0)
end

local function AddVertex(geometry, position, normal, uv, color)
    geometry:DefineVertex(position)
    geometry:DefineNormal(normal)
    geometry:DefineColor(color)
    geometry:DefineTexCoord(uv)
end

-- UV.x / UV.y = 顶点 B / C 的重心坐标。
-- COLOR.rgb = 对边 BC / CA / AB 的敞开度。
-- COLOR.a 打包三个顶点圆角位，三顶点同值，避免插值搅在一起。
local function AddTriangle(geometry, a, b, c, normal, edgeBC, edgeCA, edgeAB, cornerA, cornerB, cornerC)
    local color = Color(edgeBC, edgeCA, edgeAB, PackCornerCaps(cornerA, cornerB, cornerC))
    AddVertex(geometry, a, normal, Vector2(0.0, 0.0), color)
    AddVertex(geometry, b, normal, Vector2(1.0, 0.0), color)
    AddVertex(geometry, c, normal, Vector2(0.0, 1.0), color)
end

local function AddPrismFace(geometry, a, b, bottomY, topY, sideAO, sideCorners)
    local edge = b - a
    local normal = Vector3(-edge.z, 0, edge.x):Normalized()
    local bottomA = Vector3(a.x, bottomY, a.z)
    local bottomB = Vector3(b.x, bottomY, b.z)
    local topB = Vector3(b.x, topY, b.z)
    local topA = Vector3(a.x, topY, a.z)
    local bottomOpen = sideAO[1]
    local rightOpen = sideAO[2]
    local topOpen = sideAO[3]
    local leftOpen = sideAO[4]
    local cornerBottomA = sideCorners[1]
    local cornerBottomB = sideCorners[2]
    local cornerTopB = sideCorners[3]
    local cornerTopA = sideCorners[4]

    AddTriangle(geometry, bottomA, bottomB, topB, normal, rightOpen, 1.0, bottomOpen, cornerBottomA, cornerBottomB, cornerTopB)
    AddTriangle(geometry, bottomA, topB, topA, normal, topOpen, leftOpen, 1.0, cornerBottomA, cornerTopB, cornerTopA)
end

local function PopulatePrismGeometry(geometry, edgeLength, height, ao)
    ao = ao or OpenEdges()
    geometry:SetNumGeometries(1)
    geometry:BeginGeometry(0, TRIANGLE_LIST)

    -- 局部三角形：points[1] 是朝向局部 -X 的中心顶点，
    -- points[2]/points[3] 构成外侧边。旋转并平移后可无缝拼成六边形。
    local radius = edgeLength / SQRT3
    local points = {
        Vector3(-radius, 0, 0),
        Vector3(radius * 0.5, 0, edgeLength * 0.5),
        Vector3(radius * 0.5, 0, -edgeLength * 0.5),
    }
    local bottomY = -height * 0.5
    local topY = height * 0.5

    AddTriangle(
        geometry,
        Vector3(points[1].x, topY, points[1].z),
        Vector3(points[2].x, topY, points[2].z),
        Vector3(points[3].x, topY, points[3].z),
        Vector3(0, 1, 0),
        ao.top[2],
        ao.top[3],
        ao.top[1],
        ao.topCorners[1],
        ao.topCorners[2],
        ao.topCorners[3]
    )
    AddTriangle(
        geometry,
        Vector3(points[1].x, bottomY, points[1].z),
        Vector3(points[3].x, bottomY, points[3].z),
        Vector3(points[2].x, bottomY, points[2].z),
        Vector3(0, -1, 0),
        ao.bottom[2],
        ao.bottom[1],
        ao.bottom[3],
        ao.bottomCorners[1],
        ao.bottomCorners[3],
        ao.bottomCorners[2]
    )

    AddPrismFace(geometry, points[1], points[2], bottomY, topY, ao.sides[1], ao.sideCorners[1])
    AddPrismFace(geometry, points[2], points[3], bottomY, topY, ao.sides[2], ao.sideCorners[2])
    AddPrismFace(geometry, points[3], points[1], bottomY, topY, ao.sides[3], ao.sideCorners[3])

    geometry:Commit()
end

function VoxelRenderer.CreateMaterial(color)
    return CreateMaterial(color)
end

function VoxelRenderer.CreateVoxel(scene, gridPosition, color, options)
    options = options or {}

    local edgeLength = options.edgeLength or VoxelRenderer.DEFAULT_EDGE
    local height = options.height or VoxelRenderer.DEFAULT_HEIGHT
    local nodeName = options.name or "TriangularPrismVoxel"
    local ao = VoxelRenderer.ComputeEdgeAO(options.grid, options.cell, options.occupied)

    local parent = options.parent or scene
    local node = parent:CreateChild(nodeName)
    node.position = gridPosition
    node.rotation = options.rotation or Quaternion()

    local customGeometry = node:CreateComponent("CustomGeometry")
    PopulatePrismGeometry(customGeometry, edgeLength, height, ao)
    customGeometry:SetMaterial(options.material or CreateMaterial(color))

    return node
end

function VoxelRenderer.CreateHexagonOfVoxels(scene, center, colors, options)
    options = options or {}
    local edgeLength = options.edgeLength or VoxelRenderer.DEFAULT_EDGE
    local height = options.height or VoxelRenderer.DEFAULT_HEIGHT
    local centerOffset = edgeLength / SQRT3
    local voxels = {}

    for i = 1, 6 do
        local angle = (i - 1) * math.pi / 3.0
        local position = center + Vector3(
            math.cos(angle) * centerOffset,
            height * 0.5,
            -math.sin(angle) * centerOffset
        )
        local color = colors[i]
        local rotation = Quaternion(angle * 180.0 / math.pi, Vector3.UP)
        voxels[i] = VoxelRenderer.CreateVoxel(scene, position, color, {
            parent = options.parent,
            edgeLength = edgeLength,
            height = height,
            rotation = rotation,
            name = "HexVoxel_" .. i,
            material = options.material,
        })
    end

    return voxels
end

return VoxelRenderer
