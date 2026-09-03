# 第一章剧情台词

润色时请保留每句的 `id`、`mode`、`style`。改完把这份文件还给我，我会按 id 导回 `scripts/Story/Chapter1.lua`。

- `mode=modal`：锁输入，必须点完
- `mode=banner`：底部条，默认可走
- `style=charlie`：查理
- `style=normal`：研究员等其他人，需要 `speaker`

---

## 1-1 门

### intro · 地图升起完成后

`id` 前缀：`ch1.1.intro`

1. `ch1.1.intro.1` · charlie · modal

这里是哪里？

2. `ch1.1.intro.2` · charlie · modal

我叫查理·戈登。我在面包店工作。

3. `ch1.1.intro.3` · charlie · modal

面包店和回家的路，我都记得。

4. `ch1.1.intro.4` · charlie · modal

这里的路，我不认识。为什么会在这里，我想不起来。

5. `ch1.1.intro.5` · charlie · modal

前面有一扇门。那边好像亮一点。

6. `ch1.1.intro.6` · charlie · modal

我先去看看。到了那里，也许就想起来了。

### inLevel · 玩家开始走后约 5 秒

`id` 前缀：`ch1.1.in_level`

1. `ch1.1.in_level.1` · charlie · banner

我好像来过这里。

2. `ch1.1.in_level.2` · charlie · banner

可是我想不起来。

3. `ch1.1.in_level.3` · charlie · banner

门还在前面。

### clear · 到达终点门

`id` 前缀：`ch1.1.clear`

1. `ch1.1.clear.1` · charlie · modal

我到了。

2. `ch1.1.clear.2` · charlie · modal

我还是想不起来。门后面一定有我忘记的东西。

---

## 1-2 白鼠先行

### intro · 进关后

`id` 前缀：`ch1.2.intro`

1. `ch1.2.intro.1` · charlie · modal

门后怎么还是这样？路又断了。

2. `ch1.2.intro.2` · charlie · modal

咦，这里有一只小白鼠。

3. `ch1.2.intro.3` · charlie · modal

那边怎么还有一扇门？

### mouse · 阿尔吉侬走到暗路入口后

`id` 前缀：`ch1.2.mouse`

1. `ch1.2.mouse.1` · charlie · modal

它怎么过去的？

2. `ch1.2.mouse.2` · charlie · modal

那里明明没有路。

### researcher · 老鼠段结束后

`id` 前缀：`ch1.2.researcher`

1. `ch1.2.researcher.1` · normal · 研究员 · modal

来，来这边吧。

2. `ch1.2.researcher.2` · normal · 研究员 · modal

走这条路过来。

### clear · 到达玩家门

`id` 前缀：`ch1.2.clear`

1. `ch1.2.clear.1` · charlie · modal

你是谁？我为什么在这里？

2. `ch1.2.clear.2` · normal · 研究员 · modal

我是研究员。你叫查理，是你自己来到这里的。

3. `ch1.2.clear.3` · normal · 研究员 · modal

你看不见那些不可能的路，所以来找我们。

---

## 1-3 另一种世界

### intro · 进关后

`id` 前缀：`ch1.3.intro`

1. `ch1.3.intro.1` · charlie · modal

怎么又是这样？路还是断的。

2. `ch1.3.intro.2` · charlie · modal

我记得刚才来过这里。可是现在看不懂了。

3. `ch1.3.intro.3` · normal · 研究员 · modal

到你所在路径的尽头。就是悬崖边。

### rotate · 玩家走到悬崖，建筑开始转

`id` 前缀：`ch1.3.rotate`

1. `ch1.3.rotate.1` · charlie · banner

它在动。这里原来不是这样的。

2. `ch1.3.rotate.2` · charlie · banner

那边……好像接上了。

### after_rotate · 转到位后

`id` 前缀：`ch1.3.after_rotate`

1. `ch1.3.after_rotate.1` · normal · 研究员 · modal

看，路接上了。现在走过来。

2. `ch1.3.after_rotate.2` · charlie · modal

我可以走过去了。

### clear · 到达终点

`id` 前缀：`ch1.3.clear`

1. `ch1.3.clear.1` · charlie · modal

你是谁？我为什么会在这里？

2. `ch1.3.clear.2` · normal · 研究员 · modal

我是研究员。你来到这里，是因为看不见这样的路。

3. `ch1.3.clear.3` · normal · 研究员 · modal

如果你接受手术，也许就能看见。以后，你可以自己让路出现。

4. `ch1.3.clear.4` · charlie · modal

我愿意。请让我试试。
