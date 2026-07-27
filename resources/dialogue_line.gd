class_name DialogueLine
extends Resource

@export var lines: Array[String] = []

# choices[line_index] = [
#   { "text": "button label", "target": line_index, "condition_flag": "", "set_flag": "" }
# ]
@export var choices: Dictionary = {}

# Track which flags the player has triggered during this dialogue session
var flags: Dictionary = {}


func get_available_choices_at(line_index: int) -> Array:
	var result: Array = []
	if not choices.has(line_index):
		return result
	var opts: Array = choices[line_index]
	for opt in opts:
		# Skip consumed choices (already selected in a previous session)
		if opt.get("consumed", false):
			continue
		var condition: String = opt.get("condition_flag", "")
		if condition == "" or flags.get(condition, false):
			result.append(opt)
	return result


func has_choices_at(line_index: int) -> bool:
	return get_available_choices_at(line_index).size() > 0


# Returns the auto-advance target if this line has a single auto-choice, or -1
func get_auto_target_at(line_index: int) -> int:
	if not choices.has(line_index):
		return -1
	var opts: Array = choices[line_index]
	if opts.size() == 1 and opts[0].get("auto", false):
		var condition: String = opts[0].get("condition_flag", "")
		if condition == "" or flags.get(condition, false):
			return opts[0].get("target", -1)
	return -1
