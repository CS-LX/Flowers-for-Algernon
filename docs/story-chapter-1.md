# 第一章剧情台词

润色时请保留每句的 `id`、`mode`、`style`。改完把这份文件还给我，我会按 id 导回 `scripts/Story/Chapter1.lua`。

- `mode=modal`：锁输入，必须点完
- `mode=banner`：底部条，默认可走
- `style=charlie`：查理
- `style=researcher`：研究员等其他人，需要 `speaker`

---

## 1-1 雾中盲途

### intro · 地图升起完成后

`id` 前缀：`ch1.1.intro`

1. `ch1.1.intro.1` · charlie · modal

奇怪……这里是哪里？

2. `ch1.1.intro.2` · charlie · modal

我是谁，我怎么会在这里呢……

3. `ch1.1.intro.3` · charlie · modal

这整座迷宫……到底是什么地方？

4. `ch1.1.intro.4` · charlie · modal

算了，想不起来。那边好像有一扇门，在发光。

5. `ch1.1.intro.5` · charlie · modal

也许过去就能离开这儿了。

### inLevel · 玩家开始走后约 5 秒

`id` 前缀：`ch1.1.in_level`

1. `ch1.1.in_level.1` · charlie · banner

这里的路，还有这些建筑……我好像在哪见过。

2. `ch1.1.in_level.2` · charlie · banner

可脑子里一片空白，什么也记不起。

3. `ch1.1.in_level.3` · charlie · banner

算了，门就在前面，先过去再说。

### clear · 到达终点门

`id` 前缀：`ch1.1.clear`

1. `ch1.1.clear.1` · charlie · modal

这扇门……好像勾起了一些模糊的印象。

2. `ch1.1.clear.2` · charlie · modal

推开看看吧，说不定门后有答案。

---

## 1-2 虚空足迹

### intro · 进关后

`id` 前缀：`ch1.2.intro`

1. `ch1.2.intro.1` · charlie · modal

门后居然还是这样的建筑？而且前面的路……怎么断开了？

2. `ch1.2.intro.2` · charlie · modal

诶，小鼠！

3. `ch1.2.intro.3` · charlie · modal

小鼠鼠！我来找你玩玩来咯！

### mouse · 阿尔吉侬走到暗路入口后

`id` 前缀：`ch1.2.mouse`

1. `ch1.2.mouse.1` · charlie · modal

别跑啊！诶等等，它是怎么走过去的？！

2. `ch1.2.mouse.2` · charlie · modal

那片空中……明明什么都没有啊。

### researcher · 老鼠段结束后

`id` 前缀：`ch1.2.researcher`

1. `ch1.2.researcher.1` · researcher · 研究员 · modal

来吧，往这边走，沿着路过来。

### clear · 到达玩家门

`id` 前缀：`ch1.2.clear`

1. `ch1.2.clear.1` · charlie · modal
你……是谁？我怎么会在这里？
2. `ch1.2.clear.2` · researcher · 研究员 · modal
……看来连这也记不得了。你叫查理，而我，只是一名研究员。
3. `ch1.2.clear.3` · researcher · 研究员 · modal
在这个世界上，绝大多数人都能看清并踏上那些隐秘的认知路径。
4. `ch1.2.clear.4` · researcher · 研究员 · modal
但你不同。你看不见它们，更无法踏足其上。
5. `ch1.2.clear.5` · researcher · 研究员 · modal
所以你主动来到研究所找到我，希望能治好这种认知障碍。
6. `ch1.2.clear.6` · researcher · 研究员 · modal
刚才只是一次测试……看来你的病情比预想中更严重，甚至开始侵蚀记忆了。

---

## 1-3 错位之契

### intro · 进关后

`id` 前缀：`ch1.3.intro`

1. `ch1.3.intro.1` · charlie · modal
怎么又是这样……眼前的路又是断的。
2. `ch1.3.intro.2` · charlie · modal
明明刚才那只小老鼠好像走过类似的结构，现在却完全看不出规律……
3. `ch1.3.intro.3` · researcher · 研究员 · modal
别急。先走到你脚下这条路的尽头——对，就是悬崖边缘。

### rotate · 玩家走到悬崖，建筑开始转

`id` 前缀：`ch1.3.rotate`

1. `ch1.3.rotate.1` · charlie · banner
等等……脚下的地面在转动？！
2. `ch1.3.rotate.2` · charlie · banner
那边的断口……好像接上了！

### after_rotate · 转到位后

1. `ch1.3.after_rotate.1` · researcher · 研究员 · modal
看到了吗？通路已经建立。现在试着走过来。
2. `ch1.3.after_rotate.2` · charlie · modal
好……我试试看。

---

### clear · 到达终点

`id` 前缀：`ch1.3.clear`

1. `ch1.3.clear.1` · charlie · modal
我刚才……是不是踩在了一条根本不存在的路上？！我的病是不是好了？！
2. `ch1.3.clear.2` · researcher · 研究员 · modal
很遗憾，并没有。刚才是我在外部强制干预了你的空间认知；一旦离开我的干预，你依然会变回原样。
3. `ch1.3.clear.3` · researcher · 研究员 · modal
不过……我确实找到了一种彻底根治的方法。
4. `ch1.3.clear.4` · researcher · 研究员 · modal
刚才那只叫阿尔吉侬的小鼠，你也看见了，它能坦然走过那些“你眼中不存在”的道路。
5. `ch1.3.clear.5` · researcher · 研究员 · modal
因为它接受了我研发的意识重构手术。手术在它身上非常成功……
6. `ch1.3.clear.6` · researcher · 研究员 · modal
……但这种手术，还从未在人类身上尝试过。
7. `ch1.3.clear.7` · charlie · modal
请让我试试吧！我也想像阿尔吉侬那样……能亲眼看见、亲脚踏上属于我自己的路！
8. `ch1.3.clear.8` · researcher · 研究员 · modal
这扇门后就是手术室。重构意识的风险完全未知，你真的做好准备了吗？
9. `ch1.3.clear.9` · charlie · modal
我准备好了。