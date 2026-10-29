extends Node3D

## Kertakäyttöinen räjähdysefekti: tulipallo, kipinät, savu ja välähdys.
## Vapauttaa itsensä, kun savu (pisin osa) on päättynyt.

const SMOKE_DELAY: float = 0.1
const FLASH_ENERGY: float = 6.0
const FLASH_TIME: float = 0.3

@onready var fireball: GPUParticles3D = $Fireball
@onready var sparks: GPUParticles3D = $Sparks
@onready var smoke: GPUParticles3D = $Smoke
@onready var flash: OmniLight3D = $Flash


func _ready() -> void:
	fireball.restart()
	sparks.restart()

	smoke.finished.connect(queue_free)

	# Tween on sidottu tähän nodeen, joten se pysähtyy, jos efekti vapautetaan aiemmin.
	flash.light_energy = FLASH_ENERGY
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "light_energy", 0.0, FLASH_TIME)
	tween.tween_callback(smoke.restart).set_delay(SMOKE_DELAY)
