# 轻剧情对话系统实现计划

## 文档定位

本文把纪念碑谷式轻叙事接到当前关卡容器、演出导演和信号系统上。它是实现计划，不是文学大纲。

剧情文本、章节情绪和关卡线仍以 `docs/algernon-monument-valley-narrative-design.md` 为准。Path Graph、机关 Snap、固定相机和关卡 JSON 仍是玩法真相源。本文不改那些架构。

核心前提：

> 对话是演出层能力，不是第二套玩法系统。导演决定何时说话；JSON / Inspector 不存台词。

---

## 一、产品感觉

目标是纪念碑谷那种轻剧情：

- 句子短，不解释谜题
- 不做成独立 Galgame 状态机替代选关
- 全屏对话只出现在进关前和过关后的转场
- 关卡中只在触发或导演需要时出现底部条
- 玩家主要时间仍在观察建筑、拖机关、点路径

明确不做：

- 选项分支、好感度、语音（以后要再加字段）
- 在关卡 JSON / Inspector 配台词
- 用文本解释「旋转 = 变聪明」
- 过关立刻切关，把收尾剧情冲掉

---

## 二、职责分层

```text
LevelDirector（每关一份，写时机和序列名）
        ↓ PlayStory(lines, options)
StoryPlayer（打字、翻页、阻塞、完成回调）
        ↓
StoryView（fullscreen / banner / modal 三种外壳）
        ↓
LevelSession / GameApp（进关、过关、切下一关）
```

| 层 | 负责 | 不负责 |
|---|---|---|
| **StoryPlayer** | 打字机、点击继续、跳过当前句、队列、阻塞输入、完成回调 | 某关台词、进关/过关流程 |
| **StoryView** | 全屏图+字、底部条、必须点完的底部条 | 何时播 |
| **LevelDirector** | 这一关播哪段、何时播、播完干什么 | UI 控件实现 |
| **GameApp** | 过关后等导演说可以走，再切关或回选关 | 台词内容 |

和现有信号系统对齐：

- Trigger 仍只发 ID（例如 `level.finish`、`mouse_door`）
- 导演订阅后决定要不要说话
- 关卡 JSON 继续只存 Trigger ID，不存台词

对修改关闭、对扩展开放：新关只加 `scripts/Story/ChapterN.lua` 和导演登记，不改 `StoryPlayer`。

---

## 三、三种外壳

共用一套行数据，只换表现和输入策略。

| 模式 | 外观 | 输入 | 典型时机 |
|---|---|---|---|
| **fullscreen** | 全屏底图 + 打字 + 可选姓名 | 关卡输入锁死，点屏幕 / 空格继续 | 进关前、过关后转场 |
| **banner** | 画面下方半透明条 | 默认可玩；导演可选择阻塞 | 走路途中、看见阿尔吉侬 |
| **modal** | 底部条，必须点完 | 锁输入，打完再点才进下一句 | 触发器、关键揭示、过关句号 |

行结构（导演脚本或 Story 模块里写表，不进关卡 JSON）：

```lua
{
    id = "ch1.intro.1",
    speaker = "查理",      -- 可空，旁白
    text = "我想走到那扇门那里。",
    image = "Story/ch1_intro.png", -- 仅 fullscreen 使用；可空
    mode = "fullscreen",   -- 或 banner / modal
    typeSpeed = 28,        -- 字/秒
    blockInput = true,     -- banner 默认可 false；modal / fullscreen 必须 true
}
```

交互约定：

- 打字中再点一次：立刻出全句
- 打完再点：下一句
- Esc：只跳过当前序列，不退出关卡
- 退出关卡仍是「当前没有在播剧情」时的 Esc

`blockInput` 与模式的关系：

- fullscreen：始终阻塞
- modal：始终阻塞
- banner：默认可玩；导演可把该段或整段设为阻塞

---

## 四、关卡生命周期

当前 `level.finish +1` 会立刻弹出过关 HUD。轻剧情需要导演截住这一步。

```text
选关进入
  → Session Init（场景已在）
  → Director.OnStart
      可选 fullscreen / banner / modal
      再播现有地图升起等演出
      解锁玩法
  → 游玩中
      Subscribe(triggerId) 或导演主动 PlayStory
      → banner 或 modal
  → level.finish +1
      Session 标记 finished，锁玩法
      不立刻 ShowFinish
      交给 Director.OnFinish
          过关 fullscreen / banner / modal
          onComplete → GameApp 切下一关或回选关
```

`GameApp` 需要补两件很薄的事：

1. `EnterNextLevel()`：按 `LevelCatalog` 顺序进下一章；没有则回选关
2. 过关 HUD 变成可选句号。默认让导演决定「说完再走」

导演 API 保持很小：

```lua
self:PlayStory(lines, {
    onComplete = function() end,
})
self:StopStory()
self:IsStoryPlaying()
```

`lines` 可以是当场写的表，或 `require("Story.Chapter1").intro`。推荐后者：台词和时机分开。

建议目录：

```text
scripts/Story/Chapter1.lua
scripts/Story/Chapter2.lua
scripts/Story/Chapter3.lua
scripts/LevelDirectors/Chapter1.lua   -- 只写何时 PlayStory
```

---

## 五、五种用法能否实现

结论：**都能实现。** 它们是同一套 `PlayStory` 在不同生命周期上的调用，不是五套系统。

### 1. 进关全屏 Galgame 式剧情，结束后过渡到关卡

能。`OnStart` 先锁输入，播 `mode = "fullscreen"`。`onComplete` 再播地图升起或直接解锁。

当前缺口：还没有 `StoryPlayer` / 全屏 View。生命周期已经有 `OnStart`。

### 2. 关卡结束全屏剧情，结束后过渡到下一关或后续

能。`level.finish` 后不立刻弹 HUD，交给 `OnFinish` 播 fullscreen。`onComplete` 调 `EnterNextLevel()` 或回选关。

当前缺口：`GameApp` 现在在 `onFinish` 里直接 `ShowFinish()`，需要改成等导演收尾。还没有 `EnterNextLevel()`。

### 3. 进关、结束时的 banner，可选阻塞

能。同一套行数据，`mode = "banner"`。默认不锁走路和拖机关；该行或整段设 `blockInput = true` 就阻塞。

当前缺口：还没有底部条 View，以及「banner 不锁玩法」这条输入策略。

### 4. 进关、结束时的 modal，必须点完

能。`mode = "modal"` 固定 `blockInput = true`。打字中点击补全，打完再点下一句，序列结束才继续升起或切关。

当前缺口：modal 与 banner 共用底部条，只是输入策略不同。

### 5. Trigger 或导演触发的 banner / modal

能。Trigger 继续只发 ID。导演：

```lua
self:Subscribe("mouse_door", function()
    self:PlayStory(Story.Chapter1.algernonSeen)
end)
```

也可以在 `OnUpdate`、到达某 PathNode、升起结束回调里直接 `PlayStory`。不在 JSON 里写台词。

当前缺口：订阅 API 已有；缺的是 `PlayStory` 本身。

---

## 六、与现有代码的衔接

已有、可复用：

- `LevelSession` Init / Update / Dispose，以及 `level.finish` 订阅
- `LevelDirector.Extend()`、`Subscribe` / `Publish`、输入锁定、Part 位置 API
- `LevelDirectorCatalog` 按关卡 id 登记
- `RiderFollow`：进关升起时玩家跟着 Part
- Triggerable 只提供 ID，开火条件在物体代码里

需要新增：

- `scripts/StoryPlayer.lua`：队列、打字、点击、完成回调
- `scripts/StoryView.lua`：fullscreen 与底部条
- `LevelDirector:PlayStory` / `StopStory` / `IsStoryPlaying`
- `LevelDirector:OnFinish()`：默认空；有剧情的关覆盖它
- `GameApp:EnterNextLevel()`
- `GameApp` 过关不再无条件 `ShowFinish()`
- `scripts/Story/Chapter1.lua` 等台词模块

需要收敛的现有行为：

- `LevelSession:OnFinishSignal` 仍标记 `finished` 并锁玩家
- 是否立刻显示过关 HUD，改由导演 `OnFinish` 决定
- 第一章现有升起演出保留，插在开场剧情之后

---

## 七、实现顺序

1. 落地 `StoryPlayer` + fullscreen / banner / modal View
2. 接到 `LevelDirector:PlayStory`，并把 `level.finish` 交给 `OnFinish`
3. `GameApp:EnterNextLevel()`，过关默认等导演
4. 写第一章台词并接到 `Chapter1` 导演；第二章、第三章按需要建空导演只播剧情

试玩验收（第一章）：

```text
进关 fullscreen 一句
  → 地图升起
  → 走进门
  → 过关 fullscreen / modal
  → 进入第二章
```

关卡中的 trigger banner / modal 用现有 Trigger ID 另接，不和过关抢同一段序列。
