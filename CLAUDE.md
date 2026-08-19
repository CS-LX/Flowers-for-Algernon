# 项目开发规则

## 预览与运行时验证

- 用户已确认预览正常时，以预览结果作为当前视觉正确性的基线；不得仅因其他验证环境失败就替换正常实现。
- 独立无头 Runtime 验证不是默认必需步骤，只有用户明确要求或任务确实需要时才使用。
- 预览、构建、LSP、独立 Runtime 属于不同层次的检查。发现环境差异时，先归因并记录差异，不得把工具环境错误扩展为项目代码错误。
- 一个 API 在某个 Runtime 中失败，只能证明该 API 在该环境不可用，不能据此推断其他 API 也失败。
- 任何会改变已正常视觉结果的替换，必须先保留原实现，并在修改后进行目标画面回归检查；出现纸片、圆柱、黑屏等回归时立即恢复基线。
- 验证工具报错时，先区分用户脚本错误、资源缺失、运行时能力差异和验证器自身问题，再决定是否修改代码。

## 渲染验证与 3D Overlay

- 不能根据单次黑屏、全黑截图或某个独立 Runtime 的 shader/resource 错误，直接判定 Viewport、RenderPath 或 Overlay 架构不可用。
- 验证多 Viewport 时，必须使用颜色明确不同的 MainScene/OverlayScene，并检查真实像素；默认 RenderPath 可能包含 `CLEAR_COLOR | CLEAR_DEPTH | CLEAR_STENCIL`，会把前一个 Viewport 清掉。
- 3D 置顶 Overlay 的正式验证链路是：Viewport 0 绘制 MainScene，Viewport 1 绘制 OverlayScene；Overlay RenderPath 的首个清屏命令只清 `CLEAR_DEPTH`，不能清 `CLEAR_COLOR`。
- 在确认该链路前，不得用 UI 屏幕空间线条替代真实 3D Overlay，也不得把 DebugRenderer、CustomGeometry、UI Overlay 多次试错后的现象泛化为引擎能力结论。
- 渲染结论必须区分：API 存在、脚本运行、Scene 创建、真实像素合成、用户预览；低层探针失败时，先检查探针是否真正执行了目标命令以及是否在截图帧前提前退出。

## 变更范围与回退安全

- 用户要求回退某个功能时，必须按功能边界回退，不得按提交时间粗暴 `reset --hard` 到更早提交；与目标功能无关的已验收功能必须保留。
- 推送过的提交不得通过强制重写远程历史来修复范围错误；应恢复正确基线后，用普通提交记录范围化修复。
- 回退前必须先检查提交差异，列出需要移除和必须保留的文件/hunk；回退后必须用 `git diff`、`git status` 和提交历史复核。
- 用户明确说“先别写代码”或要求先调研时，只允许读取文档、源码和运行证据；不得创建实验实现、临时 Overlay 或替换现有渲染链路。
- 渲染问题在证据闭合前不得连续切换 DebugRenderer、CustomGeometry、UI Overlay 等实现；每次方案替换必须先说明渲染层、深度策略、提交顺序和回退边界，并等待用户确认。
- 发现误回退后，首先恢复无关的已验收功能，再处理目标问题；不得把事故扩大为整体回退。

## Git 提交与推送

- 远程仓库使用不含凭据的标准 HTTPS URL，禁止把 token 写入 remote URL、Git 配置、提交内容或日志。
- GitHub token 保存在项目本地 `secret/github_token`，`secret/` 必须持续受 `.gitignore` 排除。
- 用户说“提交并且推送”时，从 `secret/github_token` 临时读取凭据完成认证；认证数据只用于该次命令，不持久化到 Git 配置。
- 提交或推送前检查 `secret/` 未被 Git 追踪；推送后再次检查远程地址和提交内容不含凭据。
