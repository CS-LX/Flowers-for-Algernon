# 三棱柱体素关卡 Part 与预览工作流

## 目标

在保持三棱柱体素编辑精度与六边形错视基准的前提下，建立类似 Unity 的关卡物体树工作流：

```text
Level Object Tree
  -> Part
    -> 局部体素编辑
    -> 非破坏性 Mesh Bake
  -> Transform / Behavior
  -> 固定镜头 Preview
```

该工作流解决两个问题：

1. 不依赖外部建模软件，也能在 TapTap Maker 内搭建复杂的关卡建筑；
2. 避免单一全局体素世界无法自然表达平移、旋转、父子层级与机关组件的问题。

## 纪念碑谷式关卡原则

### 固定游戏镜头

游戏预览以固定的正交/轴测镜头为基准：

```text
projection = Orthographic
pitch = 30°
rotation = 固定的关卡设计角度
```

编辑器可以提供可旋转、可平移、可切换透视的辅助相机，但这不能取代游戏预览镜头。

纪念碑谷式错视依赖稳定投影。玩家的主要交互不是自由旋转相机，而是操作建筑中的旋转、滑动、升降、展开等组件，使路径在固定视角下形成新的视觉连接。

### 视觉连接与逻辑连接分离

```text
视觉重合 != 自动可通行
```

即使两个 Part 在固定镜头下视觉对齐，角色是否可以通过，仍由关卡逻辑图显式决定。

```text
Mechanism State
  -> Conditional Logic Edge
  -> Walkability
```

例如：

```text
RotatorTower.state == 2
  -> Edge(stair_1, bridge_3) enabled
```

## Part 是编辑与运行时边界

### 为什么不能只有全局体素文档

单一全局体素世界中的每一个单元都直接使用世界坐标：

```text
全局三棱柱体素
  -> 旋转需要重写全部格子坐标
  -> 平移需要重写全部格子坐标
  -> 缩放会破坏体素尺寸与网格对齐
  -> 动画需要持续修改正式文档
```

这不适合机关和可动建筑。

### Part 定义

每个 `Part` 是一个具有局部坐标系、局部体素源数据、Transform 和可选行为的关卡物件，概念上类似 Unity 的 `GameObject / Prefab Instance`。

```lua
{
    id = "part_rotator_tower",
    name = "旋转塔",
    type = "part",

    localVoxelDocument = {
        -- 该 Part 局部坐标系内的三棱柱体素
    },

    transform = {
        position = { x = 0, y = 0, z = 0 },
        rotationSteps = 0,
        scale = { x = 1, y = 1, z = 1 },
    },

    behavior = {
        type = "rotator",
        axis = "Y",
        allowedSteps = { 0, 1, 2, 3, 4, 5 },
        state = 0,
        duration = 0.45,
    },
}
```

## 双层编辑工作流

### 1. Object Tree / Level Editor

关卡总装层负责：

```text
- 创建、复制、删除 Part
- 物体树与父子层级
- 当前 Part 选择
- Part Transform
- Part 类型与机关参数
- 逻辑连接图
- 固定镜头 Preview
```

推荐层级：

```text
LevelRoot
├── StaticGeometry
│   ├── Part_Gate
│   └── Part_Stair
├── RotatorTower
├── MovingBridge
├── LogicGraph
└── FixedPreviewCamera
```

### 2. Part Voxel Editor

局部建模层复用现有三棱柱体素编辑器，负责：

```text
- 只编辑当前 Part 的 localVoxelDocument
- 使用局部三棱柱网格
- 放置、擦除、选择、变换局部体素
- 保存 Part 体素源数据
- 请求重新烘焙
- 返回 Object Tree
```

进入 Part 编辑模式相当于 Unity 的 Prefab Mode：

```text
Object Tree
  -> Open Part
  -> Part Voxel Editor
  -> Save / Bake
  -> Back to Object Tree
```

Part 编辑器不直接修改 Level 中其他 Part 的体素数据。

## 非破坏性烘焙

### 真相源规则

```text
Part.localVoxelDocument = 唯一可编辑真相源
BakedMesh = 可随时重新生成的派生缓存
Preview Node = 可销毁并重建的显示结果
```

禁止以下破坏性流程：

```text
体素编辑
  -> 转成最终 mesh
  -> 删除体素源数据
```

该流程会使后续局部编辑、组件边界恢复、逻辑调试与机关调整变得困难。

### 正确 Bake 流程

```text
Part Voxel Edit
  -> localVoxelDocument dirty
  -> BakePartMesh(part)
  -> 生成或替换 Part Root 下的 BakedMesh
  -> Preview 刷新
```

初版可以先保持每个体素一个渲染节点，并将其挂在 `PartRoot` 下，以先验证组件层级和机关行为。

Mesh 合并、可见面剔除、材质批处理是后续 Bake 优化，不应阻塞 Part 层级和 Preview 闭环。

## Transform 规则

### 可安全支持的 Transform

```text
平移：安全
绕 Y 轴按 60° 离散旋转：安全，符合六向规范
父子层级：安全
```

运行时只变更 Part Root，不改写局部体素源数据：

```lua
partRoot.position = runtimePosition
partRoot.rotation = Quaternion(rotationSteps * 60.0, Vector3.UP)
```

### 缩放规则

三棱柱规范依赖：

```text
a = 1.0m
h = 1 / sqrt(3)m
h = a * tan(30°)
```

任意非均匀缩放会破坏：

```text
- 六边形密铺
- 三棱柱比例
- 30° 投影对齐
- 错视连接基准
- 导航与视觉一致性
```

因此按 Part 类型限制缩放：

| Part 类型 | 平移 | 六向旋转 | 缩放 |
|---|---|---|---|
| Static / Decorative | 支持 | 支持 | 可支持任意缩放 |
| Gameplay Static | 支持 | 支持 | 默认 1,1,1；需显式确认 |
| Gameplay Moving | 支持 | 支持 | 初版禁用 |
| Illusion Connector | 支持 | 支持 | 必须 1,1,1 |

初版的可动玩法 Part 只支持：

```text
位移 + 60° 离散旋转
```

不支持缩放。

## Preview 模块

Preview 不是编辑器相机的另一种显示方式，而是游戏规则验证环境。

它负责：

```text
- 固定 30° 正交游戏相机
- 从 PartDefinition 创建 Preview Node Hierarchy
- 加载每个 Part 的 Bake 结果
- 执行 Part 的离散机关状态
- 计算并显示逻辑连接图
- 显示可通行节点、条件边与错视连接 Debug
```

Preview 节点建议：

```text
PreviewRoot
├── StaticGeometry
│   └── Static baked mesh
├── Components
│   ├── Rotator_Tower_A
│   │   ├── BakedMesh
│   │   ├── PivotGizmo
│   │   └── RotatorBehavior
│   ├── Slider_Bridge_B
│   │   ├── BakedMesh
│   │   └── SliderBehavior
│   └── Elevator_C
│       ├── BakedMesh
│       └── ElevatorBehavior
├── NavigationGraphDebug
└── FixedPreviewCamera
```

## 实施顺序

### 阶段 A：Level 与 Part 数据模型

```text
- LevelDocument
- PartDefinition
- Part localVoxelDocument
- Static / Rotator Part 类型
- Part 与体素集合的所有权
```

目标：明确哪些局部体素属于哪个 Part，而不更改现有三棱柱拓扑。

### 阶段 B：Object Tree Editor

```text
- Hierarchy 面板
- 创建 / 选择 / 删除 Part
- Open Part / Back to Level
- Part Inspector
- 平移与 60° 离散旋转
```

### 阶段 C：初版 Preview

```text
- 固定 30° 正交镜头
- Part Root 层级
- 用局部体素节点构成 Preview
- Rotator Part 按 60° 离散旋转
- Part 状态可切换
```

### 阶段 D：Logic Graph 与角色验证

```text
- Walk nodes
- Conditional edges
- 连接图 Debug
- 小角色寻路
- 机关状态改变后更新路径
```

### 阶段 E：Bake 优化

```text
- 按 Part 合并 mesh
- 可见面剔除
- 材质批处理
- dirty Part 增量重烘焙
- 运行时导出
```

## 最小验收闭环

```text
在 Object Tree 创建 Rotator Part
  -> 打开 Part Voxel Editor
  -> 用三棱柱体素搭出一座塔
  -> 返回 Object Tree
  -> 自动生成该 Part 的派生显示结果
  -> 固定 30° 正交 Preview
  -> 操作 Part 旋转 60°
  -> Preview 中塔以 Part Root 为中心旋转
  -> 局部体素源数据保持不变
```

完成该闭环后，再接入逻辑图和小角色寻路，验证纪念碑谷式错视连接。
