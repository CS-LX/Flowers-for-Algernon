# 第二章剧情台词

润色时请保留每句的 `id`、`mode`、`style`。改完把这份文件还给我，我会按 id 导回 `scripts/Story/Chapter2.lua`。

- `mode=modal`：锁输入，必须点完
- `mode=banner`：底部条，默认不阻塞玩法并自动结束
- `style=charlie`：查理
- `style=researcher`：研究员，需要 `speaker`
- 第二章只使用查理和研究员两个声部，不加入第三者旁白

---

## 2-1 研究室

### surgery · 进关后、阿尔吉侬出现前

`id` 前缀：`ch2.1.surgery`

1. `ch2.1.surgery.1` · researcher · 研究员 · modal

手术已经完成了。先看看周围。

2. `ch2.1.surgery.2` · charlie · modal

好像没有什么不同。可是……这里看起来清楚多了。

### after_mouse · 阿尔吉侬到达终点并消失后

`id` 前缀：`ch2.1.after_mouse`

1. `ch2.1.after_mouse.1` · charlie · modal

诶，刚刚那个不是阿尔吉侬吗？

2. `ch2.1.after_mouse.2` · charlie · modal

它朝门过去了。那我也跟过去看看。

### praise · 查理到达终点门后、地图旋转前

`id` 前缀：`ch2.1.praise`

1. `ch2.1.praise.1` · researcher · 研究员 · modal

很好。你刚才走过了一条不存在的路径。

2. `ch2.1.praise.2` · charlie · modal

不存在？有吗？

### reveal · 地图完成 360° 旋转后

`id` 前缀：`ch2.1.reveal`

1. `ch2.1.reveal.1` · researcher · 研究员 · modal

现在看到了吗？刚才那条路，在现实里并不存在。

2. `ch2.1.reveal.2` · researcher · 研究员 · modal

手术之后，你也能看见这样的路径了。

3. `ch2.1.reveal.3` · charlie · modal

我看见了。我成功了！

---

## 2-2 远处的房间

### control_intro · 进关后

`id` 前缀：`ch2.2.control_intro`

1. `ch2.2.control_intro.1` · researcher · 研究员 · modal

现在的你，已经拥有了常人无法拥有的能力。

2. `ch2.2.control_intro.2` · researcher · 研究员 · modal

阿尔吉侬已经跨过悬崖，在终点前面等着你了。试着操控这座建筑。

3. `ch2.2.control_intro.3` · researcher · 研究员 · modal

把注意力停在路径结构上。看，它正在发光——那是它在回应你的操作。

4. `ch2.2.control_intro.4` · charlie · modal

我试试看……让这条路，变成我能走的样子。

### control_start · 查理开始进入可旋转路径

`id` 前缀：`ch2.2.control_start`

1. `ch2.2.control_start.1` · charlie · banner

我做到了！我不仅能走上看不见的路径，还能让它出现！

### clear · 查理到达终点门

`id` 前缀：`ch2.2.clear`

1. `ch2.2.clear.1` · researcher · 研究员 · modal

非常好。效果很好。你已经学会操控路径结构了。

2. `ch2.2.clear.2` · charlie · modal

原来这就是我能做到的事……我还想看更多。

### 2-2 润色约束

- 本关把原著中查理“异于常人的智力”转译为两层能力：能走过不存在的路径，以及能创造不存在的路径。
- 前者对应他获得了正常人拥有的理解能力，后者对应他进一步表现出超常能力。
- 当前台词还没有完整引导“悬停结构 → 按下 → 拖动 / 转动”的操作链。
- 润色时需要补足操作引导，但不能直接说“鼠标”“点击”“按住”等元叙事词。
- 当前世界内表达是：查理把注意力停在结构上，结构发光作为回应；还需要自然引导他进一步“抓住 / 推动 / 转动”结构。

---

## 2-3 两座塔之间

### ch2_3_intro · 进关后

`id` 前缀：`ch2.3.intro`

1. `ch2.3.intro.1` · researcher · 研究员 · modal

这里是阿尔吉侬做寻路测试的地方。它以前很快就通过了。

2. `ch2.3.intro.2` · researcher · 研究员 · modal

不过，走通一条路只是开始。真正重要的是，你能不能理解道路为什么会出现。

3. `ch2.3.intro.3` · charlie · modal

我和阿尔吉侬一起试试。也许我能找到自己的路。

### charlie_first · 查理先于阿尔吉侬到达终点

`id` 前缀：`ch2.3.charlie_first`

1. `ch2.3.charlie_first.1` · researcher · 研究员 · modal

很好。你先一步走到了这里。手术后的变化，比预期还要明显。

2. `ch2.3.charlie_first.2` · charlie · modal

我只是顺着看见的路走过来了。原来我真的能做到。

### algernon_first_banner · 阿尔吉侬先到终点并消失

`id` 前缀：`ch2.3.algernon_first.banner`

1. `ch2.3.algernon_first.banner` · charlie · banner

阿尔吉侬好快！它已经到终点了。

### algernon_first · 阿尔吉侬先到，随后查理也到达终点

`id` 前缀：`ch2.3.algernon_first`

1. `ch2.3.algernon_first.1` · researcher · 研究员 · modal

别急，慢慢来。阿尔吉侬熟悉这里的结构，但你正在学会理解它。

2. `ch2.3.algernon_first.2` · charlie · modal

我明白了。它走过的路，可以告诉我该看哪里，但我要自己找到下一步。

3. `ch2.3.algernon_first.3` · researcher · 研究员 · modal

正是这样。你不是在追赶它，你是在形成自己的判断。

### 2-3 润色约束

- 这是术后能力的暗中对照测试，但研究员不能直接说“正在进行术后功效对照测试”。
- 研究员应通过“阿尔吉侬以前很快通过”“你正在形成自己的判断”等话里有话的表达观察结果。
- 阿尔吉侬先到的分支不能讽刺、贬低或阴阳查理，也不能写成查理输掉比赛。
- 查理先到时可以肯定能力提升，但不要写成夸张的胜负宣告。

---

## 2-4 高处的窗

### ch2_4_intro · 进关后

`id` 前缀：`ch2.4.intro`

1. `ch2.4.intro.1` · researcher · 研究员 · modal

你已经学会看见道路，也学会让道路出现。

2. `ch2.4.intro.2` · researcher · 研究员 · modal

最高处的那扇门，是离开实验室的出口。

3. `ch2.4.intro.3` · researcher · 研究员 · modal

你可以留下，继续在这里接受测试；也可以走出去。由你自己决定。

4. `ch2.4.intro.4` · charlie · modal

我想出去。我想看看，外面的路现在是什么样。

### ch2_4_path · 查理开始前往 Lift 上的出口

`id` 前缀：`ch2.4.path`

1. `ch2.4.path.1` · charlie · banner

我知道该怎么走了。

### ch2_4_lift_begin · 查理到达 Lift，开始上升

`id` 前缀：`ch2.4.lift_begin`

1. `ch2.4.lift_begin.1` · charlie · banner

它在动……这是要带我去哪儿？

2. `ch2.4.lift_begin.2` · researcher · 研究员 · banner

出去看看吧，查理。

### ch2_4_farewell · Lift 停稳，第二章配色已转为第三章配色

`id` 前缀：`ch2.4.farewell`

1. `ch2.4.farewell.1` · researcher · 研究员 · modal

接下来的路，你自己走。

2. `ch2.4.farewell.2` · charlie · modal

嗯。我自己走。

### 2-4 待润色补充

当前正式台词已经交代查理可以留下或离开，并由查理主动选择离开；但还没有解释阿尔吉侬为什么没有随 Lift 一起离开。

建议在去留选择中补入以下意思，可修改措辞，但不要改变因果：

```text
查理：那阿尔吉侬呢？
研究员：它还要留在这里，完成剩下的观察。
查理：那我先出去。不过……我还会回来看看它。
```

设计原因：

- 阿尔吉侬没有跟随 Lift 不是遗漏，而是它仍作为实验对象留在研究所。
- 必须承认查理与阿尔吉侬在此暂时分别，避免玩家认为剧情遗忘了阿尔吉侬。
- 建立查理会主动回来找它的承诺，为第三章回访和发现阿尔吉侬衰退提供动机。
- 为查理最终把阿尔吉侬带出实验室、沿真实道路到墓前送花建立完整因果链。
- 形成前后对照：2-4 是查理第一次为自己选择离开；后续由他替阿尔吉侬完成离开。

---

## 润色时不要做的事

- 不要增加第三者旁白；只保留查理和研究员两个声部。
- 不要把研究员写成向玩家朗读机制说明书。
- 不要直接使用“鼠标”“点击”“按住”“拖动”等出戏词汇。
- 不要把“旋转机关”等同于“变聪明”，也不要加入智力值、等级或技能树措辞。
- 不要让 2-1 的查理在地图旋转揭示真相前，就意识到自己正在走不存在的路径。
- 不要让 2-3 变成查理和阿尔吉侬的竞速比赛。
- 不要删除 2-3 的两套先后到达分支。
- 不要让阿尔吉侬在 2-4 跟随 Lift 离开实验室。
- banner 保持短，避免玩家边走、边转建筑或边看 Lift 上升时来不及阅读。
