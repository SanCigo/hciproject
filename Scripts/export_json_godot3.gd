tool
extends SceneTree

func _init():
	var file = File.new()
	# Change this path if your downloaded file is elsewhere
	if file.open("res://gestures/p_c_data.dat", File.READ) == OK:
		var data = file.get_var()
		file.close()
		
		var export_data = []
		for gesture in data:
			var name = gesture[0]
			var points = gesture[1]
			var py_points = []
			for pt in points:
				# pt[0] is the Vector3, pt[1] is the Controller ID
				py_points.append({"x": pt[0].x, "y": pt[0].y, "z": pt[0].z})
			export_data.append({"name": name, "points": py_points})
			
		var out = File.new()
		out.open("res://gestures/p_c_data.json", File.WRITE)
		out.store_string(to_json(export_data))
		out.close()
		print("Successfully converted p_c_data.dat to p_c_data.json")
	else:
		print("ERROR: Could not find p_c_data.dat in the project root! Please place it there.")
	
	quit()
