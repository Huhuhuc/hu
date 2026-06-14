# 提交说明

## 项目名称

《余烬回廊》：Roguelike 流派强弱模拟器

## 交付内容

- `project.godot`：Godot 4.x 工程入口。
- `README.md`：项目介绍、运行方式、验证命令、结果分析和面试讲解重点。
- `design.md`：游戏设计、角色/技能/道具/怪物/关卡与流派假设。
- `schema.md`：JSON 配置格式规范。
- `api.md`：Strategy API 规范与扩展到外部策略的设计。
- `data/sample_config.json`：完整可加载的示例配置。
- `scripts/combat/combat_simulator.gd`：回合制 / Tick 制模拟核心。
- `scripts/strategy/*.gd`：暴击流、灼烧流、召唤流三套策略实现。
- `scenes/Main.tscn`：流派模拟器面板。
- `scenes/PlayableGame.tscn`：可玩房间模式演示。

## 推荐验收命令

如果 `godot` 已加入 PATH：

```powershell
godot --headless --path . --quit-after 3 -- --compare-strategies --runs=100 --mode=turn_based --seed=12345
```

本机示例路径：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --compare-strategies --runs=100 --mode=turn_based --seed=12345
```

## 重点能力说明

- 数据驱动：角色、技能、道具、怪物、关卡和流派 preset 都来自 JSON。
- 策略解耦：玩家加点、奖励选择、技能释放和主动道具使用都由 Strategy API 返回。
- 批量验证：同一关卡、同一 seed 序列下对照三套策略，统计胜率、耗时、HP、伤害、承伤和吞吐。
- 可复盘：单场结果导出 `replay_events` 和 `damage_curve`，UI 可回放，CSV 可定位伤害来源和异常点。
- 可归档：latest 文件便于快速读取，`user://exports` 会保存带时间、策略、模式、seed 的归档副本。

## 未实现但保留设计

- Web 部署：Godot HTML5 导出可作为后续扩展。
- 外部进程策略：当前 API 已使用 JSON 友好的 Dictionary 结构，可扩展为 HTTP / stdio / JSON-RPC 策略进程。
