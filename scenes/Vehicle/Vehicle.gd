extends VehicleBody3D

const MAX_ENGINE_FORCE = 1500.0
const MAX_BRAKE_FORCE = 150.0
const MAX_STEER_ANGLE = 0.5

@onready var speed_label = $HUD/SpeedLabel

func _physics_process(delta):
	# Alapvető manuális irányítás a teszteléshez
	var steer_val = 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		steer_val = MAX_STEER_ANGLE
	elif Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		steer_val = -MAX_STEER_ANGLE
	
	steering = lerp(steering, steer_val, 5.0 * delta)

	var accel = 0.0
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		accel = -MAX_ENGINE_FORCE
	elif Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		accel = MAX_ENGINE_FORCE

	engine_force = accel
	
	if Input.is_action_pressed("ui_accept"): # Szóköz - Fék
		brake = MAX_BRAKE_FORCE
	else:
		brake = 0.0
		
	# Sebességmérő frissítése
	if speed_label:
		# Valós sebesség (hossz) m/s-ban, majd átváltva km/h-ra
		var speed_kmh = linear_velocity.length() * 3.6
		speed_label.text = "%d km/h" % int(speed_kmh)
