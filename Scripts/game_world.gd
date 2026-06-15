extends Node3D

const DEFAULT_LIGHT_COLOR : Color = Color8(255, 255, 255)

@export var lights : Array[Light3D]

func set_light_color(color: Color) -> void:
	for light in lights:
		light.light_color = color
	
func flash_light_color(color: Color, duration: float) -> void:
	set_light_color(color)
	await get_tree().create_timer(duration).timeout
	set_light_color(DEFAULT_LIGHT_COLOR)
