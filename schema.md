# 数据格式规范

本项目使用 JSON 作为策划配置格式。选择 JSON 的原因是：Godot 4.6 可直接用 `JSON.parse_string()` 解析；格式直观，便于策划、测试脚本和外部策略程序共同读取；后续也容易导出给 Python 做批量分析。

示例配置文件放在 `data/sample_config.json`。模拟器启动时先加载该文件，读取角色、技能、道具、怪物、关卡和流派预设。

## 1. 顶层结构

```json
{
  "schema_version": "1.0.0",
  "game": {},
  "characters": [],
  "skills": [],
  "items": [],
  "item_affixes": [],
  "monsters": [],
  "stages": [],
  "build_presets": []
}
```

字段说明：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| schema_version | string | 是 | 配置格式版本 |
| game | object | 是 | 全局规则 |
| characters | array | 是 | 可玩角色列表 |
| skills | array | 是 | 技能列表 |
| items | array | 是 | 道具列表 |
| item_affixes | array | 否 | 清房奖励可随机附加的道具词条池 |
| monsters | array | 是 | 怪物列表 |
| stages | array | 是 | 关卡列表 |
| build_presets | array | 是 | 流派预设，用于批量模拟对照 |

说明：

- 主模拟器面板会从 `build_presets` 读取流派显示名和默认构筑。
- 运行时通过 `strategy_id` 将某个预设和某个策略实现绑定起来，形成“配置定义构筑，策略定义行为”的分层。

## 2. 全局规则 `game`

```json
{
  "tick_seconds": 0.1,
  "max_turns": 80,
  "max_seconds": 120,
  "starting_energy": 3,
  "max_energy": 6,
  "room_clear_heal": 48,
  "starting_stat_points": 6,
  "item_slots": 2,
  "reward_affix_chance": 0.85
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| tick_seconds | number | 实时模式每 tick 对应的秒数 |
| max_turns | int | 回合制最大回合数 |
| max_seconds | number | 实时模式最大模拟秒数 |
| starting_energy | int | 战斗开始时的能量 |
| max_energy | int | 能量上限 |
| room_clear_heal | number | 清理一个房间并选择奖励后恢复的 HP |
| starting_stat_points | int | 开局可分配属性点 |
| item_slots | int | 开局可携带道具数量 |
| reward_affix_chance | number | 清房奖励道具获得随机词条的概率，范围 0 到 1 |

## 3. 角色 `characters`

```json
{
  "id": "ember_hunter",
  "name": "余烬猎手",
  "base_stats": {
	"max_hp": 120,
	"attack": 12,
	"defense": 3,
	"crit_rate": 0.1,
	"crit_damage": 1.8,
	"speed": 10,
	"burn_power": 4,
	"summon_power": 6,
	"energy_regen": 1
  },
  "stat_growth": {
	"attack": 2,
	"crit_rate": 0.05,
	"speed": 1.5,
	"max_hp": 10,
	"burn_power": 1.5,
	"summon_power": 2,
	"defense": 1
  },
  "skill_ids": ["basic_attack", "core_split", "ember_mark", "armor_pulse", "ember_servant"]
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| base_stats | object | 基础属性 |
| stat_growth | object | 每点属性点带来的提升 |
| skill_ids | array | 角色可使用技能 ID |

## 4. 技能 `skills`

```json
{
  "id": "core_split",
  "name": "裂芯斩",
  "kind": "direct_damage",
  "cooldown": 3,
  "energy_cost": 2,
  "power": 2.2,
  "can_crit": true,
  "tags": ["physical", "burst"],
  "effects": []
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| kind | string | 技能类型，如 `basic`、`direct_damage`、`dot`、`debuff`、`summon` |
| cooldown | number | 冷却时间。回合制按回合，实时模式按秒 |
| energy_cost | int | 能量消耗 |
| power | number | 技能倍率或基础系数 |
| can_crit | bool | 是否可暴击 |
| tags | array | 用于策略判断的标签 |
| effects | array | 附加效果 |

附加效果格式：

```json
{
  "type": "burn",
  "stacks": 4,
  "duration": 4
}
```

常用 `type`：

| type | 说明 |
| --- | --- |
| burn | 施加灼烧 |
| armor_break | 施加破甲 |
| summon | 召唤单位 |
| bonus_vs_debuff | 目标带指定 debuff 时增伤 |

## 5. 道具 `items`

```json
{
  "id": "prism_charm",
  "name": "棱镜护符",
  "effects": [
	{
	  "type": "stat_add",
	  "stat": "crit_rate",
	  "value": 0.1
	}
  ],
  "tags": ["crit"]
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| charges | int | 主动道具可用次数；被动道具可省略 |
| effects | array | 道具效果列表 |
| tags | array | 流派标签 |

常用道具效果：

| type | 说明 |
| --- | --- |
| stat_add | 增加角色属性 |
| on_crit_damage | 暴击时追加伤害 |
| burn_modify | 修改灼烧持续和伤害 |
| burn_explosion | 灼烧层数达标时触发爆炸 |
| summon_limit_add | 增加召唤物上限 |
| on_summon_damage_energy | 召唤物造成伤害时回能 |
| active_heal | 主动使用后恢复 HP |
| active_energy | 主动使用后恢复能量 |
| active_damage | 主动使用后造成一次伤害 |

主动道具示例：

```json
{
  "id": "ember_vial",
  "name": "余烬急救瓶",
  "charges": 1,
  "effects": [
	{
	  "type": "active_heal",
	  "value": 34,
	  "max_hp_ratio": 0.08
	}
  ],
  "tags": ["active", "survival"]
}
```

## 6. 奖励词条 `item_affixes`

清房奖励会从未获得道具中抽取候选项，再按 `game.reward_affix_chance` 为候选道具随机附加 0 到 1 个词条。词条会改变道具显示名，并把自己的 `effects` 合并进道具运行时效果。

```json
{
  "id": "sharp",
  "display_name": "锋锐",
  "name_prefix": "锋锐的",
  "description": "追加攻击力，适合暴击与爆发道具。",
  "weight": 2,
  "applicable_tags": ["crit", "attack", "burst"],
  "effects": [
	{
	  "type": "stat_add",
	  "stat": "attack",
	  "value": 2
	}
  ],
  "tags": ["affix_attack"]
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| display_name | string | 词条短名称，用于导出和 replay 展示 |
| name_prefix | string | 附加到道具名前的前缀 |
| name_suffix | string | 附加到道具名后的后缀，可省略 |
| description | string | 词条说明 |
| weight | number | 在可用候选词条中的随机权重 |
| applicable_tags | array | 只会附加到标签匹配的道具；为空则通用 |
| effects | array | 合并到道具运行时效果的效果列表 |
| tags | array | 词条自身标签 |

## 7. 怪物 `monsters`

```json
{
  "id": "ash_crawler",
  "name": "灰壳爬行者",
  "stats": {
	"max_hp": 55,
	"attack": 8,
	"defense": 1,
	"speed": 8
  },
  "behavior": {
	"type": "basic_attack"
  }
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| stats | object | 怪物属性 |
| behavior | object | 怪物行为 |

## 8. 关卡 `stages`

```json
{
  "id": "corridor_entrance",
  "name": "回廊入口",
  "waves": [
	{
	  "monster_id": "ash_crawler",
	  "count": 2,
	  "spawn": "sequential"
	}
  ]
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| waves | array | 怪物波次 |
| monster_id | string | 怪物 ID |
| count | int | 数量 |
| spawn | string | 出场方式，当前支持 `sequential` |

## 9. 流派预设 `build_presets`

流派预设用于批量模拟，也作为策略 API 的默认样例输入。运行时会把匹配当前 `strategy_id` 的预设放进 `initial_context.build_preset`。

```json
{
  "id": "crit_build",
  "name": "裂芯暴击流",
  "stat_points": {
	"attack": 3,
	"crit_rate": 3
  },
  "item_ids": ["prism_charm", "blade_gear"],
  "strategy_id": "crit_strategy"
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 唯一 ID |
| name | string | 显示名 |
| stat_points | object | 开局属性点分配，总点数应等于 `game.starting_stat_points` |
| item_ids | array | 携带道具 ID，数量应不超过 `game.item_slots` |
| strategy_id | string | 对应策略实现 ID |

## 10. 基础校验规则

加载配置时至少校验：

1. 顶层字段必须存在。
2. 所有 `id` 在各自类型内唯一。
3. 角色引用的 `skill_ids` 必须能在 `skills` 中找到。
4. 关卡引用的 `monster_id` 必须能在 `monsters` 中找到。
5. 流派预设引用的 `item_ids` 必须能在 `items` 中找到。
6. 流派预设引用的 `strategy_id` 必须能匹配到一个已注册的策略实现。
7. 流派预设的属性点总和必须等于 `starting_stat_points`。
8. 流派预设的 `item_ids` 数量不能超过 `item_slots`。
9. 数值字段不能为负，`crit_rate` 应限制在 0 到 1 之间。
