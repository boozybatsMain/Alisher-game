extends Node
## Глобальная шина событий. Все модули общаются через неё, чтобы не зависеть друг от друга напрямую.
## Дары (game/boons) слушают боевые события; HUD слушает всё про ресурсы; комнаты — про врагов.

# --- бой ---
signal hit_landed(hit: Hit, target: Node)          ## после применения удара к цели (урон уже вычтен)
signal enemy_killed(enemy: Node, hit: Hit)         ## враг умер (hit — добивающий удар, может быть null)
signal player_damaged(amount: float, source: Node) ## герой получил урон (после брони/блока)
signal player_died
signal player_revived(charges_left: int)
signal player_dashed(from: Vector3, to: Vector3)   ## рывок завершён
signal player_landed(fall_height: float)           ## приземление после прыжка/падения
signal player_wall_kick(pos: Vector3)              ## отскок от стены
signal perfect_dodge(attacker: Node)               ## уклонение в последний момент (рывок сквозь атаку)
signal damage_number(pos: Vector3, amount: float, kind: String)  ## kind: normal/special/crit/heal/armor/dot/player
signal shake(strength: float, duration: float)
signal hitstop(duration: float)

# --- ресурсы и забег ---
signal hp_changed(hp: float, max_hp: float)
signal dash_charges_changed(charges: int, max_charges: int)
signal dirhams_changed(value: int)
signal ash_changed(value: int)
signal boons_changed
signal weapon_changed(weapon_id: String, aspect: int)
signal room_cleared                                ## последняя волна комнаты уничтожена
signal room_entered(room: Dictionary)
signal wave_started(index: int, total: int)
signal toast(text: String, color: Color)           ## короткое уведомление в центре экрана
signal dialogue_requested(lines: Array)            ## [{speaker, text}] — показать диалог
