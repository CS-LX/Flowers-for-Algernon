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
}
