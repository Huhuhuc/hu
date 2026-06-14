# 流派策略 API 规范

## 1. 设计目标

策略 API 用来把“战斗规则”和“玩家决策”解耦。模拟器只负责加载配置、推进战斗、结算伤害和导出结果；玩家角色的加点、道具选择、技能释放和普通攻击选择，都必须由策略实现返回。

这样同一份角色、怪物和关卡配置，可以替换不同策略后批量模拟，得到不同流派的胜率、耗时、剩余 HP 和伤害曲线。

## 2. 接口形式

本项目最低实现采用 **GDScript 策略类接口**。

选择理由：

- Godot 4.6 原生支持，开发和调试成本最低。
- 策略可以作为脚本资源直接替换，满足题目要求的“可替换策略实现”。
- 接口输入和输出都设计为 Dictionary，结构接近 JSON，后续可以平滑扩展为 HTTP、JSON-RPC 或 stdio 外部进程策略。
- 不依赖额外服务器。

当前实现入口：

| 文件 | 职责 |
| --- | --- |
| `scripts/combat/combat_simulator.gd` | 加载配置、生成 context、调用策略、校验动作、推进回合制 / Tick 制战斗 |
| `scripts/strategy/strategy_base.gd` | 定义策略基类和 `_can_cast()` 辅助函数 |
| `scripts/strategy/crit_strategy.gd` | 裂芯暴击流样例策略 |
| `scripts/strategy/burn_strategy.gd` | 余火持续输出流样例策略 |
| `scripts/strategy/summon_strategy.gd` | 余烬召唤流样例策略 |
| `scripts/main.gd` | UI / 命令行选择策略并运行单场或批量模拟 |

替换策略入口：

- UI：`流派模拟器面板` 中的流派下拉框可以替换当前策略。
- UI：`对照三流派` 按钮会用同一关卡和同一批随机种子分别运行三套策略。
- 命令行：`--single-sim --strategy=crit|burn|summon --seed=12345` 可复现单场样本。
- 命令行：`--batch-sim --strategy=crit|burn|summon --seed=12345` 可指定单套策略批量运行，并把每局 seed 写入 CSV。
- 命令行：`--compare-strategies --seed=12345` 可直接对照运行所有样例策略，三套策略使用同一批随机种子。

建议目录：

```text
scripts/strategy/
  strategy_base.gd
  crit_strategy.gd
  burn_strategy.gd
  summon_strategy.gd
```

## 3. 策略基类

所有策略脚本继承同一个基类，至少实现以下方法。

```gdscript
class_name StrategyBase
extends RefCounted

func get_strategy_id() -> String:
	return "base"

func choose_initial_build(context: Dictionary) -> Dictionary:
	return {}

func choose_reward(context: Dictionary) -> Dictionary:
	return {"item_id": ""}

func decide_action(context: Dictionary) -> Dictionary:
	return {
		"type": "basic_attack",
		"target_id": context.get("current_target_id", "")
	}
```

## 4. 初始加点策略

### 4.1 调用时机

模拟器加载角色、技能、道具和关卡配置后，先按 `build_presets.strategy_id` 找到当前策略对应的默认构筑，再在战斗开始前调用一次：

```gdscript
var initial_build = strategy.choose_initial_build(initial_context)
```

实际代码位置：`scripts/combat/combat_simulator.gd` 的 `run()` 中调用 `strategy.choose_initial_build(...)`。`context.build_preset` 会把配置文件中的默认构筑传给策略，策略可以直接返回该 preset，也可以在其基础上做调整；随后 `_make_player(character, build)` 根据最终构筑应用属性成长和道具效果。

### 4.2 输入 `initial_context`

```json
{
  "schema_version": "1.0.0",
  "mode": "turn_based",
  "character": {
	"id": "ember_hunter",
	"base_stats": {},
	"stat_growth": {},
	"skill_ids": []
  },
  "available_items": [],
  "stage": {
	"id": "corridor_entrance",
	"waves": []
  },
  "build_preset": {
	"id": "crit_build",
	"strategy_id": "crit_strategy",
	"stat_points": {},
	"item_ids": []
  },
  "rules": {
	"starting_stat_points": 6,
	"item_slots": 2
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| mode | 当前模拟模式，`turn_based` 或 `realtime` |
| character | 当前角色配置 |
| available_items | 可选道具列表 |
| stage | 当前关卡配置 |
| build_preset | 当前策略对应的默认流派预设，来自 `data/sample_config.json` |
| rules | 全局规则 |

### 4.3 输出 `initial_build`

```json
{
  "stat_points": {
	"attack": 3,
	"crit_rate": 3
  },
  "item_ids": ["prism_charm", "blade_gear"],
  "notes": "暴击流：提高爆发伤害和暴击触发率"
}
```

字段说明：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| stat_points | object | 是 | 属性点分配，总和必须等于 `starting_stat_points` |
| item_ids | array | 是 | 选择的道具 ID，数量不能超过 `item_slots` |
| notes | string | 否 | 给 README 或调试面板展示的说明 |

### 4.4 清房奖励选择

每个房间清理完成后，模拟器从尚未获得的道具中随机提供 3 个候选项，并调用一次：

```gdscript
var reward_decision = strategy.choose_reward(reward_context)
```

输入示例：

```json
{
  "mode": "turn_based",
  "stage_index": 1,
  "stage": {},
  "choices": [
	{"id": "iron_heart", "name": "铁心脏"},
	{"id": "hot_coal", "name": "热煤块"},
	{"id": "battery_flask", "name": "电池瓶"}
  ],
  "player": {},
  "history": {
	"rooms_cleared": 1,
	"skill_cast_counts": {},
	"total_damage_done": 320,
	"total_damage_taken": 42
  }
}
```

输出格式：

```json
{
  "item_id": "iron_heart",
  "reason": "priority_match"
}
```

如果策略返回了不在候选列表中的道具，模拟器会记录 warning，并回退到第一个候选项。被动道具获得后立即应用到玩家属性或被动效果上；带 `active_*` 效果和 `charges` 字段的主动道具会进入 `available_actions`，由策略在战斗中通过 `use_item` 主动使用。

## 5. 战斗中决策

### 5.1 决策时机

为了兼容回合制和实时 tick 制，统一使用同一个 `decide_action(context)` 接口。

回合制模式：

- 玩家回合开始时调用一次。
- 如果技能冷却或能量不足，模拟器会拒绝非法动作，并回退为普通攻击或等待。
- 行动顺序由玩家速度和当前怪物速度比较决定。

实时模式：

- 每个 tick 推进冷却、Buff、召唤物和 DOT。
- 当玩家可行动时调用一次策略。
- 可行动条件由模拟器决定，例如普攻间隔结束、技能 CD 完成或能量足够。

技能 CD 好了：

- 不额外设计单独回调，策略可通过 `context.available_actions` 判断当前能释放哪些技能。
- 这样接口更简单，也方便批量测试。

实际代码位置：`scripts/combat/combat_simulator.gd` 的 `_player_action()` 会构造 `context = _make_context()`，然后调用 `strategy.decide_action(context)`。回合制由 `_run_turn_based()` 调用，实时 Tick 制由 `_run_realtime()` 在玩家行动计时器就绪时调用。

### 5.2 输入 `battle_context`

```json
{
  "mode": "turn_based",
  "time": {
	"turn": 7,
	"tick": 0,
	"seconds": 0.0
  },
  "player": {
	"id": "ember_hunter",
	"hp": 92,
	"max_hp": 120,
	"energy": 4,
	"stats": {},
	"cooldowns": {
	  "core_split": 0,
	  "ember_mark": 2,
	  "armor_pulse": 0,
	  "ember_servant": 5
	},
	"items": ["prism_charm", "blade_gear"],
	"summons": []
  },
  "current_target_id": "enemy_3",
  "enemies": [
	{
	  "instance_id": "enemy_3",
	  "monster_id": "furnace_guard",
	  "name": "炉心守卫",
	  "hp": 118,
	  "max_hp": 150,
	  "status": {
		"burn": 0,
		"armor_break": 2,
		"guarded": false
	  }
	}
  ],
  "available_actions": [
	{
	  "type": "basic_attack",
	  "target_id": "enemy_3"
	},
	{
	  "type": "cast_skill",
	  "skill_id": "core_split",
	  "target_id": "enemy_3"
	}
  ],
  "history": {
	"last_player_action": "armor_pulse",
	"skill_cast_counts": {
	  "core_split": 2,
	  "ember_mark": 1
	},
	"total_damage_done": 184,
	"total_damage_taken": 28
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| time | 当前回合、tick 和秒数 |
| player | 玩家当前状态 |
| current_target_id | 默认目标 |
| enemies | 当前场上敌人列表 |
| available_actions | 当前合法动作列表 |
| history | 战斗历史摘要，用于策略判断 |

### 5.3 输出 `action`

策略每次返回一个动作。

当前已实现动作：

| type | 是否已执行 | 说明 |
| --- | --- | --- |
| `basic_attack` | 是 | 普通攻击当前目标 |
| `cast_skill` | 是 | 释放当前合法技能 |
| `wait` | 是 | 本次不行动 |
| `use_item` | 是 | 使用当前已获得且仍有次数的主动道具 |
| `move` | 预留 | 抽象模拟器目前不模拟站位；可玩房间模式中玩家手动 WASD 走位 |

#### 普通攻击

```json
{
  "type": "basic_attack",
  "target_id": "enemy_3"
}
```

#### 释放技能

```json
{
  "type": "cast_skill",
  "skill_id": "core_split",
  "target_id": "enemy_3"
}
```

#### 使用道具

当前配置提供 `余烬急救瓶` 作为主动道具样例。策略只有在该道具已获得且剩余次数大于 0 时，才会在 `available_actions` 中看到 `use_item`。

```json
{
  "type": "use_item",
  "item_id": "ember_vial",
  "target_id": "enemy_3"
}
```

#### 等待

```json
{
  "type": "wait"
}
```

#### 走位

当前战斗不做复杂地图和寻路，但接口预留走位动作：

```json
{
  "type": "move",
  "direction": "back"
}
```

如果未来模拟器加入二维坐标，`move` 可以扩展为：

```json
{
  "type": "move",
  "vector": {"x": -1, "y": 0},
  "reason": "kite_ranged_enemy"
}
```

## 6. 非法动作处理

为了防止策略实现错误导致模拟器崩溃，模拟器必须校验动作合法性。

非法情况包括：

- `type` 不在支持列表中。
- `skill_id` 不存在。
- 技能冷却未结束。
- 能量不足。
- `target_id` 不存在或目标已死亡。
- 道具不在当前携带列表中。

处理规则：

1. 记录一条 warning log。
2. 本次动作回退为 `basic_attack`。
3. 如果没有可攻击目标，则回退为 `wait`。

实际代码位置：`scripts/combat/combat_simulator.gd` 的 `_sanitize_action(action, context)`。策略只能选择 `context.available_actions` 中的动作；如果返回了冷却中技能、能量不足技能或未知动作，模拟器会记录 warning 并回退，保证批量模拟不会因为单个策略错误崩溃。

## 7. 策略样例

下面给出三套流派策略样例。实际实现时可以分别写成 `crit_strategy.gd`、`burn_strategy.gd`、`summon_strategy.gd`。

本项目已经提供 3 套样例，实现数量超过题目要求的至少 2 套：

- `scripts/strategy/crit_strategy.gd`
- `scripts/strategy/burn_strategy.gd`
- `scripts/strategy/summon_strategy.gd`

对照运行方式：

```powershell
& "D:\godot v4.6.1\Godot_v4.6.1-stable_win64_console.exe" --headless --path "E:\game\roge" --quit-after 3 -- --compare-strategies --runs=30 --mode=turn_based --seed=12345
```

该入口会输出每套策略的胜率、平均耗时、平均剩余 HP、平均伤害和模拟吞吐，并导出 `user://strategy_compare.csv`。固定 `--seed` 后，三套策略会使用同一批随机种子，便于公平对照和复盘。

### 7.1 裂芯暴击流策略

初始构筑：

```json
{
  "stat_points": {
	"attack": 3,
	"crit_rate": 3
  },
  "item_ids": ["prism_charm", "blade_gear"]
}
```

战斗决策：

1. 如果目标没有破甲，且 `armor_pulse` 可释放，优先释放 `碎甲脉冲`。
2. 如果目标已有破甲，且 `core_split` 可释放，释放 `裂芯斩`。
3. 如果 `core_split` 可释放且目标 HP 高于 30%，释放 `裂芯斩`。
4. 否则普通攻击。

伪代码：

```gdscript
func decide_action(context: Dictionary) -> Dictionary:
	var target_id = context["current_target_id"]
	var target = context["enemies"][0]

	if _can_cast(context, "armor_pulse") and target["status"].get("armor_break", 0) == 0:
		return {"type": "cast_skill", "skill_id": "armor_pulse", "target_id": target_id}

	if _can_cast(context, "core_split") and target["status"].get("armor_break", 0) > 0:
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}

	if _can_cast(context, "core_split") and target["hp"] > target["max_hp"] * 0.3:
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}

	return {"type": "basic_attack", "target_id": target_id}
```

验证目标：

- 观察暴击流是否拥有最低平均通关时间。
- 观察暴击随机性是否导致胜率或剩余 HP 波动更大。

### 7.2 余火持续输出流策略

初始构筑：

```json
{
  "stat_points": {
	"speed": 3,
	"burn_power": 3
  },
  "item_ids": ["ember_hourglass", "fission_spark"]
}
```

战斗决策：

1. 如果目标灼烧层数低于 4，且 `ember_mark` 可释放，优先释放 `燃烬印记`。
2. 如果目标 HP 较高，且 `armor_pulse` 可释放，释放 `碎甲脉冲` 提高后续直伤。
3. 如果 `core_split` 可释放，释放 `裂芯斩` 补伤害。
4. 否则普通攻击。

伪代码：

```gdscript
func decide_action(context: Dictionary) -> Dictionary:
	var target_id = context["current_target_id"]
	var target = context["enemies"][0]
	var burn_stacks = target["status"].get("burn", 0)

	if _can_cast(context, "ember_mark") and burn_stacks < 4:
		return {"type": "cast_skill", "skill_id": "ember_mark", "target_id": target_id}

	if _can_cast(context, "armor_pulse") and target["hp"] > target["max_hp"] * 0.5:
		return {"type": "cast_skill", "skill_id": "armor_pulse", "target_id": target_id}

	if _can_cast(context, "core_split"):
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}

	return {"type": "basic_attack", "target_id": target_id}
```

验证目标：

- 观察持续输出流是否拥有更稳定的胜率。
- 观察其在最终敌人阶段的累计伤害是否高于暴击流。

### 7.3 余烬召唤流策略

初始构筑：

```json
{
  "stat_points": {
	"summon_power": 4,
	"max_hp": 2
  },
  "item_ids": ["ash_bell", "resonance_core"]
}
```

战斗决策：

1. 如果当前召唤物数量未达到上限，且 `ember_servant` 可释放，优先释放 `余烬仆从`。
2. 如果目标 HP 高于 50%，且 `ember_mark` 可释放，释放 `燃烬印记` 叠持续伤害。
3. 如果 `core_split` 可释放，释放 `裂芯斩` 补伤害。
4. 否则普通攻击。

伪代码：

```gdscript
func decide_action(context: Dictionary) -> Dictionary:
	var target_id = context["current_target_id"]
	var target = context["enemies"][0]
	var summons = context["player"].get("summons", [])
	var summon_limit = context["player"].get("summon_limit", 2)

	if _can_cast(context, "ember_servant") and summons.size() < summon_limit:
		return {"type": "cast_skill", "skill_id": "ember_servant", "target_id": target_id}

	if _can_cast(context, "ember_mark") and target["hp"] > target["max_hp"] * 0.5:
		return {"type": "cast_skill", "skill_id": "ember_mark", "target_id": target_id}

	if _can_cast(context, "core_split"):
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}

	return {"type": "basic_attack", "target_id": target_id}
```

验证目标：

- 观察召唤流是否在长战斗中拥有最高总伤害。
- 观察召唤流是否用更长耗时换取更高生存稳定性。

## 8. 扩展到外部策略进程

当前最低实现使用 GDScript 策略类。若后续要接 Python、LLM 或自动化测试脚本，可以复用同样的 Dictionary/JSON 结构，改成 HTTP 或 stdio。

示例 HTTP 请求：

```json
POST /decide_action
{
  "strategy_id": "crit_strategy",
  "context": {}
}
```

示例 HTTP 响应：

```json
{
  "type": "cast_skill",
  "skill_id": "core_split",
  "target_id": "enemy_3"
}
```

由于上下文和动作本身已经是 JSON 友好结构，外部策略进程不需要理解 Godot 节点，只需要读取状态并返回动作。

## 9. API 自评

这套 API 的边界较小，但能满足笔试题核心要求：

- 初始加点和道具选择由策略决定。
- 战斗中动作由策略决定。
- 同一关卡可以替换三套策略对比结果。
- 战斗逻辑不需要知道“暴击流”“持续输出流”“召唤流”的具体规则，只消费策略返回的动作。
- 未来接外部进程时，接口结构可以直接复用。
