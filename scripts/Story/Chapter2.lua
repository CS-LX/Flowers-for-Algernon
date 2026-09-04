return {
    surgery = {
        {
            id = "ch2.1.surgery.1",
            style = "researcher",
            speaker = "研究员",
            text = "手术已经完成了。先看看周围。",
            mode = "modal",
        },
        {
            id = "ch2.1.surgery.2",
            style = "charlie",
            text = "好像没有什么不同。可是……这里看起来清楚多了。",
            mode = "modal",
        },
    },
    after_mouse = {
        {
            id = "ch2.1.after_mouse.1",
            style = "charlie",
            text = "诶，刚刚那个不是阿尔吉侬吗？",
            mode = "modal",
        },
        {
            id = "ch2.1.after_mouse.2",
            style = "charlie",
            text = "它朝门过去了。那我也跟过去看看。",
            mode = "modal",
        },
    },
    praise = {
        {
            id = "ch2.1.praise.1",
            style = "researcher",
            speaker = "研究员",
            text = "很好。你刚才走过了一条不存在的路径。",
            mode = "modal",
        },
        {
            id = "ch2.1.praise.2",
            style = "charlie",
            text = "不存在？有吗？",
            mode = "modal",
        },
    },
    reveal = {
        {
            id = "ch2.1.reveal.1",
            style = "researcher",
            speaker = "研究员",
            text = "现在看到了吗？刚才那条路，在现实里并不存在。",
            mode = "modal",
        },
        {
            id = "ch2.1.reveal.2",
            style = "researcher",
            speaker = "研究员",
            text = "手术之后，你也能看见这样的路径了。",
            mode = "modal",
        },
        {
            id = "ch2.1.reveal.3",
            style = "charlie",
            text = "我看见了。我成功了！",
            mode = "modal",
        },
    },
    -- 2-2 的核心巧思：将原著中查理“异于常人的智力”转译为两层能力：
    -- 1. 能走过不存在的路径，体现他获得了正常的智力；
    -- 2. 能创造不存在的路径，体现他进一步拥有了超常的智力。
    -- 目前剧情还没有完整引导“鼠标悬停 -> 按下拖动 / 转动”的操作链；
    -- 后续润色时需要补足操作引导，同时保持在世界观内，不直接说出鼠标、点击等元叙事概念。
    -- 2-2 的“操控路径”不是把玩家动作说成鼠标操作。
    -- 叙事映射：玩家悬停在可旋转结构上时，结构的发光反馈被表达为“注意力停留后回应”；
    -- “路径结构”同时保留查理异于常人的智慧这一层含义，后续润色对白时可继续深化。
    control_intro = {
        {
            id = "ch2.2.control_intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "现在的你，已经拥有了常人无法拥有的能力。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "阿尔吉侬已经跨过悬崖，在终点前面等着你了。试着操控这座建筑。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.3",
            style = "researcher",
            speaker = "研究员",
            text = "把注意力停在路径结构上。看，它正在发光——那是它在回应你的操作。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.4",
            style = "charlie",
            text = "我试试看……让这条路，变成我能走的样子。",
            mode = "modal",
        },
    },
    control_start = {
        {
            id = "ch2.2.control_start.1",
            style = "charlie",
            text = "我做到了！我不仅能走上看不见的路径，还能让它出现！",
            mode = "banner",
        },
    },
    clear = {
        {
            id = "ch2.2.clear.1",
            style = "researcher",
            speaker = "研究员",
            text = "非常好。效果很好。你已经学会操控路径结构了。",
            mode = "modal",
        },
        {
            id = "ch2.2.clear.2",
            style = "charlie",
            text = "原来这就是我能做到的事……我还想看更多。",
            mode = "modal",
        },
    },
    -- 2-3 的对照实验只通过措辞暗示，不直接说出“术后功效测试”。
    -- “熟悉这里的结构”“形成自己的判断”让研究员的话里有话，但不会把查理当成被比较的对象，
    -- 也避免把阿尔吉侬先到写成对查理的嘲讽或否定。
    ch2_3_intro = {
        {
            id = "ch2.3.intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "这里是阿尔吉侬做寻路测试的地方。它以前很快就通过了。",
            mode = "modal",
        },
        {
            id = "ch2.3.intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "不过，走通一条路只是开始。真正重要的是，你能不能理解道路为什么会出现。",
            mode = "modal",
        },
        {
            id = "ch2.3.intro.3",
            style = "charlie",
            text = "我和阿尔吉侬一起试试。也许我能找到自己的路。",
            mode = "modal",
        },
    },
    charlie_first = {
        {
            id = "ch2.3.charlie_first.1",
            style = "researcher",
            speaker = "研究员",
            text = "很好。你先一步走到了这里。手术后的变化，比预期还要明显。",
            mode = "modal",
        },
        {
            id = "ch2.3.charlie_first.2",
            style = "charlie",
            text = "我只是顺着看见的路走过来了。原来我真的能做到。",
            mode = "modal",
        },
    },
    algernon_first_banner = {
        {
            id = "ch2.3.algernon_first.banner",
            style = "charlie",
            text = "阿尔吉侬好快！它已经到终点了。",
            mode = "banner",
        },
    },
    algernon_first = {
        {
            id = "ch2.3.algernon_first.1",
            style = "researcher",
            speaker = "研究员",
            text = "别急，慢慢来。阿尔吉侬熟悉这里的结构，但你正在学会理解它。",
            mode = "modal",
        },
        {
            id = "ch2.3.algernon_first.2",
            style = "charlie",
            text = "我明白了。它走过的路，可以告诉我该看哪里，但我要自己找到下一步。",
            mode = "modal",
        },
        {
            id = "ch2.3.algernon_first.3",
            style = "researcher",
            speaker = "研究员",
            text = "正是这样。你不是在追赶它，你是在形成自己的判断。",
            mode = "modal",
        },
    },
    -- 2-4 是第二章的收束：查理不再依赖研究员或阿尔吉侬，自己找到离开实验室的路。
    -- 后续润色时建议在去留选择中补充以下对白：
    -- 研究员：“最高处的那扇门，是离开实验室的出口。”
    -- 研究员：“你可以留下，继续在这里接受观察；也可以走出去。由你自己决定。”
    -- 查理：“那阿尔吉侬呢？”
    -- 研究员：“它还要留在这里，完成剩下的观察。”
    -- 查理：“那我先出去。不过……我还会回来看看它。”
    --
    -- 设计原因：阿尔吉侬没有跟随 Lift 不是遗漏，而是因为它仍被作为实验对象留在研究所。
    -- 这组对白要明确承认查理与阿尔吉侬在此暂时分别，避免玩家误以为剧情遗忘了阿尔吉侬；
    -- 同时提前建立“查理会回来找它”的承诺，为第三章主动返回、发现阿尔吉侬衰退，
    -- 以及最终把它带出实验室并沿真实道路去墓前送花建立完整因果链。
    -- 2-4 是查理第一次为自己选择离开；后续则由他替阿尔吉侬完成离开，形成前后对照。
    ch2_4_intro = {
        {
            id = "ch2.4.intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "你已经学会看见道路，也学会让道路出现。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "最高处的那扇门，是离开实验室的出口。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.3",
            style = "researcher",
            speaker = "研究员",
            text = "你可以留下，继续在这里接受测试；也可以走出去。由你自己决定。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.4",
            style = "charlie",
            text = "我想出去。我想看看，外面的路现在是什么样。",
            mode = "modal",
        },
    },
    ch2_4_path = {
        {
            id = "ch2.4.path.1",
            style = "charlie",
            text = "我知道该怎么走了。",
            mode = "banner",
        },
    },
    ch2_4_lift_begin = {
        {
            id = "ch2.4.lift_begin.1",
            style = "charlie",
            text = "它在动……这是要带我去哪儿？",
            mode = "banner",
        },
        {
            id = "ch2.4.lift_begin.2",
            style = "researcher",
            speaker = "研究员",
            text = "出去看看吧，查理。",
            mode = "banner",
        },
    },
    ch2_4_farewell = {
        {
            id = "ch2.4.farewell.1",
            style = "researcher",
            speaker = "研究员",
            text = "接下来的路，你自己走。",
            mode = "modal",
        },
        {
            id = "ch2.4.farewell.2",
            style = "charlie",
            text = "嗯。我自己走。",
            mode = "modal",
        },
    },
}
