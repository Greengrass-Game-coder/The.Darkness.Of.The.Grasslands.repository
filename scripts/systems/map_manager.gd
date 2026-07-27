class_name MapManager
extends Node

# Color codes from blueprint
const COLOR_WALKABLE: Color = Color(1, 1, 1)       # White
const COLOR_WALL: Color = Color(0, 0, 0)            # Black
const COLOR_DOOR: Color = Color(0.545, 0.271, 0.075)  # Brown (#8B4513)
const COLOR_PUZZLE: Color = Color(0.639, 0.286, 0.643) # Purple (#A349A4)
const COLOR_KILLER_SPAWN: Color = Color(0.929, 0.11, 0.141)  # Red (#ED1C24)
const COLOR_SURVIVOR_SPAWN: Color = Color(0.247, 0.282, 0.8)  # Blue (#3F48CC)
const COLOR_STAIRS: Color = Color(0, 0.635, 0.91)   # Cyan (#00A2E8)

# Tolerance for color matching
const COLOR_TOLERANCE: float = 0.05

# Grid cell size for collision generation (pixels)
const GRID_SIZE: int = 32

# Minimum distance from killer spawn for survivor spawn (pixels)
const KILLER_SAFE_RADIUS: float = 300.0

# Blueprint path (relative to res://)
const BLUEPRINT_DIR: String = "res://The Darkness Of The Grasslands assets/Maps/COLOR CODED MAPS/"
const MAP_DIR: String = "res://The Darkness Of The Grasslands assets/Maps/Maps/"

# ---- Spawn / Marker data ----
var survivor_spawns: Array[Vector2] = []
var killer_spawns: Array[Vector2] = []
var stairs_positions: Array[Vector2] = []
var puzzle_positions: Array[Vector2] = []
var door_positions: Array[Vector2] = []

var blueprint_size: Vector2i = Vector2i.ZERO
var blueprint_image: Image = null
var _raw_data: PackedByteArray = PackedByteArray()
var _wall_color_int: int = 0


func load_blueprint(blueprint_name: String) -> bool:
	"""
	Load a blueprint PNG and extract all game data (spawns, walls, markers).
	The blueprint file should be named like 'Map_Test [COLOR CODED].png'.
	Pass just 'Map_Test' as the name.
	"""
	var path: String = BLUEPRINT_DIR + blueprint_name + " [COLOR CODED].png"
	
	var _tex: Texture2D = load(path)
	if _tex:
		blueprint_image = _tex.get_image()
	if not blueprint_image or blueprint_image.is_empty():
		push_error("MapManager: Could not load blueprint: ", path)
		return false
	
	blueprint_size = blueprint_image.get_size()
	_raw_data = blueprint_image.get_data()
	_wall_color_int = _color_to_int(COLOR_WALL)
	print("MapManager: Loaded blueprint ", blueprint_size.x, "x", blueprint_size.y)
	
	# Clear previous data
	survivor_spawns.clear()
	killer_spawns.clear()
	stairs_positions.clear()
	puzzle_positions.clear()
	door_positions.clear()
	
	# Scan the blueprint to find colored regions
	_scan_blueprint()
	
	print("MapManager: Found:")
	print("  Survivor spawns: ", survivor_spawns.size())
	print("  Killer spawns: ", killer_spawns.size())
	print("  Stairs: ", stairs_positions.size())
	print("  Puzzles: ", puzzle_positions.size())
	print("  Doors: ", door_positions.size())
	
	return true


func get_map_visual_path(blueprint_name: String) -> String:
	return MAP_DIR + blueprint_name + ".png"


func build_collision(parent_node: Node) -> void:
	"""
	Read the blueprint's black (wall) pixels and generate CollisionPolygon2D
	collision shapes on a StaticBody2D.
	Uses grid sampling + polygon outline extraction for seamless collision
	without corner-catching seams between adjacent rectangles.
	"""
	if not blueprint_image:
		push_error("MapManager: No blueprint loaded")
		return
	
	var wall_body := StaticBody2D.new()
	wall_body.name = "WallCollision"
	wall_body.collision_layer = 4  # Layer 3 = walls
	parent_node.add_child(wall_body)
	
	var grid_w: int = ceili(float(blueprint_size.x) / GRID_SIZE)
	var grid_h: int = ceili(float(blueprint_size.y) / GRID_SIZE)
	
	# Step 1: Build a grid of wall/no-wall at GRID_SIZE resolution
	# using multi-point sampling (center + 4 corners) for reliability
	var wall_grid: Array[Array] = []
	wall_grid.resize(grid_h)
	for gy in range(grid_h):
		wall_grid[gy] = []
		wall_grid[gy].resize(grid_w)
		for gx in range(grid_w):
			wall_grid[gy][gx] = _is_grid_cell_wall(gx, gy)
	
	# Step 2: Find connected wall regions via flood fill
	var visited: Array[Array] = []
	visited.resize(grid_h)
	for gy in range(grid_h):
		visited[gy] = []
		visited[gy].resize(grid_w)
		for gx in range(grid_w):
			visited[gy][gx] = false
	
	# Directions: up, right, down, left (clockwise)
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
	]
	
	var total_polygons: int = 0
	
	for start_gy in range(grid_h):
		for start_gx in range(grid_w):
			if not wall_grid[start_gy][start_gx] or visited[start_gy][start_gx]:
				continue
			
			# BFS to collect all cells in this connected region
			var region_cells: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(start_gx, start_gy)]
			visited[start_gy][start_gx] = true
			
			while queue.size() > 0:
				var cell: Vector2i = queue.pop_front()
				region_cells.append(cell)
				for d in dirs:
					var nx: int = cell.x + d.x
					var ny: int = cell.y + d.y
					if nx >= 0 and nx < grid_w and ny >= 0 and ny < grid_h \
							and wall_grid[ny][nx] and not visited[ny][nx]:
						visited[ny][nx] = true
						queue.append(Vector2i(nx, ny))
			
			if region_cells.is_empty():
				continue
			
			# Step 3: Extract boundary polygon from region cells
			var polygon: Array[Vector2] = _extract_region_polygon(region_cells)
			if polygon.size() >= 3:
				var col_poly := CollisionPolygon2D.new()
				col_poly.polygon = polygon
				wall_body.add_child(col_poly)
				total_polygons += 1
	
	print("MapManager: Created ", total_polygons, " wall collision polygons (seamless)")


func get_spawn_point(for_killer: bool = false) -> Vector2:
	"""
	Get a random spawn point. If for_killer is false (survivor),
	exclude spawns too close to any killer spawn.
	"""
	if for_killer:
		if killer_spawns.is_empty():
			return Vector2.ZERO
		return killer_spawns[randi() % killer_spawns.size()]
	
	# Survivor: filter out spawns near killer spawns
	var safe_spawns: Array[Vector2] = []
	for spawn in survivor_spawns:
		var is_safe: bool = true
		for kspawn in killer_spawns:
			if spawn.distance_to(kspawn) < KILLER_SAFE_RADIUS:
				is_safe = false
				break
		if is_safe:
			safe_spawns.append(spawn)
	
	# If somehow all are unsafe, just use all of them
	if safe_spawns.is_empty():
		safe_spawns = survivor_spawns
	
	if safe_spawns.is_empty():
		return Vector2.ZERO
	
	return safe_spawns[randi() % safe_spawns.size()]


# ----------------- Private -----------------

func _scan_blueprint() -> void:
	"""
	Scan the entire blueprint using raw byte data for speed.
	7M pixels scanned via get_pixel() is too slow - use get_data() instead.
	"""
	# RGBA8 format: 4 bytes per pixel, stored row by row
	var stride: int = blueprint_size.x * 4
	
	var survivor_pixels: Array[Vector2i] = []
	var killer_pixels: Array[Vector2i] = []
	var stairs_pixels: Array[Vector2i] = []
	var puzzle_pixels: Array[Vector2i] = []
	var door_pixels: Array[Vector2i] = []
	
	var col_surv: int = _color_to_int(COLOR_SURVIVOR_SPAWN)
	var col_kill: int = _color_to_int(COLOR_KILLER_SPAWN)
	var col_stairs: int = _color_to_int(COLOR_STAIRS)
	var col_puzzle: int = _color_to_int(COLOR_PUZZLE)
	var col_door: int = _color_to_int(COLOR_DOOR)
	
	var bw: int = blueprint_size.x
	var bh: int = blueprint_size.y
	
	for y in range(bh):
		var row_start: int = y * stride
		for x in range(bw):
			var idx: int = row_start + x * 4
			var r: int = _raw_data[idx]
			var g: int = _raw_data[idx + 1]
			var b: int = _raw_data[idx + 2]
			# Skip alpha
			var pixel_val: int = (r << 16) | (g << 8) | b
			
			if pixel_val == _wall_color_int:
				pass  # handled by build_collision
			elif pixel_val == col_surv:
				survivor_pixels.append(Vector2i(x, y))
			elif pixel_val == col_kill:
				killer_pixels.append(Vector2i(x, y))
			elif pixel_val == col_stairs:
				stairs_pixels.append(Vector2i(x, y))
			elif pixel_val == col_puzzle:
				puzzle_pixels.append(Vector2i(x, y))
			elif pixel_val == col_door:
				door_pixels.append(Vector2i(x, y))
	
	if not survivor_pixels.is_empty():
		survivor_spawns = _cluster_centers(survivor_pixels)
	if not killer_pixels.is_empty():
		killer_spawns = _cluster_centers(killer_pixels)
	if not stairs_pixels.is_empty():
		stairs_positions = _cluster_centers(stairs_pixels)
	if not puzzle_pixels.is_empty():
		puzzle_positions = _cluster_centers(puzzle_pixels)
	if not door_pixels.is_empty():
		door_positions = _cluster_centers(door_pixels)


func _cluster_centers(pixels: Array[Vector2i]) -> Array[Vector2]:
	"""
	Group pixels into clusters (regions) and return the center of each cluster.
	Uses a simple flood-fill approach.
	"""
	if pixels.is_empty():
		return []
	
	var unvisited: Dictionary = {}
	for p in pixels:
		unvisited[p] = true
	
	var centers: Array[Vector2] = []
	var remaining: Array = unvisited.keys()
	
	while not remaining.is_empty():
		var start: Vector2i = remaining[0] as Vector2i
		var cluster: Array[Vector2i] = _flood_fill(start, unvisited)
		
		# Remove cluster pixels from unvisited
		for p in cluster:
			unvisited.erase(p)
		
		# Calculate center
		var sum_x: float = 0.0
		var sum_y: float = 0.0
		for p in cluster:
			sum_x += p.x
			sum_y += p.y
		
		centers.append(Vector2(sum_x / cluster.size(), sum_y / cluster.size()))
		remaining = unvisited.keys()
	
	return centers


func _flood_fill(start: Vector2i, unvisited: Dictionary) -> Array[Vector2i]:
	"""Simple BFS flood fill to find connected region."""
	var cluster: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	var visited_local: Dictionary = {}
	visited_local[start] = true
	
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		cluster.append(p)
		
		var neighbors: Array[Vector2i] = [
			Vector2i(p.x + 1, p.y),
			Vector2i(p.x - 1, p.y),
			Vector2i(p.x, p.y + 1),
			Vector2i(p.x, p.y - 1),
		]
		
		for n in neighbors:
			if not visited_local.has(n) and unvisited.has(n):
				visited_local[n] = true
				queue.append(n)
	
	return cluster


func _is_grid_cell_wall(gx: int, gy: int) -> bool:
	"""Check if a grid cell (at GRID_SIZE resolution) is a wall using multi-point sampling.
	Samples 9 points (3x3 grid) within the cell — if most are wall, it's a wall cell.
	This is far more reliable than single-pixel center sampling."""
	var start_x: int = gx * GRID_SIZE
	var start_y: int = gy * GRID_SIZE
	var end_x: int = mini(start_x + GRID_SIZE, blueprint_size.x)
	var end_y: int = mini(start_y + GRID_SIZE, blueprint_size.y)
	
	# Sample a 3x3 grid of points within the cell for robust wall detection
	var wall_count: int = 0
	var total_samples: int = 0
	
	for sy in range(3):
		for sx in range(3):
			var px: int = start_x + int(float(end_x - start_x) * (sx + 1) / 4.0)
			var py: int = start_y + int(float(end_y - start_y) * (sy + 1) / 4.0)
			px = clampi(px, 0, blueprint_size.x - 1)
			py = clampi(py, 0, blueprint_size.y - 1)
			
			var idx: int = py * blueprint_size.x * 4 + px * 4
			var r: int = _raw_data[idx]
			var g: int = _raw_data[idx + 1]
			var b: int = _raw_data[idx + 2]
			var pixel_val: int = (r << 16) | (g << 8) | b
			
			if pixel_val == _wall_color_int:
				wall_count += 1
			total_samples += 1
	
	# If more than half the samples are wall, mark the cell as wall
	return wall_count >= total_samples * 0.5


func _color_to_int(color: Color) -> int:
	"""Convert a Color to an int for fast byte comparison (RRGGBB)."""
	return (roundi(color.r * 255) << 16) | (roundi(color.g * 255) << 8) | roundi(color.b * 255)


func _match_color(a: Color, b: Color) -> bool:
	"""Check if two colors match within tolerance."""
	return abs(a.r - b.r) < COLOR_TOLERANCE and abs(a.g - b.g) < COLOR_TOLERANCE and abs(a.b - b.b) < COLOR_TOLERANCE


func _extract_region_polygon(region_cells: Array[Vector2i]) -> Array[Vector2]:
	"""Extract the outer boundary polygon of a connected wall region.
	Uses edge-following: for each wall cell, checks which edges border
	a non-wall cell (exposed), collects all exposed edge segments,
	then sorts them into a continuous closed polygon.
	This produces seamless collision without corner-catching seams."""
	if region_cells.is_empty():
		return []
	
	# Build a set for O(1) neighbor lookups
	var cell_set: Dictionary = {}
	for cell: Vector2i in region_cells:
		cell_set[Vector2i(cell.x, cell.y)] = true
	
	# Collect all boundary edge segments (each edge = [from, to] in world coords)
	# Using a dict with edge key to avoid duplicates
	var edge_set: Dictionary = {}
	
	for cell: Vector2i in region_cells:
		var gx: int = cell.x
		var gy: int = cell.y
		var x0: float = gx * GRID_SIZE
		var y0: float = gy * GRID_SIZE
		var x1: float = (gx + 1) * GRID_SIZE
		var y1: float = (gy + 1) * GRID_SIZE
		
		# Top edge: exposed if cell above is not a wall
		if not cell_set.get(Vector2i(gx, gy - 1), false):
			var edge_key: String = "%d_%d_%d_%d" % [x0, y0, x1, y0]
			edge_set[edge_key] = [Vector2(x0, y0), Vector2(x1, y0)]
		
		# Right edge: exposed if cell to the right is not a wall
		if not cell_set.get(Vector2i(gx + 1, gy), false):
			var edge_key: String = "%d_%d_%d_%d" % [x1, y0, x1, y1]
			edge_set[edge_key] = [Vector2(x1, y0), Vector2(x1, y1)]
		
		# Bottom edge: exposed if cell below is not a wall
		if not cell_set.get(Vector2i(gx, gy + 1), false):
			var edge_key: String = "%d_%d_%d_%d" % [x1, y1, x0, y1]
			edge_set[edge_key] = [Vector2(x1, y1), Vector2(x0, y1)]
		
		# Left edge: exposed if cell to the left is not a wall
		if not cell_set.get(Vector2i(gx - 1, gy), false):
			var edge_key: String = "%d_%d_%d_%d" % [x0, y1, x0, y0]
			edge_set[edge_key] = [Vector2(x0, y1), Vector2(x0, y0)]
	
	if edge_set.is_empty():
		return []
	
	# Convert dict values to array for sorting
	var edges: Array = edge_set.values()
	
	# Sort edges into a continuous polygon by matching endpoints
	var polygon: Array[Vector2] = []
	var remaining: Array = edges.duplicate()
	
	# Start from the first edge
	var first_edge: Array = remaining.pop_front()
	polygon.append(first_edge[0])
	polygon.append(first_edge[1])
	var current_point: Vector2 = first_edge[1]
	
	var max_iter: int = remaining.size() * 2
	var iter_count: int = 0
	
	while not remaining.is_empty() and iter_count < max_iter:
		iter_count += 1
		var found: bool = false
		
		for i in range(remaining.size()):
			var edge: Array = remaining[i]
			var edge_from: Vector2 = edge[0]
			var edge_to: Vector2 = edge[1]
			
			if edge_from.distance_squared_to(current_point) < 0.01:
				current_point = edge_to
				polygon.append(current_point)
				remaining.remove_at(i)
				found = true
				break
			elif edge_to.distance_squared_to(current_point) < 0.01:
				current_point = edge_from
				polygon.append(current_point)
				remaining.remove_at(i)
				found = true
				break
		
		if not found:
			# Broken chain — shouldn't happen with closed boundaries
			break
	
	# Remove the last point if it duplicates the first (closed polygon)
	if polygon.size() >= 2 and polygon[0].distance_squared_to(polygon[polygon.size() - 1]) < 0.01:
		polygon.remove_at(polygon.size() - 1)
	
	# Simplify: remove collinear points to reduce vertex count
	# A point is collinear if the cross product of (prev->curr) and (curr->next) is near zero
	if polygon.size() >= 3:
		var simplified: Array[Vector2] = []
		simplified.append(polygon[0])
		for i in range(1, polygon.size() - 1):
			var prev: Vector2 = polygon[i - 1]
			var curr: Vector2 = polygon[i]
			var next_pt: Vector2 = polygon[i + 1]
			var v1: Vector2 = curr - prev
			var v2: Vector2 = next_pt - curr
			var cross: float = abs(v1.cross(v2))
			if cross > 0.5:  # Threshold: keep non-collinear points
				simplified.append(curr)
		simplified.append(polygon[polygon.size() - 1])
		polygon = simplified
	
	return polygon
