extends Node3D

func _ready():
	randomize()
	generate_road()

func generate_road():
	var path = Path3D.new()
	var curve = Curve3D.new()
	path.curve = curve
	add_child(path)
	
	var current_pos = Vector3(0, 0, 0)
	curve.add_point(current_pos)
	
	# Generálunk 100 szegmensnyi utat
	for i in range(1, 100):
		var z_dist = randf_range(30.0, 50.0)
		var x_offset = randf_range(-25.0, 25.0)
		current_pos += Vector3(x_offset, 0, -z_dist)
		
		# Sima kanyarokhoz kontroll pontok beállítása (előző pont felé mutat a "be", következő felé a "ki")
		# A Godot Curve3D add_point sorrendje: position, in, out
		curve.add_point(current_pos, Vector3(0, 0, z_dist/2.5), Vector3(0, 0, -z_dist/2.5))
		
	# Út 3D hálójának generálása a görbe mentén
	var road_mesh = CSGPolygon3D.new()
	road_mesh.mode = CSGPolygon3D.MODE_PATH
	road_mesh.path_node = path.get_path()
	road_mesh.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	road_mesh.path_interval = 2.0
	
	# Út profilja (egy 8 méter széles, 0.5 magas domború forma)
	var profile = PackedVector2Array()
	profile.push_back(Vector2(-5, -0.5)) # Bal alsó perem
	profile.push_back(Vector2(-4, 0))    # Bal felső perem
	profile.push_back(Vector2(4, 0))     # Jobb felső perem
	profile.push_back(Vector2(5, -0.5))  # Jobb alsó perem
	road_mesh.polygon = profile
	road_mesh.use_collision = true
	
	# Aszfalt anyag
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	road_mesh.material = mat
	
	add_child(road_mesh)
