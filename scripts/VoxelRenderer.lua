-- 三棱柱体素绘制器
-- 第一版规范：等边三角形边长 a=1.0m，垂直高度 h=1/sqrt(3)m。

local VoxelRenderer = {}

local SQRT3 = math.sqrt(3.0)
VoxelRenderer.DEFAULT_EDGE = 1.0
VoxelRenderer.DEFAULT_HEIGHT = 1.0 / SQRT3

local function CreateMaterial(color)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.72))
    return material
end

local function AddVertex(geometry, position, normal, uv)
    geometry:DefineVertex(position)
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(uv)
end

local function AddTriangle(geometry, a, b, c, normal)
    AddVertex(geometry, a, normal, Vector2(0.0, 0.0))
    AddVertex(geometry, b, normal, Vector2(1.0, 0.0))
    AddVertex(geometry, c, normal, Vector2(0.5, 1.0))
end

local function AddPrismFace(geometry, a, b, bottomY, topY)
    local edge = b - a
    local normal = Vector3(-edge.z, 0, edge.x):Normalized()
    local bottomA = Vector3(a.x, bottomY, a.z)
    local bottomB = Vector3(b.x, bottomY, b.z)
    local topB = Vector3(b.x, topY, b.z)
    local topA = Vector3(a.x, topY, a.z)

    AddTriangle(geometry, bottomA, bottomB, topB, normal)
    AddTriangle(geometry, bottomA, topB, topA, normal)
end

local function PopulatePrismGeometry(geometry, edgeLength, height)
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

    -- 顶面使用三个棱柱顶点，底面使用反向绕序。
    AddTriangle(
        geometry,
        Vector3(points[1].x, topY, points[1].z),
        Vector3(points[2].x, topY, points[2].z),
        Vector3(points[3].x, topY, points[3].z),
        Vector3(0, 1, 0)
    )
    AddTriangle(
        geometry,
        Vector3(points[1].x, bottomY, points[1].z),
        Vector3(points[3].x, bottomY, points[3].z),
        Vector3(points[2].x, bottomY, points[2].z),
        Vector3(0, -1, 0)
    )

    AddPrismFace(geometry, points[1], points[2], bottomY, topY)
    AddPrismFace(geometry, points[2], points[3], bottomY, topY)
    AddPrismFace(geometry, points[3], points[1], bottomY, topY)

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

    local parent = options.parent or scene
    local node = parent:CreateChild(nodeName)
    node.position = gridPosition
    node.rotation = options.rotation or Quaternion()

    local customGeometry = node:CreateComponent("CustomGeometry")
    PopulatePrismGeometry(customGeometry, edgeLength, height)
    customGeometry:SetMaterial(CreateMaterial(color))

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
            edgeLength = edgeLength,
            height = height,
            rotation = rotation,
            name = "HexVoxel_" .. i,
        })
    end

    return voxels
end

return VoxelRenderer
