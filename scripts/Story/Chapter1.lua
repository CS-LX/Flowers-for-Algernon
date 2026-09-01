-- 第一章台词。导演只决定何时 PlayStory，不在这里写时机。

return {
    intro = {
        {
            id = "ch1.intro.1",
            text = "门还在。",
            mode = "fullscreen",
            background = { 18, 16, 14, 236 },
        },
        {
            id = "ch1.intro.2",
            text = "我想过去。",
            mode = "fullscreen",
            background = { 24, 20, 16, 236 },
        },
        {
            id = "ch1.intro.3",
            text = "我想走到那扇门那里。路还没连上，但它已经站在另一边等了。",
            mode = "fullscreen",
            background = { 32, 24, 18, 236 },
        },
    },
    bannerTest = {
        {
            id = "ch1.test.banner",
            speaker = "测试",
            style = "normal",
            text = "这是底部 banner 打字测试。它会自动打完，不锁走路。",
            mode = "banner",
        },
    },
    modalTest = {
        {
            id = "ch1.test.modal",
            speaker = "测试",
            style = "normal",
            text = "这是 modal 打字测试。必须点完才能继续玩。",
            mode = "modal",
        },
        {
            id = "ch1.test.charlie",
            style = "charlie",
            text = "门还在。我想走到那扇门那里。",
            mode = "modal",
        },
    },
    clear = {
        {
            id = "ch1.clear.1",
            speaker = nil,
            text = "门后还是迷宫。",
            mode = "fullscreen",
            background = { 18, 16, 14, 236 },
        },
        {
            id = "ch1.clear.2",
            speaker = "查理",
            text = "它已经先走过去了吗？",
            mode = "fullscreen",
            background = { 28, 22, 18, 236 },
        },
    },
}
