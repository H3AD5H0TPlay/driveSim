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
	if start_coords != null and start_coords.x == -999:
		status_label.text = "Hiba: API Limitáció (Túl sok kérés). Várj egy kicsit!"
		return
	if start_coords == null:
		status_label.text = "Hiba: A kezdőpont nem található!"
		return
		
	status_label.text = "2/4: Célpont keresése (Nominatim)..."
	await get_tree().create_timer(1.2).timeout # Kötelező várakozás a 2. kérés előtt!
	
	var end_coords = await geocode_city(end_input.text)
	if end_coords != null and end_coords.x == -999:
		status_label.text = "Hiba: API Limitáció (Túl sok kérés). Várj egy kicsit!"
		return
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
	$DrivingUI.show()
	vehicle.process_mode = Node.PROCESS_MODE_INHERIT
	vehicle.show()

func _on_itinerary_button_pressed():
	var panel = $DrivingUI/ItineraryPanel
	panel.visible = !panel.visible

func geocode_city(city_name: String):
	# A Nominatim jobban kezeli a free-form szöveget vesszők nélkül
	var safe_name = city_name.replace(",", " ")
	var http = HTTPRequest.new()
	add_child(http)
	var url = "https://nominatim.openstreetmap.org/search?q=" + safe_name.uri_encode() + "&countrycodes=hu&format=json&limit=1"
	http.request(url, ["User-Agent: DriveSim/1.0"])
	
	var response = await http.request_completed
	var response_code = response[1]
	var body = response[3]
	http.queue_free()
	
	if response_code == 429:
		return Vector2(-999, -999)
		
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
	var url = "http://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?overview=full&geometries=geojson&steps=true" % [start.x, start.y, end.x, end.y]
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
	
	var points_3d = []
	for coord in coords:
		var lon = float(coord[0])
		var lat = float(coord[1])
		var dlat = lat - origin_lat
		var dlon = lon - origin_lon
		var z = -dlat * 111320.0
		var x = dlon * 111320.0 * cos(deg_to_rad(origin_lat))
		points_3d.append(Vector3(x, 0, z))
		
	# Hosszabbítsuk meg az utat 20 méterrel hátrafelé, hogy az autó ne lógjon le a peremről!
	if points_3d.size() > 1:
		var dir = (points_3d[1] - points_3d[0]).normalized()
		points_3d.insert(0, points_3d[0] - dir * 20.0)
		
	for p in points_3d:
		curve.add_point(p)
		
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
	
	# Felezővonalak és szélvonalak generálása
	add_child(_create_line_mesh(path, 0.0, 0.2)) # Középső felezővonal
	add_child(_create_line_mesh(path, -3.8, 0.2)) # Bal záróvonal
	add_child(_create_line_mesh(path, 3.8, 0.2)) # Jobb záróvonal
	
	# Főutak (ref) kigyűjtése az OSRM adatokból (azonnal kész)
	var steps = route_data["routes"][0]["legs"][0].get("steps", [])
	var itinerary_text = "[b]Érintett főutak:[/b]\n"
	var added_refs = {}
	for step in steps:
		var ref = step.get("ref", "")
		# Ha a ref tartalmazza az utat (pl. M5, E 75)
		if ref != "" and not added_refs.has(ref):
			itinerary_text += ref + ", "
			added_refs[ref] = true
			
	itinerary_text += "\n\n[b]Érintett települések (töltés...):[/b]\n(Települések lekérdezése API limitációk miatt kikapcsolva)"
	$DrivingUI/ItineraryPanel/RichTextLabel.text = itinerary_text
	
	# Háttérfolyamat indítása a települések letöltéséhez
	# _fetch_settlements_async(coords, itinerary_text)
	
	# Autó pozícionálása az eredeti első pontra (most ez az 1-es indexű, mert a 0-ás az a meghosszabbított kezdés)
	var start_pos = curve.get_point_position(1) if points_3d.size() > 1 else curve.get_point_position(0)
	var next_pos = curve.get_point_position(2) if points_3d.size() > 2 else curve.get_point_position(1)
	
	vehicle.global_position = start_pos + Vector3(0, 2, 0)
	# Irányba állítás a következő pont felé
	var target = next_pos
	target.y = vehicle.global_position.y # Ne nézzen le a földbe
	if start_pos.distance_to(next_pos) > 0.1:
		vehicle.look_at(target, Vector3.UP)
		
	# Minimap beállítása
	$DrivingUI/Minimap.vehicle = vehicle
	$DrivingUI/Minimap.setup(points_3d)

func _fetch_settlements_async(coords: Array, base_text: String):
	var panel_label = $DrivingUI/ItineraryPanel/RichTextLabel
	
	# Mintavételezés sűrűbben (minden 3 km-en), hogy kevesebb település maradjon ki
	var sample_coords = []
	var accumulated_dist = 0.0
	sample_coords.append(coords[0])
	for i in range(1, coords.size()):
		var p1 = Vector2(float(coords[i-1][0]), float(coords[i-1][1]))
		var p2 = Vector2(float(coords[i][0]), float(coords[i][1]))
		var d = p1.distance_to(p2) * 111.0 # kb. távolság km-ben
		accumulated_dist += d
		if accumulated_dist >= 3.0:
			sample_coords.append(coords[i])
			accumulated_dist = 0.0
	sample_coords.append(coords[coords.size()-1])
	
	var current_text = base_text
	var added_places = {}
	var http = HTTPRequest.new()
	add_child(http)
	
	for coord in sample_coords:
		var lon = float(coord[0])
		var lat = float(coord[1])
		var url = "https://nominatim.openstreetmap.org/reverse?lat=%f&lon=%f&format=json&zoom=10" % [lat, lon]
		
		http.request(url, ["User-Agent: DriveSim/1.0"])
		var response = await http.request_completed
		var code = response[1]
		var body = response[3]
		
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				var place = ""
				if data is Dictionary and data.has("address"):
					var addr = data["address"]
					# Előnyben részesítjük a pontosabb településeket
					if addr.has("village"): place = addr["village"]
					elif addr.has("town"): place = addr["town"]
					elif addr.has("city"): place = addr["city"]
					elif addr.has("municipality"): place = addr["municipality"]
				
				if place != "" and not added_places.has(place):
					current_text += "- " + place + "\n"
					panel_label.text = current_text + "(Folyamatban...)"
					added_places[place] = true
		
		# Kötelező 1.2 mp várakozás a Nominatim API szabályzata miatt (Max 1 kérés/mp)
		await get_tree().create_timer(1.2).timeout
		
	http.queue_free()
	panel_label.text = current_text + "\n[i]Útiterv sikeresen betöltve.[/i]"

func _create_line_mesh(path_node: Path3D, offset_x: float, width: float) -> CSGPolygon3D:
	var line = CSGPolygon3D.new()
	line.mode = CSGPolygon3D.MODE_PATH
	line.path_node = path_node.get_path()
	line.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	line.path_interval = 2.0
	
	var profile = PackedVector2Array()
	profile.push_back(Vector2(offset_x - width/2, 0.02))
	profile.push_back(Vector2(offset_x + width/2, 0.02))
	profile.push_back(Vector2(offset_x + width/2, 0.05))
	profile.push_back(Vector2(offset_x - width/2, 0.05))
	
	line.polygon = profile
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	line.material = mat
	return line
