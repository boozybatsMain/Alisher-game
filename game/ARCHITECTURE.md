# Tamyr: Steppe of Ancestors — архитектура и контракты модулей

Godot 4.7, Forward+, 3D-мир + 2D-персонажи-билборды (AnimatedSprite3D, готовые SpriteFrames из `assets/sprites/*`).
Это и есть «2.5D-компакт»: геометрия арен — 3D-блоки (MeshInstance3D + StaticBody3D, процедурно), задники — 2D-картинки
степи из `assets/bg/*` на дальних плоскостях; персонажи — спрайты с `billboard = BILLBOARD_FIXED_Y`, flip_h по направлению.

Единицы: 1 = 1 метр. Ось Y — вверх. Герой ~1.8 м. Арена ~ 30×24 м, ярусы на высоте 0 / 3 / 6 м.
Камера: ортогональная или перспективная с FOV ~30, наклон 40° вниз, смотрит с юга-востока (как Hades),
плавный зум при подъёме на ярусы.

## Папки и владельцы

| Папка | Что | Модуль |
|---|---|---|
| `game/core/` | автозагрузки Bus / Meta / Run / Sfx, Hit, Combat | ядро (не менять API, только добавлять) |
| `game/player/` | герой, акробатика, камера | A |
| `game/ui/` | HUD, пауза, экран смерти, числа урона, диалоговое окно, общий UI-кит | A |
| `game/weapons/` | 5 оружий × 3 аспекта | B |
| `game/boons/` | Дары 6 духов, BoonManager, окно выбора 1 из 3, тотем | B |
| `game/enemies/` | враги, элитки с бронёй, телеграфы, боссы, снаряды, фабрика | C |
| `game/rooms/` | арены с ярусами, двери с наградами, типы комнат, волны, торговец, колодец, «Спор Духов», «Печать Номада» | D |
| `game/hub/` | Стойбище Предков: оружейная, манекен, Сандык, домбра, диалоги/сюжет | E |
| `game/fx/` | общие эффекты (вспышки, частицы, кольца-телеграфы) — любой модуль может добавлять файлы | все |
| `game/scenes/` | title.tscn (главное меню) | E |
| `tools/` | проверки (check.tscn), smoke-тесты, генерация звука | все |

## Автозагрузки (ядро)

- **Bus** (`core/bus.gd`) — все сигналы. Посмотрите список, прежде чем вводить свой.
- **Meta** (`core/meta.gd`) — постоянный прогресс: `ash`, `chest[...]`, `weapons_unlocked`, `aspects_unlocked`, `equipped_weapon/aspect`, `kuis_unlocked`, `kui_prepared`, `story`, `stats`, `last_run`.
- **Run** (`core/run.gd`) — текущий забег: `hp`, `dirhams`, `weapon`, `aspect`, `kui`, `depth`, `biome`, `current_room`, `revives_left`,
  `boons` (BoonManager), `planner` (RoomPlanner). Функции: `stat(key)`, `modify_outgoing(hit, target)`, `modify_incoming(amount, source)`,
  `heal`, `set_hp`, `add_dirhams`, `spend_dirhams`, `add_ash`, `start_run`, `enter_room(room)`, `door_choices()`, `on_player_death(killer) -> bool`,
  `end_run(died, killer, boss)`, `goto_hub`, `spawn_player(parent, pos)`, `spawn_hud(parent)`, `slowmo(scale, secs)`, `register_kill(enemy)`.
- **Sfx** — `Sfx.play("hit")`, `Sfx.music("boss")`. Файлы `assets/sfx/*.wav`, `assets/music/*.wav`. Позиционного звука нет — это ок.

## Бой

`Hit` (`core/hit.gd`) — объект удара (урон, вид, крит, стихия, отбрасывание, оглушение, урон броне, statuses, tags).
Удары героя: `Combat.player_hit(target, hit)` — прогоняет через Run.modify_outgoing (дары, крит, удар в спину) и вызывает `target.take_hit(hit)`.
Поиск целей: `Combat.in_radius / in_cone / along_line / nearest`.

**Группы:**
- `"player"` — герой (один).
- `"hurtable_enemy"` — всё, что герой может бить: враги, манекен, разрушаемые колонны, кувшины. Должно иметь `take_hit(hit: Hit)` и `hit_radius: float`.
- `"enemies"` — только живые враги (для подсчёта волн). Метод `is_dead() -> bool`.
- `"enemy_projectile"` — вражеские снаряды (меч героя их отбивает: метод `reflect(new_owner: Node, dir: Vector3)`).
- `"wall_plate"` — плиты для отскока (необязательно: отскок работает от любой стены).

**Цель обязана** (враги и манекен):
- `take_hit(hit)`: учесть броню, вычесть HP, применить `hit.statuses`, отбрасывание, оглушение, затем `Bus.hit_landed.emit(hit, self)`
  и `Bus.damage_number.emit(pos, amount, kind)` где kind ∈ normal/special/crit/armor/dot. При смерти: `Bus.enemy_killed.emit(self, hit)`, `Run.register_kill(self)`.
- `get_facing() -> Vector3` (для удара в спину), `hit_radius`, `is_dead()`.
- `apply_status(id: String, params: Dictionary)`. Статусы: `burn {dps,time}`, `poison {stacks}` (скверна Ерлика: стаки, урон/сек = stacks*2, при 5+ стаках и смерти — взрыв),
  `bleed {dps,time}`, `slow {mult,time}`, `freeze {time}`, `stun {time}`, `curse {time}` (взрыв проклятия при смерти: `Bus.enemy_killed` + boon делает взрыв), `shock {time}`.
  Враг хранит статусы в `statuses: Dictionary` (id → params с оставшимся временем) — Дары читают `enemy.statuses.has("burn")`.
- `knock(velocity: Vector3)` — отбрасывание. Если отброшенный враг врезается в стену/колонну со скоростью > 6 м/с — урон `wall` (×2 базового в Жер-Су),
  если падает с высоты > 2.5 м — урон `fall`. Тег `wall_slam` / `fall_slam` в Hit.

**Герой** (`game/player/player.gd`, `class_name Player`, CharacterBody3D, группа `"player"`):
- `take_hit(hit)` — получает урон от врагов (учитывая неуязвимость рывка, блок щитом спереди `blocking`/`block_dir`, `Run.modify_incoming`).
  Урон → `Run.set_hp`, `Bus.player_damaged`. При 0 HP → `Run.on_player_death()`; если вернул true — воскрешение с эффектом, иначе смерть-анимация.
- Свойства для оружия: `facing: Vector3` (единичный XZ), `aim_dir() -> Vector3` (к курсору мыши на плоскости героя или по стику / направлению движения),
  `is_on_floor()`, `airborne`, `wall_kick_time` (время последнего отскока, для удара с отскока),
  `lunge(dir: Vector3, speed: float, time: float)` — короткий выпад, `move_lock: float` (замедление/фиксация бега), `blocking: bool`,
  `weapon: WeaponBase`, `sprite: AnimatedSprite3D`, `play_anim(name, speed := 1.0)`, `invulnerable() -> bool`, `teleport_to(pos)`.
- Сигналы шлются через Bus: `player_dashed`, `player_landed`, `player_wall_kick`, `perfect_dodge`, `hp_changed`, `dash_charges_changed`.
- Входы: move_*, jump, dash, slide, attack, special, interact, pause. Оружию герой передаёт: `attack_pressed/released`, `special_pressed/released`.

**Оружие** (`game/weapons/weapon_base.gd`, `class_name WeaponBase extends Node3D`) — дочерний узел героя:
- `var player: Player`, `var id: String`, `var aspect: int`
- `func setup(p_player, p_aspect)`, `func attack_pressed()`, `func attack_released()`, `func special_pressed()`, `func special_released()`
- `func tick(delta)` — вызывается героем каждый кадр; `func is_busy() -> bool` (герой не может рывок/прыжок? — рывок прерывает атаку всегда)
- `func cancel()` — прервать атаку (рывок). `func move_mult() -> float` — множитель скорости бега во время атаки.
- `func air_special()` — особая атака в воздухе сразу после отскока от стены (удар сверху вниз, ×2 по броне) — по умолчанию в базовом классе.
- Фабрика: `WeaponBase.create(id: String) -> WeaponBase` (`game/weapons/weapon_factory.gd`, `static func create(id, aspect)`).
- Метаданные для оружейной: `game/weapons/weapon_data.gd`: `const WEAPONS := {id: {title, desc, range, tempo, aspects: [{title, desc, color}]}}`.

**Дары** (`game/boons/boon_manager.gd`, `class_name BoonManager extends Node`, живёт в Run.boons):
- `reset()`, `add_boon(id)`, `has_boon(id)`, `level_of(id)`, `level_up(id)`, `remove_boon(id) -> int` (возвращает цену продажи в дирхемах),
  `owned() -> Array[{id, level, rarity}]`, `roll_choices(god: String, count := 3) -> Array` (учитывает Run.stat rare/epic_chance),
  `stat_bonus(key) -> float`, `modify_outgoing(hit, target)`, `modify_incoming(amount, source) -> float`.
- Подписывается на Bus (hit_landed, enemy_killed, player_dashed, player_landed, ...) и реализует эффекты.
- Данные: `game/boons/boon_data.gd` — 6 духов (`tengri`, `ai_mergen`, `umai`, `zher_su`, `erlik`, `kokbori`), каждый ~5–6 даров, слоты: attack / special / dash / passive.
- UI выбора: `game/boons/boon_choice.gd` (CanvasLayer): `static func open(parent, god, on_done: Callable)`. Тотем духа: `game/boons/spirit_totem.tscn`
  (Area3D с подсказкой «E — принять дар»; `god: String`; сигнал `taken`). Комната ставит тотем после зачистки.

**Враги** (`game/enemies/`):
- `enemy_base.gd` (`class_name EnemyBase extends CharacterBody3D`): hp, armor (полоса брони у элиток), статусы, отбрасывание, телеграфы (кольцо/конус на земле + красная вспышка за 0.5 с + звук `alert`).
- `enemy_factory.gd`: `static func spawn(type_id: String, parent: Node, pos: Vector3, mods := {}) -> EnemyBase`.
  mods: `{"elite": bool, "element": String (стихия гневного духа для «Спора Духов»), "hp_mult": float, "dmg_mult": float}`.
- `enemy_data.gd`: `const TYPES := {id: {...}}`, `static func pool(biome: int) -> Array` (кто водится в биоме), `const BOSSES := [id по биомам]`.
- Сигнал врага `died(enemy)`. Враги ищут героя через группу "player". Ходят по ярусам: прыжки на уступы, отскоки, перекаты от стрел, фланги.

**Комнаты** (`game/rooms/`):
- `room.tscn` / `room.gd` — читает `Run.current_room`, строит арену (`arena_builder.gd`), спавнит героя и HUD, запускает волны, после зачистки — награда и 2 двери.
- `room_planner.gd` (`class_name RoomPlanner`): `first_room() -> Dictionary`, `make_choices(current_room, rng) -> Array` (2 двери).
- Формат комнаты: `{"type": "combat"|"elite"|"boss"|"merchant"|"duel"|"rest", "reward": "boon"|"ash"|"gold"|"merchant"|"upgrade"|"heal"|"kui",
  "god": String, "god2": String (для duel), "depth": int, "biome": int, "seed": int, "seal": bool (Печать Номада после зачистки)}`.
- Двери: `door.gd` — Area3D, символ награды над аркой (Sprite3D/Label3D иконка), вход → `Run.enter_room(room_dict)`.
- Конец забега: финальный босс биома 2 → `Run.end_run(false, "", boss_id)` (победа) — в Хабе пойдёт сюжетный диалог.

**Хаб** (`game/hub/`): `hub.tscn` — Стойбище Предков: оружейный шатёр (5 стоек + манекен с DPS), шатёр героя с Сандыком, костёр с домброй, выход на тропу (→ `Run.start_run()`).
Сюжет — `story.gd` (диалоги по `Meta.story`, `Meta.last_run`, `Run.hub_reason`), показ через `Bus.dialogue_requested.emit(lines)` — окно рисует `game/ui/dialogue_box.gd` (A).
Интерактивные объекты — `game/hub/interactable.gd` (Area3D, `prompt: String`, сигнал `activated(player)`; герой ищет ближайший в группе `"interactable"` и по `interact` вызывает `activate(player)`).
Этот же interactable используют комнаты (двери, тотемы, торговец, колодец, сундук-печать).

## UI

HUD (`game/ui/hud.tscn`, A): HP-бар, заряды рывка, дирхемы, пепел, иконки даров (по Tab — список с описаниями), оружие+аспект, кюй,
полоса броски элитки над врагом рисует C (Sprite3D/Label3D), числа урона (`Bus.damage_number` → Label3D всплывающие), тосты, пауза (Esc), экран смерти.
Общий UI-кит (`game/ui/ui_kit.gd`): цвета, шрифт, `panel()`, `button()` — используйте его во всех меню, чтобы стиль был единым.
Цвета духов: tengri `#8cc8ff`, ai_mergen `#c9b3ff`, umai `#ff8a3d`, zher_su `#5fd3c4`, erlik `#9b4dff`, kokbori `#e04848`.

## Проверка

- `godot --headless --path . res://tools/check.tscn` — грузит все скрипты/сцены из `game/`, печатает ошибки.
- `godot --headless --path . res://tools/smoke.tscn -- scene=res://game/hub/hub.tscn secs=5` — запускает сцену N секунд, печатает ошибки рантайма.
- Каждый модуль добавляет свой тест-скрипт в `tools/tests/<module>_test.gd` (+ .tscn), который проверяет логику без человека.
