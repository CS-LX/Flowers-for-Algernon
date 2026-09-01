-- 第一章台词。导演只决定何时 PlayStory，不在这里写时机。

return {
    intro = {
        {
            id = "ch1.intro.1",
            speaker = "查理",
            text = "我想走到那扇门那里。",
            mode = "fullscreen",
        },
    },
    bannerTest = {
        {
            id = "ch1.test.banner",
            speaker = "测试",
            text = "这是底部 banner 打字测试。它会自动打完，不锁走路。",
            mode = "banner",
        },
    },
    modalTest = {
        {
            id = "ch1.test.modal",
            speaker = "测试",
            text = "这是 modal 打字测试。必须点完才能继续玩。",
            mode = "modal",
        },
    },
    clear = {
        {
            id = "ch1.clear.1",
            speaker = nil,
            text = "门后还是迷宫。",
            mode = "fullscreen",
        },
        {
            id = "ch1.clear.2",
            speaker = "查理",
            text = "它已经先走过去了吗？",
            mode = "fullscreen",
        },
    },
}
