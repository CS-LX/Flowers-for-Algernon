# 纪念碑谷式 Path Graph 与视差连接调研

## 结论摘要

本项目的目标架构不是手写条件边模拟纪念碑谷，而是向成熟的纪念碑谷式工作流看齐：

```text
关卡配置可走面节点与机关
  -> 机关到达合法 Snap 状态
  -> 固定游戏相机下评估节点的视觉连接
  -> 生成当前有效 Path Graph
  -> BFS / 后续寻路消费 Path Graph
```

其中 Path Graph 仍是运行时寻路的唯一输入和玩法真相，但 Graph 的错视连接应由以下信息共同生成：

- 可走面节点配置；
- 节点所属 Part 和机关；
- 机关合法 Snap 状态；
- 固定游戏相机；
- 节点投影、深度、遮挡、方向和边界连续性评估。

显式条件边不再是错视连接的目标架构，只保留为固定连接、临时白盒兜底、设计者特殊覆盖或 Debug 对照。它不能替代视觉连接评估，也不能因为官方算法细节未公开而升级为长期主要配置方式。

```text
真实空间中不连续
  + 固定相机投影下的深度压缩、边缘对齐和遮挡关系
  = 视觉上连续的错觉路径
```

视觉连接评估的第一版范围不是对任意几何体做无约束自动连边，而是：在关卡配置提供的可走面节点和连接候选范围内，使用固定游戏相机、机关合法 Snap 状态以及投影/深度/遮挡/方向规则生成当前有效连接。

## 证据等级

本文将资料分成三类：

- **A：开发者公开陈述**，可作为纪念碑谷路径设计原则的直接依据；
- **B：公开研究或第三方分析**，可辅助理解视觉机制，但不代表官方内部实现；
- **C：仿作、社区和工程推断**，只能作为设计参考，不能写成官方事实。

## A 级：开发者公开陈述

### 1. 导航节点位于可行走空间

Game Developer 对 ustwo 技术总监 Peter Pashley 的技术分享记录了：纪念碑谷的导航节点分布在物体的可行走空间上，而不是简单依赖传统的“节点网络”。公开引文为：

> “Monument Valley's nodes were dotted across the objects' walkable spaces.”

这意味着节点更接近“可行走表面上的逻辑位置”，而不是 NavMesh 三角形或单纯的场景节点树。

对本项目的直接影响：

- 每个可走 tile 应有独立的逻辑 node ID；
- 节点可以映射到三棱柱 Cell 或 Part 内的局部位置；
- 视觉模型不能成为可达性真相源；
- 逻辑节点应能脱离 Scene 和 Mesh 单独调试。

### 2. 节点存在可达和不可达状态

公开资料还明确提到，开发团队可以将导航节点标记为 accessible 或 inaccessible；特定几何配置下，Ida 能到达的区域会以高亮节点和高亮路径表现出来。

公开引文包括：

> “UsTwo could also mark up navigation nodes as accessible or inaccessible.”

以及：

> “that path of highlights shifts if the geometry shifts.”

对本项目的直接影响：

- Graph 应区分“已声明节点”和“当前可达节点”；
- 机关状态变化后，重新计算当前有效边和可达性；
- Debug 层应显示有效边、关闭边和当前 BFS 路径；
- 高亮路径是逻辑状态的表现，不是逻辑状态本身。

### 3. 节点可以在同一位置表达不同通行语义

公开文章用“同一位置存在两个节点”的例子说明：一个节点可以表示梯子，另一个节点可以表示地面。公开引文为：

> “The solution is to have two nodes, basically in exactly the same place, one as a ladder and one as a floor.”

这说明一个世界坐标不能简单等同于一个玩法节点。节点还需要携带通行语义、方向或类型。

对本项目的直接影响：

```lua
{
    id = "tower_ladder_01",
    grid = { q = 0, r = 0, layer = 1, sector = 2 },
    kind = "ladder",
    walkable = true,
}
```

同一位置可以有：

```text
floor node
ladder node
rotator entry node
rotator exit node
```

它们是否连接，应由显式 Edge 和机关状态决定，不能只用距离判断。

### 4. 连接判断与游戏相机的深度顺序有关

公开技术描述指出，自动连接处理会：

1. 按游戏相机的深度顺序排列节点；
2. 按该顺序遍历节点；
3. 判断前后节点之间的遮挡关系。

公开引文为：

> “it involves ordering those nodes in depth order from the game camera, and then going through them in depth order and deciding which ones should occlude the ones that are in front or behind.”

这不是“相机旋转来找路径”，而是固定游戏视角参与判断视觉上的前后关系。

对本项目的直接影响：

- 游戏相机必须保持固定正交投影和固定设计角度；
- 如果未来实现投影候选边，应使用游戏相机，而不是编辑器自由相机；
- 深度排序可以用于验证或筛选候选连接；
- 深度排序结果不能直接绕过关卡数据创建最终玩法边。

### 5. 连接只在合法 snap 状态下重算

公开技术描述指出，连接决策只在几何体处于指定 snap position 时进行，而不是在旋转过程的每个浮点角度持续判断。

公开引文为：

> “We ended up only making those decision points when the geometry was in one of the snap positions.”

同时提到只在特定时间和特定配置下重新计算连接。

对本项目的直接影响：

```text
旋转动画中
  -> 只更新表现层
  -> 不提交新的逻辑拓扑

旋转到合法离散状态并完成动画
  -> 提交 rotatorStep
  -> 原子重算条件边
  -> 更新 topologyVersion
```

这与本项目的六向状态 `0..5`、每步 `60°` 完全一致。

## B 级：视觉错视与关卡工作流

### 1. 固定投影是错视的基础

公开研究和第三方技术分析普遍将纪念碑谷的视觉基础描述为固定的等距/正交式视图。不同资料对具体角度和术语存在差异，因此本项目不把第三方的具体角度数字当作官方内部参数。

本项目已有明确的工程规范：

```text
projection = orthographic
pitch = 30°
yaw = 30°
```

该规范来自：

```text
docs/voxel-spec.md
```

### 2. 错视连接依赖投影结果，不等于真实空间连接

在固定正交视图下，以下情况是可能的：

```text
World A 与 World B 不相邻
Screen A 与 Screen B 的边缘、方向和高度关系看起来连续
```

因此，视觉连接和逻辑连接必须分开：

```text
视觉层：显示道路是否对齐
逻辑层：决定角色是否允许通过
```

不能因为两个模型在屏幕上重合，就自动给 Graph 增加一条边。否则会把纪念碑谷的“视觉重合 != 逻辑可通行”变成不可控的自动碰撞系统。

### 3. 白盒优先，再做美术完善

公开开发流程资料显示，关卡会先以白盒和功能验证为主，再进入视觉完善阶段。对本项目的直接意义是：

```text
先验证节点、边、机关状态和路径
再验证三棱柱边缘的投影对齐
最后再做成品美术
```

## C 级：仿作和社区资料能说明什么

公开仿作和教程可以确认“节点 + 显式连接 + 机关状态”的工程模式很常见，但本次调研没有获得足够可复核的源码内容，不能确认某个仿作具体使用了：

- `Walkable.cs` 的确切字段；
- `possiblePaths` 的完整配置格式；
- BFS、A* 或 Dijkstra 的具体选择；
- 官方或仿作的实际 JSON / XML / ScriptableObject 结构；
- 官方完整的自动投影连边代码。

因此以下内容只能作为本项目的工程设计，不应写成“纪念碑谷官方实现”：

```text
可走面节点配置
固定游戏相机下的视觉连接评估
机关 Snap 状态完成后的 Graph 重建
BFS 查询 nodeId 路径
topologyVersion
logicalNodeId 到视觉对象的映射
```

其中“自动评估视觉连接”是本项目向成熟工作流看齐的目标架构，不是对官方未公开源码的声称。

## 本项目采用的 Path Graph 方案

### 1. 节点是逻辑真相

建议节点包含：

```lua
{
    id = "rotator_exit",

    grid = {
        q = 1,
        r = 0,
        layer = 0,
        sector = 2,
    },

    kind = "floor",
    walkable = true,

    visual = {
        partId = "part_rotator_tower",
        cellKey = "0:0:2:0",
    },
}
```

`grid`、`kind`、`walkable` 和 `id` 属于逻辑数据。`visual` 是映射信息。世界坐标应由 Grid、Part Transform 和当前机关状态派生，不应作为唯一逻辑真相。

### 2. 连接由配置范围和视觉评估共同产生

固定连接可以由关卡直接配置；错视连接不应把 `rotatorStep == 1` 写成一组长期维护的手工分支。推荐的运行时流程是：

```text
关卡配置的可走面节点与连接候选范围
  + 当前机关 Snap 状态
  + 固定游戏相机
  -> 视觉连接评估
  -> 当前有效 Path Graph
```

评估可以使用：

- 节点和可走面的屏幕投影；
- 入口/出口方向；
- 投影边界的连续性和容差；
- 相机深度顺序；
- 遮挡关系；
- 节点类型和通行语义。

Graph 保存当前状态下的有效边以及可解释的评估结果。显式边只能作为固定连接、白盒兜底、设计者覆盖或 Debug 对照。

### 3. 机关状态改变后原子更新拓扑

```text
rotator 动画开始
  -> 只更新表现层
  -> Path Graph 保持上一合法状态

rotator 动画完成并到达 Snap 状态
  -> 提交离散机关状态
  -> 使用固定游戏相机重新评估视觉连接
  -> 原子重建当前有效 Path Graph
  -> topologyVersion += 1
```

角色移动与机关旋转互斥，避免角色读取半旋转状态下的路径。

### 4. 关卡配置的职责

关卡设计者配置的是：

- 可走面节点；
- 节点的面类型、方向和入口/出口语义；
- 节点所属 Part 和机关；
- 机关允许的离散 Snap 状态；
- 视觉连接评估所需的候选范围和规则参数；
- 必要的固定连接或明确覆盖。

设计者不应为每一个机关状态手写全部错视边。这样才能让几何状态变化驱动连接评估，保持纪念碑谷式工作流。

### 5. 第一版寻路使用 BFS

BFS 不是对官方算法的声称，而是本项目对当前有效 Path Graph 的最小寻路实现选择。

```text
输入：当前有效 Path Graph、startNodeId、goalNodeId
输出：稳定的 nodeId 路径或不可达
```

寻路层不读取：

- Mesh；
- Scene Node；
- 物理碰撞；
- 编辑器相机；
- 三棱柱几何细节。

### 6. 视差评估是连接生成的一部分

未来的视觉连接评估器应遵循：

```text
关卡配置的候选节点对
  -> 固定游戏相机投影
  -> 节点深度排序、方向、遮挡和边界连续性检查
  -> 生成或拒绝当前有效边
```

评估器可以：

- 生成满足规则的错视连接；
- 标记声明的固定连接可能不满足视觉对齐；
- 在 Debug 层显示投影线、深度顺序和拒绝原因。

评估器不能：

- 对任意模型距离自动创建玩法边；
- 使用编辑器自由相机决定游戏路径；
- 在旋转动画中途修改 Graph；
- 让 BFS、角色或物理碰撞反向定义连接。

## 推荐实施顺序

```text
1. WalkNode 数据结构
2. 可走面语义和入口/出口定义
3. 机关与合法 Snap 状态
4. 视觉连接评估输入与规则
5. 固定游戏相机下的投影、深度和遮挡评估
6. 当前有效 Path Graph 重建与 topologyVersion
7. 节点、边、评估结果和路径 Debug
8. BFS 与可达性查询
9. 旋转机关运行时状态提交
10. 角色沿 nodeId 路径移动
```

先完成 1-7，就能独立验证纪念碑谷式 Path Graph 是否正确；BFS 和角色只是之后消费 Graph 的客户端。

## 调研边界与未确认事项

目前没有公开证据足以确认：

- Monument Valley 官方使用的具体寻路算法；
- 官方 Path Graph 的实际序列化格式；
- 官方是否将所有边预定义，还是在 snap 状态下自动生成部分连接；
- 官方深度排序的具体数据结构和遮挡算法；
- 官方角色跨空间连接时的完整内部移动实现；
- 公开仿作仓库中某个具体项目的完整 Path Graph 源码配置。

本项目不需要等待这些未知细节才能继续。当前应以公开可确认的设计原则为依据，以可走面节点、固定相机视觉连接评估、机关 Snap 状态和当前有效 Path Graph 完成自己的可复现技术验证；BFS 只作为后续 Graph 消费者。

## 参考来源

- Peter Pashley / ustwo 技术分享，Game Developer：
  [Making the Impossible Possible in Monument Valley](https://www.gamedeveloper.com/design/making-the-impossible-possible-in-i-monument-valley-i-)
- Ken Wong，GDC Vault：
  [Designing Monument Valley: Less Game, More Experience](https://gdcvault.com/play/1020878/Designing-Monument-Valley-Less-Game)
- ustwo / Unity：
  [Monument Valley 3: Blurring Art and Design](https://unity.com/resources/monument-valley-3-blurring-art-and-design)
- 本项目三棱柱体素规范：
  `docs/voxel-spec.md`
- 本项目技术验证计划：
  `docs/plans/hexagonal-monument-valley-technical-validation.md`

---

**文档定位：** 本文是 Path Graph 设计调研和本项目工程决策记录，不是 Monument Valley 官方源码的反向还原。