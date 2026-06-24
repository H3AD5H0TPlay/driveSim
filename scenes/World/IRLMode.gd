extends Node3D

@onready var ui_layer = $UI
@onready var start_input = $UI/Panel/StartInput
@onready var end_input = $UI/Panel/EndInput
@onready var status_label = $UI/Panel/StatusLabel
@onready var vehicle = $Vehicle

var path: Path3D
var curve: Curve3D
var road_mesh: CSGPolygon3D

func _ready():
	vehicle.process_mode = Node.PROCESS_MODE_DISABLED
	vehicle.hide()

func _on_drive_button_pressed():
	if start_input.text.is_empty() or end_input.text.is_empty():
		status_label.text = "Kérlek add meg mindkét várost!"
		return
		
	status_label.text = "1/4: Kezdőpont keresése (Nominatim)..."
	var start_coords = await geocode_city(start_input.text)
	if start_coords == null:
		status_label.text = "Hiba: A kezdőpont nem található!"
		return
		
	status_label.text = "2/4: Célpont keresése (Nominatim)..."
	var end_coords = await geocode_city(end_input.text)
	if end_coords == null:
		status_label.text = "Hiba: A célpont nem található!"
		return
		
	status_label.text = "3/4: Útvonal letöltése (OSRM)..."
	var route_data = await get_osrm_route(start_coords, end_coords)
	if route_data == null:
		status_label.text = "Hiba: Nem sikerült útvonalat tervezni!"
		return
		
	status_label.text = "4/4: 3D út generálása..."
	generate_road(route_data)
	
	ui_layer.hide()
	vehicle.process_mode = Node.PROCESS_MODE_INHERIT
	vehicle.show()

func geocode_city(city_name: String):
	var http = HTTPRequest.new()
	add_child(http)
	var url = "https://nominatim.openstreetmap.org/search?q=" + city_name.uri_encode() + ",Hungary&format=json&limit=1"
	http.request(url, ["User-Agent: DriveSim/1.0"])
	
	var response = await http.request_completed
	var response_code = response[1]
	var body = response[3]
	http.queue_free()
	
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.get_data()
			if data is Array and data.size() > 0:
				var lon = float(data[0]["lon"])
				var lat = float(data[0]["lat"])
				return Vector2(lon, lat)
	return null

func get_osrm_route(start: Vector2, end: Vector2):
	var http = HTTPRequest.new()
	add_child(http)
	var url = "http://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?overview=full&geometries=geojson" % [start.x, start.y, end.x, end.y]
	http.request(url)
	
	var response = await http.request_completed
	var response_code = response[1]
	var body = response[3]
	http.queue_free()
	
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			return json.get_data()
	return null

func generate_road(route_data: Dictionary):
	var coords = route_data["routes"][0]["geometry"]["coordinates"]
	if coords.size() < 2:
		return
		
	path = Path3D.new()
	curve = Curve3D.new()
	path.curve = curve
	add_child(path)
	
	var origin_lon = float(coords[0][0])
	var origin_lat = float(coords[0][1])
	
	for coord in coords:
		var lon = float(coord[0])
		var lat = float(coord[1])
		
		var dlat = lat - origin_lat
		var dlon = lon - origin_lon
		
		# 1 fok szélesség ~ 111320 méter
		# Z tengely a Godot-ban: +Z dél, -Z észak
		var z = -dlat * 111320.0
		# X tengely a Godot-ban: +X kelet, -X nyugat
		var x = dlon * 111320.0 * cos(deg_to_rad(origin_lat))
		
		curve.add_point(Vector3(x, 0, z))
		
	road_mesh = CSGPolygon3D.new()
	road_mesh.mode = CSGPolygon3D.MODE_PATH
	road_mesh.path_node = path.get_path()
	road_mesh.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	road_mesh.path_interval = 2.0
	
	var profile = PackedVector2Array()
	profile.push_back(Vector2(-6, -0.5))
	profile.push_back(Vector2(-4, 0))
	profile.push_back(Vector2(4, 0))
	profile.push_back(Vector2(6, -0.5))
	road_mesh.polygon = profile
	road_mesh.use_collision = true
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	road_mesh.material = mat
	add_child(road_mesh)
	
	# Autó pozícionálása az első pontra, a második pont irányába nézve
	var start_pos = curve.get_point_position(0)
	var next_pos = curve.get_point_position(1)
	
	vehicle.global_position = start_pos + Vector3(0, 2, 0)
	# Irányba állítás a következő pont felé
	var target = next_pos
	target.y = vehicle.global_position.y # Ne nézzen le a földbe
	if start_pos.distance_to(next_pos) > 0.1:
		vehicle.look_at(target, Vector3.UP)
