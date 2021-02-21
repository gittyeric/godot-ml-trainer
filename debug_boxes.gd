extends Node2D

var randomizer = RandomNumberGenerator.new()
var bounding_boxes = []

func _ready():
	randomizer.randomize()

func _draw():
	var r = randomizer.randf_range(0.5, 1)
	var g = randomizer.randf_range(0.5, 1)
	var b = randomizer.randf_range(0.5, 1)
	var alpha = randomizer.randf_range(0.6, 0.9)
	for i in range(bounding_boxes.size()):
		draw_rect(bounding_boxes[i], Color(r, b, g, alpha), true)

func handle_bounding_box_update(new_bounding_boxes):
	bounding_boxes = new_bounding_boxes
	update()
