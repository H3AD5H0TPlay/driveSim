extends Control

func _on_random_drive_pressed():
	get_tree().change_scene_to_file("res://scenes/World/RandomDrive.tscn")

func _on_irl_mode_pressed():
	get_tree().change_scene_to_file("res://scenes/World/IRLMode.tscn")
