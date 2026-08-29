# 关卡数据存储与真相源规范

## 落地状态

已闭环为存储职责规范。用户只通过 Editor UI 改关卡；工作区 `levels/` `parts/` 是 Git 基线，Preview 使用 Runtime 相对存档。三者不能混称为“当前关卡”。本规范不证明某次 Preview 一定读到了工作区文件。

用户导出是第四条通道：把当前内存关卡连同内联 Part 体素文档复制到**用户系统剪切板**。它不改 Runtime 存档，也不使用 VoxelSandbox 的项目体素复制缓冲。

关卡 JSON 还保存 `atmosphere`（LightGroup、tonemap、雾、Bloom、Vignette）；每个 Part 保存 `look`（shader 预设、Unlit 分面 Neg/Mid/Pos 与 lightAxis；两套预设都含 aoEnabled / aoColor / aoSmooth / aoBlend；高度雾预设另含 fogUp / fogColor / fogHeightA / fogHeightB）。这两项都由 Inspector 写入内存文档，再随保存/导出走同一条真相源。默认雾关闭（start=1000、density=0），tonemap 默认 `none`。默认 Part shader 是 `tri_prism_look`，默认开接触 AO。


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
- 当前默认关卡是 `levels/default-level.json` + `parts/part_part_9.json` / `parts/part_part_17.json`。缺失或损坏时由 `levels/starter-inline.json`（`docs/level.txt` 同源内联模板）恢复。

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

`StarterLevel` 在 Runtime 相对路径下找不到 Level 存档时创建初始关卡。如果现有关卡 JSON 损坏、无法解析，则先把坏档备份为 `levels/default-level.json.corrupt-*.bak`，再重建默认关卡，并用弹窗提示用户；不得因此中断启动。完好的用户关卡仍不得被默认关卡覆盖。

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
user clipboard export
```

前三者不能混为一个“当前关卡”。导出只复制当前内存关卡的内联 JSON，不写回 Runtime 存档。

## 用户导出

Editor UI 的“导出 JSON 到用户剪切板”生成一份单文件关卡：

```text
LevelDocument.ToTable()
  + 每个 Part.localVoxelDocument
  -> inline JSON
  -> 用户系统剪切板
```

规则：

- Runtime 保存仍拆成 `levels/*.json` + `parts/*.json`；
- 导出才把 Part 体素文档内联进 `parts[].localVoxelDocument`，并标记 `inlineParts = true`；
- 复制目标是引擎 `ui.useSystemClipboard = true` 后的系统剪切板；
- 禁止写入 `VoxelSandbox.clipboard`，那是项目内体素复制缓冲；
- 导出失败时不得假装已经复制成功。

导入是同一条用户通道的反向操作，但不能依赖 `ui:GetClipboardText()` 读取浏览器系统剪切板。WASM 下该 API 读到的是引擎内部剪贴板，导出能写出去，导入会读空。

```text
用户在导入弹窗中 Ctrl+V
  -> TextField 接收系统粘贴
  -> 内联 JSON
  -> 校验 Level + 每个 Part.localVoxelDocument
  -> 写入 Runtime 的 levels/*.json 与 parts/*.json
  -> 刷新当前编辑器
```

规则：

- 导出仍写用户系统剪切板；
- 导入必须经过输入框粘贴，不调用 `GetClipboardText()`；
- 不读取 `VoxelSandbox.clipboard`；
- Part 必须带 `localVoxelDocument`；静物走 `stillObjects[]`，不要求体素文档；
- 先在临时文档上校验，成功后再覆盖当前关卡；
- 导入后 Runtime 存档仍保持拆分。
