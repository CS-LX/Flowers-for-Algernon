# 纪念碑谷式 Path Graph 与视差连接调研

### 6. 跨 Part 面视觉邻接规范

跨 Part 候选连接不应只比较两个节点中心点。两个候选节点所附着的面及其道路边，必须在各自 Part Transform 后使用固定游戏相机投影，并评估：

- 投影道路边的连续性；
- 投影行走方向；
- 相机深度关系；
- 遮挡；
- 当前机关合法 Snap 状态。

真实面不要求共面或相接；跨 Part 视觉邻接是将 Part 内的面/边连续性思想应用到固定相机的视觉空间。详细规则见：

```text
docs/cross-part-face-visual-adjacency-spec.md
```


本项目采用以下职责边界：

```text
PartVoxelDocument.pathNodes
  -> 路径节点的唯一持久化源数据

PartRuntime
  -> 根据 Part 当前 Transform 派生局部节点的世界锚点、法线与方向

PathRuntime
  -> 建立临时全局索引，评估连接，维护当前有效 Graph

BFS / Character
  -> 只消费 PathRuntime 暴露的当前有效 Graph

LevelDocument
  -> 保存 Part、层级、固定游戏相机和关卡组合；不复制或拥有 PathNode
```

**关键修正：** 整张关卡需要统一寻路视图，不意味着节点必须迁移或复制到 `LevelDocument`。`VoxelDocument.pathNodes` 继续是节点几何锚点和局部通行语义的唯一真相源；`PathRuntime` 只在运行时按 `partId:localNodeId` 建立索引和有效连接缓存。

这样避免两份节点数据不同步，并保留 Part 作为编辑、变换和机关影响范围的边界。

## 项目目标

本项目不是手写条件边模拟纪念碑谷，而是验证以下闭环：

```text
固定正交相机
  + Part 局部可走面节点
  + 机关合法 Snap 状态
  -> 当前有效 Path Graph
  -> BFS
  -> 小人自动行走
```

错视连接的第一版必须受关卡候选范围约束，不对任意几何体做无约束自动连边：

```text
候选局部节点对
  + 固定游戏相机投影、深度、方向与边界连续性
  -> 接受或拒绝当前临时连接
```

显式条件边仅用于固定连接、白盒临时兜底、设计者覆盖或 Debug 对照，不能替代视觉连接评估成为长期主架构。

## 公开 Unity 实现对照

以下仓库均作为只读 Git submodule 收录到 `references/`，便于后续查验源码；它们是工程参考，不是本项目运行时依赖。

| 仓库 | 子模块位置 | 有价值的参考 |
|---|---|---|
| [RodrigoHamuy/impossible-geometry](https://github.com/RodrigoHamuy/impossible-geometry) | `references/impossible-geometry` | 可走对象拥有局部 PathContainer；机关 Snap 后范围化刷新 PathPoint；固定相机投影参与邻居判断。 |
| [eliemichel/MonumentValley](https://github.com/eliemichel/MonumentValley) | `references/monument-valley-unity` | 节点附着场景可走对象；固定邻居和条件邻居分布式存储；BFS 在角色控制器中读取当前有效邻居。 |

另行审阅、但未作为子模块引入的对照实现：

- [GameDevCatch/Monument-Valley-Like-Pathfinding](https://github.com/GameDevCatch/Monument-Valley-Like-Pathfinding)：每个 Walkable 自身持有显式邻接；适合白盒固定边参考。
- [KunKard/MonumentValley-Remake](https://github.com/KunKard/MonumentValley-Remake)：Manager 开关预配置边；可作为“设计者覆盖”的反例，不可作为自动错视连接主架构。

### `impossible-geometry`：Part 局部节点与 Snap 后局部刷新

相关源码：

- `references/impossible-geometry/Assets/script/components/PointsContainerComponent.cs`
- `references/impossible-geometry/Assets/script/model/PathContainer.cs`
- `references/impossible-geometry/Assets/script/components/rotate/RotateController.cs`
- `references/impossible-geometry/Assets/script/controller/PathFinder.cs`
- `references/impossible-geometry/Assets/script/utility/Utility.cs`

它将 `PointsContainerComponent` 挂在可走 Mesh 对象上，一个 `PathContainer` 保存该对象的局部 `PathPoint`。旋转控制器在旋转完成时通知自身子树中的容器；容器删除旧点，并从变换后的 Mesh 重新生成点。寻路时则通过固定相机的屏幕投影、Raycast、遮挡和高度规则即时求邻居。

可借鉴的原则：

```text
Part / 可走对象拥有节点
机关 Snap 完成后仅使受影响的 Part 路径数据失效
视觉评估由固定游戏相机参与
```

不直接照搬的部分：它没有独立、可完整 Debug 的当前有效 Graph；其寻路过程即时查询场景并计算邻居。我们保留局部节点所有权，但加入 `PathRuntime` 的派生有效 Graph，确保 BFS 和 Debug 都读取同一份运行时结果。

### `eliemichel/MonumentValley`：分布式节点与条件邻居

相关源码：

- `references/monument-valley-unity/Assets/Scripts/NavigationCorner.cs`
- `references/monument-valley-unity/Assets/Scripts/ConditionalNeighbor.cs`
- `references/monument-valley-unity/Assets/Scripts/HandleController.cs`
- `references/monument-valley-unity/Assets/Scripts/CharacController.cs`

`NavigationCorner` 直接挂在场景对象上，并拥有固定 `neighbors`。同对象的 `ConditionalNeighbor` 在读取邻居时，根据手柄 Transform 当前角度决定是否附加条件邻居；角色的 BFS 直接遍历该结果。

可借鉴的原则：

```text
节点和局部固定连接可以去中心化地属于可走对象
统一的寻路入口不等于统一持久化节点所有权
```

不直接照搬的部分：它把旋转角度和连接有效性直接耦合为手写条件边，并在拖动期间重算角色路径；本项目要求只在合法 Snap 完成后提交拓扑，且错视边以视觉评估为主。

## 节点和 Graph 的正确边界

### 1. 节点：Part 局部、持久化、唯一真相源

一个 `PathNode` 继续附着在 `VoxelDocument` 的局部 Cell/Face：

```lua
{
    id = "entry_01",
    voxelCell = { hexQ = 0, hexR = 0, layer = 0, sector = 2 },
    face = "top",
    kind = "floor",
    walkable = true,
    orientation = 0,
    entryDirection = "...",
    exitDirection = "...",
}
```

它表达的是“该 Part 内哪个可走面能够成为路径节点”。局部 ID 必须在所属 Part 内稳定；全局运行时键由 `partId .. ":" .. localNodeId` 派生，不复制同一节点数据。

`partId` 不应作为第二份权威归属数据：节点的所属 Part 已由其所在 `VoxelDocument` 和 `PartDefinition.localVoxelPath` 决定。若保留 `partId` 仅作为冗余校验字段，必须由保存链路一致维护，而不能让它成为新的真相源。

### 2. PartRuntime：计算派生空间数据

Part 的旋转不改写局部 Cell/Face。`PartRuntime` 通过当前 Part Transform 派生：

```text
局部 Cell/Face + Part 当前 Transform
  -> 世界锚点
  -> 世界法线
  -> 面方向
  -> 固定相机投影与深度
```

对于本项目的三棱柱 Cell/Face 节点，旋转 Snap 后无需像从 Mesh 采样节点的实现那样销毁和重建节点；节点仍是同一局部实体，只需重新计算其派生空间信息。

### 3. PathRuntime：集中查询，不集中拥有

`PathRuntime` 不是 LevelDocument，也不序列化节点。它负责：

```text
收集每个 Part 的局部 PathNode
  -> 建立 temporary globalNodeIndex
  -> 解析局部固定连接和关卡候选连接
  -> 使用固定游戏相机评估候选错视连接
  -> 生成 CurrentEffectiveGraph
  -> 输出稳定的 BFS 结果和 Debug 诊断
```

`CurrentEffectiveGraph` 是运行时派生缓存：

```text
NodeKey                  = partId:localNodeId
EffectiveEdge            = 当前有效的 NodeKey 对
TopologyVersion          = 每次合法拓扑提交递增
EvaluationDiagnostics    = 接受/拒绝原因、投影与深度数据
```

它是寻路的唯一输入，但不是新的持久化节点真相源。

### 4. LevelDocument：仅保存组合关系和关卡配置

`LevelDocument` 继续负责：

- Part 集合、父子层级与顺序；
- Part Transform 和行为配置；
- 固定游戏相机；
- 关卡持久化；
- 必要的跨 Part 候选连接配置、固定边或设计者覆盖。

其中跨 Part 配置只引用局部节点键，例如：

```lua
{
    from = "part_static_base:start_01",
    to = "part_rotator_tower:entry_01",
    rule = "visual_candidate",
}
```

它不复制 `cell`、`face`、`kind` 等 PathNode 定义。

## 机关、Snap 与拓扑刷新

### 机关控制器职责

机关运行时控制器仅负责：

```text
接收交互
  -> 播放旋转表现
  -> 对齐合法 60° Snap
  -> 提交离散 rotatorStep
  -> 发出 SnapCompleted(partId, affectedPartIds)
```

它不做 BFS，不保存全局边，也不通过浮点旋转角直接定义玩法拓扑。

### PathRuntime 职责

`PathRuntime` 订阅 `SnapCompleted`，在该边界执行：

```text
标记受影响 Part 的运行时投影数据失效
  -> 重新派生这些 Part 的节点世界锚点
  -> 重评估相关视觉连接候选
  -> 原子替换 CurrentEffectiveGraph
  -> topologyVersion += 1
```

旋转动画中保持上一份合法 Graph：

```text
Animating
  -> 更新 PartRoot 表现层
  -> CurrentEffectiveGraph 不变

SnapCompleted
  -> 提交状态、刷新派生数据、替换 Graph
```

角色移动与机关动画互斥，避免角色读取半旋转状态。

## 连接类别

### 局部固定连接

由同一 Part 的局部节点语义或局部邻接产生。它们可由 PathRuntime 在收集该 Part 节点后建立，不需要复制到 LevelDocument。

### 跨 Part 固定连接

由 LevelDocument 的关卡组合配置引用局部节点键；例如永久桥梁或白盒连接。

### 跨 Part 视觉候选连接

由 LevelDocument 配置候选节点对及评估规则，但有效性只能由运行时固定相机评估产生：

```text
候选局部节点对
  + 当前 Part Transform
  + 当前机关 Snap 状态
  + 固定游戏相机
  -> EffectiveEdge / RejectedDiagnostic
```

### 设计者覆盖

显式条件边仅限固定连接、白盒兜底、特殊语义和 Debug 对照，不成为错视连接的主来源。

## 第一版最小实施计划

1. 保留 `VoxelDocument.pathNodes` 为节点唯一持久化源，确保局部 ID 稳定。
2. 引入 `PathRuntime`，只建立 `partId:localNodeId` 的临时索引；不新增 `LevelDocument.pathNodes`。
3. 先从 Part 局部语义和少量跨 Part 固定候选构建最小 `CurrentEffectiveGraph`。
4. 在该 Graph 上实现稳定 BFS，证明跨 Part 可达与不可达查询。
5. 让运行时 Rotator 在 Snap 完成后通知 `PathRuntime` 刷新受影响节点的派生位置与连接。
6. 将固定游戏相机投影、方向、深度和边界连续性加入受约束候选边评估。
7. 将节点、有效边、拒绝边、评估原因、`rotatorStep`、`topologyVersion` 和 BFS 路径接入 Debug Overlay。
8. 最后才接入白盒角色点击移动。

## 必须保持的约束

- PathNode 不因全局寻路而迁移或复制到 `LevelDocument`。
- `PathRuntime` 不拥有节点持久化数据；它只保存派生索引和当前有效连接。
- BFS 不读取 Mesh、Scene Node、物理碰撞或编辑器自由相机。
- 错视边不由世界距离自动创建，不由手写 `rotatorStep == n` 长期分支主导。
- 视觉评估只用固定游戏相机，并且只在机关完成合法 Snap 后刷新。
- 编辑器自由相机、Preview 表现和 Debug Overlay 都不能反向定义玩法连接。

## 调研边界

公开资料不足以确认官方纪念碑谷的具体 Graph 格式、寻路算法、深度排序数据结构或完整连接生成算法。本文记录的是公开陈述、公开 Unity 复刻源码和本项目工程约束共同支持的实现决策，不是官方源码的反向还原。
