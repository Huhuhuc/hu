# 《余烬回廊》：Roguelike 流派强弱模拟器

一个基于 Godot 4.6.1 的 Roguelike Build 验证小项目。项目同时提供可玩的房间战斗模式，以及用于数值验证的回合制 / Tick 制战斗模拟器。

核心目标：

> 用可替换 AI 策略批量验证不同 Roguelike 流派的胜率、耗时、剩余 HP 和伤害曲线。

## 项目亮点

- 配置化角色、技能、怪物、道具和关卡，核心数据位于 `data/sample_config.json`。
- 启动时会做严格配置校验，覆盖顶层字段、唯一 ID、引用关系、属性点总和和关键数值范围，错误会明确显示而不是静默兜底。
- 战斗系统和玩家决策解耦，策略只需要实现 `choose_initial_build(context)`、`choose_reward(context)` 和 `decide_action(context)`。
- 开局构筑由 `build_presets` 配置驱动，策略在 `choose_initial_build(context)` 中消费 `context.build_preset`，避免把初始加点和初始道具硬编码在核心流程里。
- 同时支持回合制模拟与实时 Tick 模拟。
- 支持单场模拟、批量模拟、三流派对照模拟。
- 命令行支持 `--seed=` 固定随机种子；CSV 逐局记录 seed，失败样本可以用 `--single-sim --seed=...` 原样复现。
- 批量模拟会统计工具自身耗时和 `runs_per_second`，用于评估模拟吞吐量，而不只看游戏内胜负。
- 支持主动道具 `use_item` 动作，策略可在低血量等条件下决定是否使用道具。
- 支持清房奖励随机词条，词条会改变道具名并合并运行时效果。
- 单场和批量结果会导出 `replay_events` 事件流，模拟器面板可直接播放上次结果。
- 模拟器面板提供三流派胜率、平均耗时、平均剩余 HP 的条形图对比。
- 模拟结果导出为 JSON / CSV，便于后续用表格或脚本做数值分析。
- 保留一个轻量可玩的房间模式，用于展示清房、三选一奖励、技能和怪物表现。

## 笔试题要求对照

| 题目要求 | 当前完成情况 | 对应文件 / 入口 |
| --- | --- | --- |
| 小而自洽的策划案 | 已完成：世界观、角色、属性、技能、道具、怪物、关卡、三套流派假设 | `design.md` |
| 数据格式规范 | 已完成：JSON 顶层结构、角色/技能/道具/怪物/关卡字段说明、完整示例配置 | `schema.md`、`data/sample_config.json` |
| 策略 API 规范 | 已完成：开局加点、清房奖励、技能释放、主动道具使用等策略接口 | `api.md`、`scripts/strategy/*.gd` |
| 配置加载与错误提示 | 已完成：UI 可重新加载配置，解析失败、字段缺失、ID 重复、引用失效、属性点不合法等都会清晰报错 | `scripts/main.gd`、`scripts/playable_game.gd` |
| 场景渲染 | 已完成：可玩房间模式显示玩家、怪物、HP 条、飘字、技能提示 | `scenes/PlayableGame.tscn` |
| 回合制战斗 | 已完成：按速度决定先后手，技能 CD、能量、状态逐回合结算 | `scripts/combat/combat_simulator.gd` |
| 实时 Tick 战斗 | 已完成：按固定 tick 推进，技能 CD、灼烧、召唤物、攻击间隔按秒结算 | `scripts/combat/combat_simulator.gd` |
| 可替换策略实现 | 已完成：暴击流、灼烧流、召唤流三套策略可替换运行；开局构筑来自 `build_presets`，战斗动作来自策略实现 | `scripts/strategy/crit_strategy.gd` 等 |
| 战斗结果输出 | 已完成：胜负、回合/tick/秒、剩余 HP、技能次数、道具次数、总伤害、承伤、伤害曲线图和表格 | UI、`user://last_result.json` |
| CSV / JSON 导出 | 已完成：单场、批量、三流派对照均可导出，CSV 包含 seed、平均耗时、平均 HP、平均伤害、平均承伤、Replay 事件数和模拟器吞吐 | `batch_summary.csv`、`strategy_compare.csv` |
| 批量模拟 | 已完成：命令行和 UI 均可运行 N 次并统计胜率、平均耗时、平均回合/tick/秒、平均剩余 HP、平均伤害、平均承伤和 runs/s | `--batch-sim --runs=N --seed=12345` |
| 加分项：可视化对比面板 | 已完成：三流派对照后在 UI 中显示胜率/耗时/HP 条形图 | `scenes/Main.tscn` |
| 加分项：Replay 事件流 | 已完成：导出完整事件序列，UI 可播放上次单场/批量中的第一场结果，用于复盘技能、伤害、奖励和道具使用 | `last_result.json` 的 `replay_events`、`回放上次结果` |
| 加分项：随机词条 | 已完成：清房奖励候选道具会按权重随机附加词条，词条效果进入战斗结算，并在 UI / CSV / Replay 中展示 | `data/sample_config.json` 的 `item_affixes` |
| 加分项：Web 部署 / 外部进程策略 | 暂未实现，保留为后续扩展方向 | 可基于现有 API 继续扩展 |

## 面向客户端面试的工程点

| 关注点 | Demo 中的对应设计 |
| --- | --- |
| 玩法框架拆分 | `CombatSimulator` 只管规则推进，Strategy API 只管玩家决策，配置文件只管数值内容 |
| 数据驱动 | 角色、技能、道具、怪物、关卡和流派 preset 均从 JSON 加载，配置校验失败会明确报错 |
| 可复现调试 | 所有 CLI 模拟入口都支持 `--seed=`；批量 CSV 会记录每局 seed，可用 `--single-sim --seed=...` 复现失败局 |
| 可量化验证 | 批量输出胜率、耗时、剩余 HP、总伤害、承伤、Replay 事件数、模拟耗时和 runs/s |
| 问题定位 | 单场 JSON 保存 `damage_curve`、`logs`、`warnings`、`replay_events`，UI 可播放上次结果 |
| 扩展边界 | 新增流派优先增加 `build_presets` 和策略脚本，核心战斗代码只消费动作，不识别具体流派名 |

## 核心架构

```text
                ┌────────────────┐
                │  配置文件 JSON  │
                └──────┬─────────┘
                       │
           加载角色/技能/关卡/流派 preset
                       │
        ┌──────────────▼──────────────┐
        │      Combat Simulator        │
        │  战斗推进 / Tick / 回合结算   │
        └──────────────┬──────────────┘
                       │
              构造 BattleContext
                       │
        ┌──────────────▼──────────────┐
        │        Strategy API          │
        │ choose_initial_build         │
        │ choose_reward                │
        │ decide_action                │
        └──────┬─────────┬────────────┘
               │         │
        暴击流策略  灼烧流策略  召唤流策略
               │         │
        返回加点/奖励/技能动作
                       │
                执行动作结算
                       │
             输出战斗结果 JSON / CSV
```

## 三套流派

| 流派 | 核心属性 | 核心技能 / 道具 | 验证命题 |
| --- | --- | --- | --- |
| 裂芯暴击流 | attack、crit_rate | 碎甲脉冲、裂芯斩、棱镜护符、锋刃齿轮 | 高随机性爆发流是否能换取更短通关时间 |
| 余火持续输出流 | speed、burn_power | 燃烬印记、余火沙漏、裂变火种 | DOT 是否在长线战斗中更稳定 |
| 余烬召唤流 | summon_power、max_hp | 余烬仆从、灰烬铃、共鸣核心 | 召唤流是否能用更长耗时换取更高生存率 |

## 目录结构

```text
data/sample_config.json          # 角色 / 技能 / 道具 / 怪物 / 房间配置
scenes/LaunchMenu.tscn           # 入口菜单
scenes/PlayableGame.tscn         # 可玩的房间战斗模式
scenes/Main.tscn                 # 流派模拟器面板
scripts/playable_game.gd         # 实时动作玩法、清房奖励、结果导出
scripts/combat/combat_simulator.gd
                                 # 回合制 / Tick 制模拟核心
scripts/strategy/*.gd            # 三套可替换流派策略
design.md                        # 游戏设计与流派假设
api.md                           # Strategy API 规范
schema.md                        # JSON 数据格式规范
```

## 如何运行

用 Godot 4.6.1 打开：

```text
E:\game\roge\project.godot
```

主场景：

```text
res://scenes/LaunchMenu.tscn
```

启动后可选择：

- `可玩房间模式`：进入 `res://scenes/PlayableGame.tscn`
- `流派模拟器面板`：进入 `res://scenes/Main.tscn`

说明：

- `流派模拟器面板` 是本题要求的主交付路径，配置加载、策略 API、双模式模拟、批量统计和导出都以它为准。
- `可玩房间模式` 是额外演示场景，用来直观看怪物、技能、飘字和清房奖励，不作为策略 API 解耦的评分主路径。

## 操作

```text
WASD / 方向键：移动
鼠标左键 / J：普通射击
K：裂芯斩
L：燃烬印记
U：碎甲脉冲
I：余烬仆从
Space：冲刺
```

## 命令行验证

如果 `godot` 已加入 PATH，可以使用通用命令：

```powershell
godot --headless --path . --quit-after 3 -- --compare-strategies --runs=100 --mode=turn_based --seed=12345
```

下面是本机 Godot 4.6.1 控制台版路径示例。

基础 headless 启动：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3
```

单场 smoke test：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --smoke-turn --seed=12345
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --smoke-tick --seed=12345
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --smoke-replay --seed=12345
```

可复现单场模拟：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --single-sim --strategy=crit --mode=turn_based --seed=12345
```

批量模拟：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --batch-sim --runs=100 --strategy=crit --mode=turn_based --seed=12345
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --batch-sim --runs=100 --strategy=burn --mode=turn_based --seed=12345
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --batch-sim --runs=100 --strategy=summon --mode=turn_based --seed=12345
```

三流派对照：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --compare-strategies --runs=100 --mode=turn_based --seed=12345
```

导出位置：

```text
C:\Users\Huhuhu\AppData\Roaming\Godot\app_userdata\roge\last_result.json
C:\Users\Huhuhu\AppData\Roaming\Godot\app_userdata\roge\last_result.csv
C:\Users\Huhuhu\AppData\Roaming\Godot\app_userdata\roge\batch_summary.csv
C:\Users\Huhuhu\AppData\Roaming\Godot\app_userdata\roge\strategy_compare.csv
C:\Users\Huhuhu\AppData\Roaming\Godot\app_userdata\roge\exports\
```

`last_result.*`、`batch_summary.csv`、`strategy_compare.csv` 是 latest 文件，会被下一次运行覆盖；`exports/` 目录会额外保存带时间、类型、策略、模式、seed 和 runs 的归档副本，例如 `20260614_151714_single_crit_strategy_turn_based_seed12345_runs1.json`，用于区分多轮实验。

`last_result.json` 中包含 `replay_events`。每条事件都会记录事件序号、模式时间、回合、tick、房间索引和 payload，可用于解释某次异常胜负，例如关键暴击、急救瓶使用时机、清房奖励词条或 Boss 阶段承伤。模拟器面板的 `回放上次结果` 会逐条播放事件流，并同步刷新玩家 HP、敌人 HP、当前伤害来源、单次伤害、累计伤害、目标 HP 变化和 replay 日志。

`damage_curve` 不只记录累计伤害，也记录每次伤害的 `source`、`delta`、`total_damage`、`critical`、`enemy_hp_before`、`enemy_hp`、`turn`、`tick` 和 `room_index`。UI 图表中橙色折线表示累计伤害，蓝色竖柱表示单次伤害峰值；`last_result.csv` 的曲线区会导出同样字段，便于用表格筛出爆发点或异常低伤害点。

清房奖励支持 `item_affixes` 随机词条。词条会按 `applicable_tags` 匹配道具标签，并把自身 `effects` 合并到道具运行时效果中；最终道具和词条会出现在结果面板、`player_item_details`、Replay 奖励事件和 CSV 的 `final_item_details` 字段中。

批量导出的 `batch_summary.csv` 会先写一行汇总统计，包括 `base_seed`、`first_seed`、`last_seed`、`runs`、`wins`、`win_rate`、`average_time`、`average_turns`、`average_ticks`、`average_seconds`、`average_player_hp`、`average_damage_done`、`average_damage_taken`、`average_replay_events`、`elapsed_ms` 和 `runs_per_second`；后续逐场记录每次模拟的 seed、胜负、耗时、剩余 HP、伤害、承伤、技能次数、道具次数、最终道具词条和 Replay 事件数。

失败样本复盘流程：

1. 打开 `batch_summary.csv`，找到失败行的 `seed`。
2. 用 `--single-sim --strategy=... --mode=... --seed=失败行seed` 复现该局。
3. 查看 `last_result.json` 的 `replay_events`、`damage_curve`、`warnings`，或在 UI 中点击 `回放上次结果`。

## 示例测试结果

以下为一次 `--compare-strategies --runs=100 --mode=turn_based --seed=12345` 的输出结果。固定 seed 后，同一版本代码应得到同一批随机序列，便于面试复盘和回归验证。

| 流派 | 胜率 | 平均耗时 | 平均剩余 HP | 平均总伤害 |
| --- | ---: | ---: | ---: | ---: |
| 裂芯暴击流 | 93% | 64.6 | 52.4 | 2369.3 |
| 余火持续输出流 | 95% | 73.5 | 65.4 | 1977.9 |
| 余烬召唤流 | 100% | 71.7 | 88.9 | 1880.8 |

## 结果分析

裂芯暴击流通关速度最快，伤害最高，但严格依赖“碎甲脉冲 -> 裂芯斩”的爆发窗口。窗口失败或关键暴击缺失时，后续房间压力会明显增加。

余火持续输出流依赖燃烬印记和 DOT 结算，面对高血量怪物时输出更平滑，但启动和冷却窗口会拉长战斗时间。主动道具加入后，它能在低血量时使用余烬急救瓶补容错，胜率明显接近召唤流。

余烬召唤流平均耗时最长，但剩余 HP 最高。召唤物铺场和共鸣核心回能让它在长线战斗中更稳定，符合“用时间换生存率”的设计假设。

## 设计自评

预期上，我原本认为 `余火持续输出流` 会是最稳的通关流派，而 `裂芯暴击流` 会拿到最短平均耗时，`余烬召唤流` 则更像偏保守的长线流派。

实际批量结果和预期大体一致，但也暴露了一个比策划直觉更重要的事实：`召唤流` 的稳定性优势比我最初预估得更强。原因不是单个技能倍率高，而是它把输出拆散到了召唤攻击、回能、再次释放技能这条闭环里，显著降低了“关键窗口没打中就崩盘”的风险。

这说明验证器真正回答的不是“哪个技能面板更高”，而是“哪套构筑在完整战斗流程里的容错和资源循环更强”。这也是我在这个笔试题里最想强调的点：数值平衡不能只看单次伤害，而要看策略、节奏、资源和敌人结构共同作用后的统计结果。

## 面试讲解重点

这个项目最核心的设计是：战斗规则和玩家行为解耦。

`CombatSimulator` 只负责加载配置、推进规则、结算伤害和导出结果；流派行为全部由 Strategy API 返回。新增职业、流派、AI，甚至外部 Python/LLM 策略时，不需要改核心战斗代码，只需要新增配置里的 `build_presets`、补充策略实现或替换策略调用层。

这让项目不只是一个小战斗 Demo，而是一个可以批量验证 Build 强弱的数值实验工具。

