# 关卡数据存储与真相源规范

## 目的

明确工作区初始资源、Preview Runtime 持久化存档和 Editor UI 的职责，避免把不同存储空间中的关卡误认为同一份数据。

## 用户编辑入口

用户没有直接编辑 JSON 的能力。关卡内容只能通过游戏内 Editor UI 修改：

```text
LevelEditorUI
VoxelSandbox / EditorUI
  -> LevelDocument / VoxelDocument
  -> Editor UI 的保存操作
  -> Runtime 当前存档
```

手工修改 JSON 不是用户工作流，也不能作为关卡测试步骤。

## 存储层级

### 工作区初始资源

```text
/workspace/levels/
/workspace/parts/
```

定位：

- 项目开发时的初始关卡/Part 资源；
- 本地代码分析和新环境回退创建的输入；
- Git 中可追踪的开发基线。

限制：

- 不自动等于当前 Preview Runtime 正在使用的存档；
- 不代表用户通过 Preview Editor UI 修改后的最新关卡；
- 在没有确认 Runtime 资源根和存档路径前，禁止用它推断 Preview 当前 Part、PathNode 或候选数量。

### Preview Runtime 持久化存档

Preview Runtime 使用相对路径加载和保存：

```text
levels/default-level.json
parts/*.json
```

这些相对路径由 Runtime 的项目挂载根/可写存档空间解析。它可能与 `/workspace/levels`、`/workspace/parts` 不在同一文件系统目录。

定位：

- 用户通过游戏 Editor UI 实际修改后的关卡真相源；
- Preview 刷新或重新启动后继续加载的持久化数据；
- 运行时测试、Gizmo、PathRuntime 和 UI 统计应以它为准。

## 数据源判断规则

当工作区文件与 Preview 画面不一致时，优先级如下：

```text
用户 Preview 中 Editor UI 的当前状态
  > Runtime 启动日志和运行时统计
  > 已确认的 Runtime 存档路径
  > /workspace/levels 与 /workspace/parts 初始资源
```

在 Runtime 实际路径未被诊断日志确认前，不得声称：

```text
Preview 加载了 /workspace/levels/default-level.json
```

只能说：

```text
Preview 使用了相对路径 levels/default-level.json，实际根目录尚未确认
```

## 构建规则

构建配置中的资源目录必须明确区分：

```text
初始资源是否进入构建包
Runtime 存档是否由 Preview 持久化系统提供
```

即使 `/workspace/levels` 或 `/workspace/parts` 没有被当前构建资产目录扫描，也不能据此断定 Preview 没有对应数据；Preview 可能从 Runtime 存档空间加载同名相对路径。

反之，也不能因为工作区存在这些文件，就断定 Preview 正在使用它们。

## 诊断要求

任何涉及关卡、Part、PathNode 或候选数量的调试，Runtime 必须输出：

```text
Level 实际解析路径/存储标识（若 Runtime API 可提供）
Level 名称
Part ID、名称和 localVoxelPath
每个 Part 加载到的 PathNode 数量和 ID
pathCandidates 数量和 ID
PathRuntime 总节点数、边数和 topologyVersion
```

如果无法获取绝对存储路径，必须明确输出：

```text
当前使用的是 Runtime 相对存档根，绝对路径不可见
```

不能用工作区 JSON 的统计冒充 Runtime 统计。

## StarterLevel 回退边界

`StarterLevel` 只在 Runtime 相对路径下找不到 Level 存档时创建初始关卡。它不应覆盖已存在的 Runtime 存档，也不应被用来重置用户通过 UI 创建的关卡。

工作区的 `/workspace/levels` 和 `/workspace/parts` 只作为初始资源基线；删除它们或强制覆盖它们都可能触发错误回退，不能作为清理幽灵存档的办法。

## 当前项目结论

当前已确认：

- 工作区存在一份初始关卡 JSON；
- Preview 通过相对路径加载/保存；
- 两者是否指向同一物理文件，需要 Runtime 诊断确认；
- 用户看到的 Preview 数据优先于未经路径确认的工作区文件统计。

后续所有路径系统开发和验证，必须先区分：

```text
workspace baseline
Runtime current save
in-memory unsaved editor state
```

三者不能混为一个“当前关卡”。
