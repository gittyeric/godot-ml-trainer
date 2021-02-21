extends Node

# Overridable settings
# All output file types should be written outside of this
# directory or Godot will try to import them!  Be sure
# snapshots/ exists in godot-ml-trainer's parent directory!
const snapshotFolder = "../snapshots"
const labelsFile = '../labels'
# Max number of random objects dropped into scene
const maxObjectInstances = 140
# Max scale factor randomly applied to objects
const maxObjectScale = 0.1 # 10%
# Seconds before taking a snapshot and resetting environment
const secs_between_reset = 4
# Speeds up simulation time for faster training data generatation
# Speeding up too much may cause physics issues
const timeMultiplier = 50
# Wait this many seconds after training data is saved to debug label result
const debug_secs = 0 * timeMultiplier
# All settings devoted to randomizing the camera angle
# This assumes an overhead view looking down
const maxJitterDegrees = 9
const maxDistanceFromCenter = 0.5 # For both X and Z
const maxCameraLift = 20   # For Y axis
# All settings for lighting
const max_lights = 5
const min_range = 50.0
const max_range = 90
const min_attentuation = 0.1
const max_attentuation = 0.9
const max_light_lift = 200
const min_light_lift = 35
const max_light_dist_from_center = 10

# Global state
var randomizer = RandomNumberGenerator.new()
var secs_since_reset = 0
var originalCameraPos = null
var originalCameraRotation = null
var camera = null
var ground = null
var debugBox = null
var objects = [
	preload("res://wooden_crate.tscn"),
	preload("res://redyellow_apple.tscn")
]
var backgrounds = [
	"res://feet.jpg",
	"res://grass.jpg",
	"res://metal.jpg",
	"res://wood.jpg",
	"res://sand.jpg",
	"res://rubble.jpg"
]
var background_textures = []
var loadedOmnilight = preload("res://omniLight.tscn")
var currentObjects = []
var currentLights = []
var iterations = -1
var csv_file = null
# 0 for sim running, 1 for debug wait mode,
# with a training image snapshot taken inbetween
var phase = 0 

func _ready():
	randomizer.randomize()
	csv_file = File.new()
	csv_file.open(labelsFile + str(randomizer.randi()) + ".csv", File.WRITE_READ)
	
	Engine.time_scale = timeMultiplier
	Engine.iterations_per_second = 30 * timeMultiplier
	camera = get_node("Camera")
	ground = get_node("Ground/MeshInstance")
	debugBox = get_node("Camera/DebugOverlay")
	
	# Store camera position for restoration later
	originalCameraPos = camera.transform.origin
	originalCameraRotation = camera.transform.basis
	
	for i in range(backgrounds.size()):
		background_textures.append(load_image_texture(backgrounds[i]))
	
	reset_environment()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	secs_since_reset += delta
	# Take a snapshot 2 seconds after start of application
	if secs_since_reset > secs_between_reset:
		if phase == 0:
			phase = -1
			for i in range(currentObjects.size()):
				# Set mode to static to stop it from moving
				currentObjects[i].set_mode(1)
			# Skip 1 frame to let the mode update settle
			yield(get_tree(), "idle_frame")
			takeLabelledSnapshot(iterations)
			phase = 1
		elif phase == 1 and secs_since_reset > (secs_between_reset + debug_secs):
			phase = 0
			secs_since_reset = 0
			reset_environment()

func reset_environment():
	iterations += 1
	# Remove old environment first
	for i in range(currentObjects.size()):
		remove_child(currentObjects[i])
	currentObjects = []
	
	randomizeBackground(ground)
	randomizeCameraAngle()
	# Reset debug bounding box to empty
	debugBox.handle_bounding_box_update([])
	
	for i in range(randomizer.randi_range(1, maxObjectInstances)):
		var randomObjType = objects[randomizer.randi() % objects.size()]
		var obj = randomObjType.instance()
		randomizeNodeInRect(obj, -3.5, 3, -3.5, 3, 15, 3)
		# 1 / 5 odds we hack the color
		if randomizer.randi() % 5 == 0:
			randomizeColor(obj.get_child(0))
		# Randomly scale the size a bit
		var rand_scalar = randomizer.randf_range(1 - maxObjectScale, 1 + maxObjectScale)
		#obj.scaled(Vector3(rand_scalar, rand_scalar, rand_scalar))
		obj.transform.basis.x *= rand_scalar
		obj.transform.basis.y *= rand_scalar
		obj.transform.basis.z *= rand_scalar
		add_child(obj)
		# Shove the object down to save time
		obj.apply_impulse(Vector3(0, -1, 0), Vector3(0, -9.8, 0))
		currentObjects.append(obj)
		randomizeLighting()

# Takes a snapshot of the scene and appends the associated
# label to labels.csv
# Warning! This function takes 2 frames to complete!
func takeLabelledSnapshot(counter):
	# super long random_id to almost ensure stateless uniqueness
	var random_id = str(counter) + "-" + str(randomizer.randi()) + str(randomizer.randi())
	
	var img_filename = random_id + ".png"
	var highest_obj = findHighestObj(currentObjects)
	var bounding_box = find2dBoundingBox(highest_obj)
	var csvRow = formatCsvRow(img_filename, bounding_box)
	
	# Only log the image if valid
	# Invalid case 1: object went through floor
	var invalid_solution = false
	if highest_obj.transform.origin.y < 0:
		invalid_solution = true
	if not Rect2(Vector2(0, 0), get_viewport().get_size()).encloses(bounding_box):
		invalid_solution = true
	if invalid_solution:
		print("Skipping invalid training datum")
	
	csv_file.store_line(csvRow)
	queueCameraSnapshot(snapshotFolder + "/" + img_filename)
	debugBox.handle_bounding_box_update([bounding_box])
	return random_id

# Warning! This function takes 2 frames to complete!
func queueCameraSnapshot(filename):
	var img = get_viewport().get_texture().get_data()
	# wait two frames
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	img.flip_y()
	img.save_png(filename)

func formatCsvRow(img_filename, bounding_box):
	return img_filename + "," + str(bounding_box.position.x) + "," + str(bounding_box.position.y) + "," + str(bounding_box.end.x) + "," + str(bounding_box.end.y)

# Returns the obj in the objs array that contains the largest Y value
func findHighestObj(objs):
	var maxY = -9223372036854775807
	var maxObj = null
	for i in range(objs.size()):
		var obj = objs[i]
		var mdt = MeshDataTool.new()
		var mesh_obj = obj.get_child(0)
		mdt.create_from_surface(mesh_obj.mesh, 0)
	
		for j in range(mdt.get_vertex_count()):
			var vertex = mesh_obj.global_transform.xform(mdt.get_vertex(j))
			if vertex.y >= maxY:
				maxY = vertex.y
				maxObj = obj
	return maxObj

# Find the bounding box of a 3d object from the camera's perspective
func find2dBoundingBox(obj):
	var minX = 9223372036854775807
	var maxX = -9223372036854775807
	var minY = 9223372036854775807
	var maxY = -9223372036854775807
	
	var mdt = MeshDataTool.new()
	var mesh_child = obj.get_child(0)
	mdt.create_from_surface(mesh_child.mesh, 0)
	
	for i in range(mdt.get_vertex_count()):
		var vertex = mesh_child.global_transform.xform(mdt.get_vertex(i))
		var vector2d = camera.unproject_position(vertex)
		minX = min(minX, vector2d.x)
		minY = min(minY, vector2d.y)
		maxX = max(maxX, vector2d.x)
		maxY = max(maxY, vector2d.y)
	return Rect2(minX, minY, maxX - minX, maxY - minY)

func degreesToRads(degrees):
	return degrees * 0.0174533

func randomizeCameraAngle():
	# First reset camera to original position
	camera.transform.origin = originalCameraPos
	camera.transform.basis = originalCameraRotation
	# Now rotate and move camera by a random amount within the bounds above
	var randomXRotation = randomizer.randf_range(-maxJitterDegrees, maxJitterDegrees)
	var randomYRotation = randomizer.randf_range(-maxJitterDegrees, maxJitterDegrees)
	var randomZRotation = randomizer.randf_range(-maxJitterDegrees, maxJitterDegrees)
	var randomX = randomizer.randf_range(-maxDistanceFromCenter, maxDistanceFromCenter)
	var randomY = randomizer.randf_range(0, maxCameraLift)
	var randomZ = randomizer.randf_range(-maxDistanceFromCenter, maxDistanceFromCenter)
	camera.transform.origin.x += randomX
	camera.transform.origin.y += randomY
	camera.transform.origin.z += randomZ
	camera.rotation.x += degreesToRads(randomXRotation)
	camera.rotation.y += degreesToRads(randomYRotation)
	camera.rotation.z += degreesToRads(randomZRotation)

# Randomly places a node within a global 3d bounding box
func randomizeNodeInRect(node, minX, minY, minZ, maxX, maxY, maxZ):
	var randomXRotation = randomizer.randf_range(0, 360)
	var randomYRotation = randomizer.randf_range(0, 360)
	var randomZRotation = randomizer.randf_range(0, 360)
	var randomX = randomizer.randf_range(minX, maxX)
	var randomY = randomizer.randf_range(minY, maxY)
	var randomZ = randomizer.randf_range(minZ, maxZ)
	node.transform.origin.x = randomX
	node.transform.origin.y = randomY
	node.transform.origin.z = randomZ
	node.rotation.x = degreesToRads(randomXRotation)
	node.rotation.y = degreesToRads(randomYRotation)
	node.rotation.z = degreesToRads(randomZRotation)

func randomizeColor(node):
	var newMaterial = SpatialMaterial.new()
	var r = randomizer.randf_range(0, 1)
	var g = randomizer.randf_range(0, 1)
	var b = randomizer.randf_range(0, 1)
	newMaterial.albedo_color = Color(r, b, g, 1.0)
	node.material_override = newMaterial

func load_image_texture(filename):
	var texture = ImageTexture.new()
	var image = Image.new()
	image.load(filename)
	texture.create_from_image(image)
	return texture

func randomizeBackground(node):
	# 1/3 shot at flat random color
	if iterations == 0 or randomizer.randi() % 3 == 0:
		randomizeColor(node)
		return
	# Pick randomly among preloaded images
	var texture = background_textures[randomizer.randi() % backgrounds.size()]
	node.material_override.albedo_texture = texture
	var random_scale = randomizer.randf_range(12, 60)
	var random_offset = randomizer.randf_range(0, 10)
	node.material_override.uv1_scale = Vector3(random_scale, random_scale, random_scale)
	node.material_override.uv1_offset = Vector3(random_offset, random_offset, random_offset)
	# Maybe reset the color so original image looks right
	if randomizer.randi() % 2 == 0:
		node.material_override.albedo_color = Color(1, 1, 1, 0)

func randomizeLight(light):
	light.omni_attenuation = randomizer.randf_range(min_attentuation, max_attentuation)
	light.omni_range = randomizer.randf_range(min_range, max_range)
	light.light_color = Color(randomizer.randf_range(0.5, 1), randomizer.randf_range(0.5, 1), randomizer.randf_range(0.5, 1))
	light.transform.origin.x += randomizer.randf_range(-max_light_dist_from_center, max_light_dist_from_center)
	light.transform.origin.z += randomizer.randf_range(-max_light_dist_from_center, max_light_dist_from_center)
	light.transform.origin.y += randomizer.randf_range(min_light_lift, max_light_lift)
	return light

func randomizeLighting():
	for i in range(currentLights.size()):
		remove_child(currentLights[i])
	currentLights = []
	var light_count = randomizer.randi_range(0, max_lights)
	for i in range(light_count):
		var light = loadedOmnilight.instance()
		randomizeLight(light)
		add_child(light)
		currentLights.append(light)
