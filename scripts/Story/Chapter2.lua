return {
    surgery = {
        {
            id = "ch2.1.surgery.1",
            style = "researcher",
            speaker = "研究员",
            text = "重构手术已经顺利完成。先看看你的四周吧。",
            mode = "modal",
        },
        {
            id = "ch2.1.surgery.2",
            style = "charlie",
            text = "周围好像没什么不同……但奇怪的是，眼前的一切看起来比以前清晰了。",
            mode = "modal",
        },
    },
    after_mouse = {
        {
            id = "ch2.1.after_mouse.1",
            style = "charlie",
            text = "咦，刚才跑过去的是阿尔吉侬吗？",
            mode = "modal",
        },
        {
            id = "ch2.1.after_mouse.2",
            style = "charlie",
            text = "它好像朝门那边跑去了。我也过去看看！",
            mode = "modal",
        },
    },
    praise = {
        {
            id = "ch2.1.praise.1",
            style = "researcher",
            speaker = "研究员",
            text = "非常好。你刚才毫无迟疑地走过了一条原本不存在的路径。",
            mode = "modal",
        },
        {
            id = "ch2.1.praise.2",
            style = "charlie",
            text = "不存在？怎么会……我脚下的路明明踩得踏踏实实的啊？",
            mode = "modal",
        },
    },
    reveal = {
        {
            id = "ch2.1.reveal.1",
            style = "researcher",
            speaker = "研究员",
            text = "看到全貌了吗？在真实的空间结构里，那段路从来没有物理连接过。",
            mode = "modal",
        },
        {
            id = "ch2.1.reveal.2",
            style = "researcher",
            speaker = "研究员",
            text = "手术重构了你的认知维度。现在的你，已经能看见并踏足那些隐秘路径、跨越认知缝隙了。",
            mode = "modal",
        },
        {
            id = "ch2.1.reveal.3",
            style = "charlie",
            text = "我真的……走过来了？！我们真的成功了！",
            mode = "modal",
        },
    },
    -- 2-2 的核心巧思：将原著中查理“异于常人的智力”转译为两层能力：
    -- 1. 能走过不存在的路径，体现他获得了正常的智力；
    -- 2. 能创造不存在的路径，体现他进一步拥有了超常的智力。
    -- 操作引导保持在世界观内：凝视后发光，再抓住结构带动转动，不出现鼠标、点击等元叙事概念。
    control_intro = {
        {
            id = "ch2.2.control_intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "现在的你，不仅能看见这些路径，甚至可以更进一步。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "你看，阿尔吉侬已经跨过了断崖，在终点前等你了。但眼前的悬崖依然断裂着。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.3",
            style = "researcher",
            speaker = "研究员",
            text = "试着把注意力集中在中间那座错落的建筑结构上。当你凝视它时，它会散发微光——那是空间在回应你的感知。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.4",
            style = "researcher",
            speaker = "研究员",
            text = "试着去抓住它、带动它转动。把那些原本断开的视线与几何，重新拼合在一起。",
            mode = "modal",
        },
        {
            id = "ch2.2.control_intro.5",
            style = "charlie",
            text = "集中注意力……去抓住它……好！我来试试看，把断开的路转接起来！",
            mode = "modal",
        },
    },
    control_start = {
        {
            id = "ch2.2.control_start.1",
            style = "charlie",
            text = "太不可思议了！我不仅能走上看不见的路，还能亲自把它们创造出来！",
            mode = "banner",
        },
    },
    clear = {
        {
            id = "ch2.2.clear.1",
            style = "researcher",
            speaker = "研究员",
            text = "极佳的适应力。空间结构已经在你的掌控下完成了重组。",
            mode = "modal",
        },
        {
            id = "ch2.2.clear.2",
            style = "charlie",
            text = "原来这就是改变世界的感觉……我的大脑里充满了灵感，我还想看到更多！",
            mode = "modal",
        },
    },
    -- 2-3 的对照实验只通过措辞暗示，不直接说出“术后功效测试”。
    -- 阿尔吉侬先到的分支强调独立判断，不把结果写成对查理的嘲讽或否定。
    ch2_3_intro = {
        {
            id = "ch2.3.intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "这里曾是阿尔吉侬接受进行空间寻路测试的场所。以前，它很快就能找到解法。",
            mode = "modal",
        },
        {
            id = "ch2.3.intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "不过对现在的你来说，仅仅走通道路只是第一步。重要的是，你要去理解这些旋转结构为何能够相互沟通。",
            mode = "modal",
        },
        {
            id = "ch2.3.intro.3",
            style = "charlie",
            text = "我明白了！我和阿尔吉侬一起试试，我不会只跟在它后面，我要找到属于我自己的路！",
            mode = "modal",
        },
    },
    charlie_first = {
        {
            id = "ch2.3.charlie_first.1",
            style = "researcher",
            speaker = "研究员",
            text = "出色。你比阿尔吉侬更快抵达了终点。重构后的空间理解力，提升得比我预想的还要惊人。",
            mode = "modal",
        },
        {
            id = "ch2.3.charlie_first.2",
            style = "charlie",
            text = "我只是理清了那些交错的旋转角度与视觉邻接……原来我真的可以比它做得更好！",
            mode = "modal",
        },
    },
    algernon_first_banner = {
        {
            id = "ch2.3.algernon_first.banner.1",
            style = "charlie",
            text = "阿尔吉侬好敏捷！它已经先一步到达终点跑掉了。",
            mode = "banner",
        },
    },
    algernon_first = {
        {
            id = "ch2.3.algernon_first.1",
            style = "researcher",
            speaker = "研究员",
            text = "别急，按你自己的节奏来。阿尔吉侬对这里的机械结构早有记忆，而你正在重新建立一套认知体系。",
            mode = "modal",
        },
        {
            id = "ch2.3.algernon_first.2",
            style = "charlie",
            text = "我懂了。阿尔吉侬走过的轨迹能给我启发，但真正的出路，必须由我自己去观察和旋转出来。",
            mode = "modal",
        },
        {
            id = "ch2.3.algernon_first.3",
            style = "researcher",
            speaker = "研究员",
            text = "很好。你没有盲目模仿，你在形成自己独立的判断。",
            mode = "modal",
        },
    },
    -- 2-4 是第二章的收束：查理不再依赖研究员或阿尔吉侬，自己找到离开实验室的路。
    -- 阿尔吉侬仍作为实验对象留在研究所；查理承诺回来找它，为后续回访、衰退和送花建立因果。
    ch2_4_intro = {
        {
            id = "ch2.4.intro.1",
            style = "researcher",
            speaker = "研究员",
            text = "你在短时间内展现出了惊人的认知天赋。你已经能观察和塑造这个空间。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.2",
            style = "researcher",
            speaker = "研究员",
            text = "看向最高处的那扇门，那是通往研究所外部的出口。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.3",
            style = "charlie",
            text = "终于可以出去了……等等，那……阿尔吉侬呢？它不和我一起走吗？",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.4",
            style = "researcher",
            speaker = "研究员",
            text = "它还需要留在这里，配合完成后续的数据记录。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.5",
            style = "charlie",
            text = "这样啊……阿尔吉侬，那你先留在里面。等我去外面看完了更广阔的世界，我一定会再回来找你的！",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.6",
            style = "researcher",
            speaker = "研究员",
            text = "那么，选择权在你手中：你可以留下来继续接受测试，也可以推开门走出去。",
            mode = "modal",
        },
        {
            id = "ch2.4.intro.7",
            style = "charlie",
            text = "我想出去。我想亲眼看看，外面的世界现在是什么样子。",
            mode = "modal",
        },
    },
    ch2_4_path = {
        {
            id = "ch2.4.path.1",
            style = "charlie",
            text = "通往高处的路线……我已经看透它的几何关联了，走吧！",
            mode = "banner",
        },
    },
    ch2_4_lift_begin = {
        {
            id = "ch2.4.lift_begin.1",
            style = "charlie",
            text = "地面在升高……这是要带我去高处吗？",
            mode = "banner",
        },
        {
            id = "ch2.4.lift_begin.2",
            style = "researcher",
            speaker = "研究员",
            text = "去吧，查理，去看看外面的天空。",
            mode = "banner",
        },
    },
    ch2_4_farewell = {
        {
            id = "ch2.4.farewell.1",
            style = "researcher",
            speaker = "研究员",
            text = "实验室的测试到此为止了。接下来的广阔天地，你需要凭自己的智慧走下去。",
            mode = "modal",
        },
        {
            id = "ch2.4.farewell.2",
            style = "charlie",
            text = "嗯。这一次，我自己走。",
            mode = "modal",
        },
    },
}
