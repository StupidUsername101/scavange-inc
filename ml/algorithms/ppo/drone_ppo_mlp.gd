class_name DronePPOMLP
extends RefCounted

const STATE_SCHEMA_VERSION = 2
const ADAM_BETA_ONE = 0.9
const ADAM_BETA_TWO = 0.999
const ADAM_EPSILON = 0.00000001
const MINIMUM_HIDDEN_WIDTH = 8
const MAXIMUM_HIDDEN_WIDTH = 1024
const MINIMUM_HIDDEN_DEPTH = 1
const MAXIMUM_HIDDEN_DEPTH = 6

#######################################################
# Uniform-width tanh MLP with explicit backpropagation and Adam.
# The flat parameter vector keeps checkpoints simple while layer-offset tables allow fresh
# policies to choose their own hidden width and depth instead of baking two layers into every
# algorithm. Hidden architecture is immutable for a policy; branches copy their source shape.
#######################################################

var input_size: int
var hidden_size: int
var hidden_layer_count: int
var output_size: int
var parameter_count: int

var weight_offsets = PackedInt32Array()
var bias_offsets = PackedInt32Array()
var layer_input_sizes = PackedInt32Array()
var layer_output_sizes = PackedInt32Array()

var parameters = PackedFloat64Array()
var gradients = PackedFloat64Array()
var adam_first_moment = PackedFloat64Array()
var adam_second_moment = PackedFloat64Array()
var optimizer_step = 0

var workspace_input = PackedFloat64Array()
var workspace_hidden_layers: Array = []
var workspace_output = PackedFloat64Array()
var workspace_hidden_gradients: Array = []


func _init(
	new_input_size: int,
	new_hidden_size: int,
	new_output_size: int,
	random_seed: int,
	output_weight_scale = 1.0,
	output_bias = 0.0,
	new_hidden_layer_count: int = 2
) -> void:
	input_size = maxi(new_input_size, 1)
	hidden_size = clampi(
		new_hidden_size,
		MINIMUM_HIDDEN_WIDTH,
		MAXIMUM_HIDDEN_WIDTH
	)
	hidden_layer_count = clampi(
		new_hidden_layer_count,
		MINIMUM_HIDDEN_DEPTH,
		MAXIMUM_HIDDEN_DEPTH
	)
	output_size = maxi(new_output_size, 1)
	_configure_offsets()
	parameters.resize(parameter_count)
	gradients.resize(parameter_count)
	adam_first_moment.resize(parameter_count)
	adam_second_moment.resize(parameter_count)
	gradients.fill(0.0)
	adam_first_moment.fill(0.0)
	adam_second_moment.fill(0.0)
	_configure_workspaces()
	_initialize_parameters(random_seed, float(output_weight_scale), float(output_bias))


func forward(input: PackedFloat64Array) -> Dictionary:
	if input.size() != input_size:
		return {}
	var hidden_layers: Array = _allocate_hidden_layers()
	var output: PackedFloat64Array = _forward_into(input, hidden_layers)
	if output.size() != output_size:
		return {}
	return {
		"input": input,
		"hidden_layers": hidden_layers,
		"output": output,
	}


func predict(input: PackedFloat64Array) -> PackedFloat64Array:
	if input.size() != input_size:
		return PackedFloat64Array()
	var hidden_layers: Array = _allocate_hidden_layers()
	return _forward_into(input, hidden_layers)


func predict_reusable(
	input: PackedFloat64Array,
	retain_for_backward = false
) -> PackedFloat64Array:
	if input.size() != input_size:
		return PackedFloat64Array()
	workspace_input = input if retain_for_backward else PackedFloat64Array()
	_forward_into_reusable(input)
	return workspace_output


func backward(cache: Dictionary, output_gradient: PackedFloat64Array) -> void:
	if cache.is_empty() or output_gradient.size() != output_size:
		return
	var input_value: Variant = cache.get("input", PackedFloat64Array())
	var hidden_value: Variant = cache.get("hidden_layers", [])
	if not (input_value is PackedFloat64Array) or not (hidden_value is Array):
		return
	var cached_input: PackedFloat64Array = input_value
	var hidden_layers: Array = hidden_value
	if not _valid_hidden_cache(hidden_layers):
		return
	_accumulate_backward(cached_input, hidden_layers, output_gradient)


func backward_reusable(output_gradient: PackedFloat64Array) -> void:
	if workspace_input.size() != input_size or output_gradient.size() != output_size:
		return
	_accumulate_backward(
		workspace_input,
		workspace_hidden_layers,
		output_gradient
	)
	workspace_input = PackedFloat64Array()


func input_gradient(
	cache: Dictionary,
	output_gradient: PackedFloat64Array
) -> PackedFloat64Array:
	if cache.is_empty() or output_gradient.size() != output_size:
		return PackedFloat64Array()
	var input_value: Variant = cache.get("input", PackedFloat64Array())
	var hidden_value: Variant = cache.get("hidden_layers", [])
	if not (input_value is PackedFloat64Array) or not (hidden_value is Array):
		return PackedFloat64Array()
	var hidden_layers: Array = hidden_value
	if not _valid_hidden_cache(hidden_layers):
		return PackedFloat64Array()

	var hidden_gradients: Array = _allocate_hidden_layers()
	for layer_index in range(hidden_layer_count):
		var empty_gradient: PackedFloat64Array = hidden_gradients[layer_index]
		empty_gradient.fill(0.0)
		hidden_gradients[layer_index] = empty_gradient
	var result = PackedFloat64Array()
	result.resize(input_size)
	result.fill(0.0)

	var output_layer_index: int = hidden_layer_count
	var output_weight_offset: int = int(weight_offsets[output_layer_index])
	var last_hidden_gradient: PackedFloat64Array = hidden_gradients[hidden_layer_count - 1]
	for row in range(output_size):
		var output_delta: float = output_gradient[row]
		var output_row_offset: int = output_weight_offset + row * hidden_size
		for column in range(hidden_size):
			last_hidden_gradient[column] += (
				parameters[output_row_offset + column] * output_delta
			)
	hidden_gradients[hidden_layer_count - 1] = last_hidden_gradient

	for layer_index in range(hidden_layer_count - 1, -1, -1):
		var activation: PackedFloat64Array = hidden_layers[layer_index]
		var activation_gradient: PackedFloat64Array = hidden_gradients[layer_index]
		var layer_weight_offset: int = int(weight_offsets[layer_index])
		var previous_size: int = int(layer_input_sizes[layer_index])
		if layer_index > 0:
			var previous_gradient: PackedFloat64Array = hidden_gradients[layer_index - 1]
			for row in range(hidden_size):
				var delta: float = activation_gradient[row] * (
					1.0 - activation[row] * activation[row]
				)
				var row_offset: int = layer_weight_offset + row * previous_size
				for column in range(previous_size):
					previous_gradient[column] += parameters[row_offset + column] * delta
			hidden_gradients[layer_index - 1] = previous_gradient
		else:
			for row in range(hidden_size):
				var delta: float = activation_gradient[row] * (
					1.0 - activation[row] * activation[row]
				)
				var row_offset: int = layer_weight_offset + row * input_size
				for column in range(input_size):
					result[column] += parameters[row_offset + column] * delta
	return result


func soft_update_from(source: DronePPOMLP, interpolation: float) -> bool:
	if not architecture_matches(source):
		return false
	var amount = clampf(interpolation, 0.0, 1.0)
	for index in range(parameter_count):
		parameters[index] = lerpf(parameters[index], source.parameters[index], amount)
	clear_gradients()
	return is_finite_state()


func architecture_matches(source: DronePPOMLP) -> bool:
	return (
		source != null
		and source.input_size == input_size
		and source.hidden_size == hidden_size
		and source.hidden_layer_count == hidden_layer_count
		and source.output_size == output_size
	)


func output_weight_offset() -> int:
	return int(weight_offsets[hidden_layer_count])


func output_bias_offset() -> int:
	return int(bias_offsets[hidden_layer_count])


func clear_gradients() -> void:
	gradients.fill(0.0)


func scale_gradients(multiplier: float) -> void:
	for index in range(gradients.size()):
		gradients[index] *= multiplier


func gradient_norm_squared() -> float:
	var result = 0.0
	for gradient in gradients:
		result += gradient * gradient
	return result


func apply_adam(learning_rate: float) -> void:
	optimizer_step += 1
	var first_correction = 1.0 - pow(ADAM_BETA_ONE, optimizer_step)
	var second_correction = 1.0 - pow(ADAM_BETA_TWO, optimizer_step)
	for index in range(parameter_count):
		var gradient = gradients[index]
		adam_first_moment[index] = (
			ADAM_BETA_ONE * adam_first_moment[index]
			+ (1.0 - ADAM_BETA_ONE) * gradient
		)
		adam_second_moment[index] = (
			ADAM_BETA_TWO * adam_second_moment[index]
			+ (1.0 - ADAM_BETA_TWO) * gradient * gradient
		)
		var corrected_first = adam_first_moment[index] / first_correction
		var corrected_second = adam_second_moment[index] / second_correction
		parameters[index] -= learning_rate * corrected_first / (
			sqrt(corrected_second) + ADAM_EPSILON
		)
	clear_gradients()


func to_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"input_size": input_size,
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"output_size": output_size,
		"parameters": Array(parameters),
		"adam_first_moment": Array(adam_first_moment),
		"adam_second_moment": Array(adam_second_moment),
		"optimizer_step": optimizer_step,
	}


func to_runtime_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"input_size": input_size,
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"output_size": output_size,
		"parameters": parameters.duplicate(),
		"adam_first_moment": adam_first_moment.duplicate(),
		"adam_second_moment": adam_second_moment.duplicate(),
		"optimizer_step": optimizer_step,
	}


func copy_from(source: DronePPOMLP) -> bool:
	if not architecture_matches(source):
		return false
	parameters = source.parameters.duplicate()
	adam_first_moment = source.adam_first_moment.duplicate()
	adam_second_moment = source.adam_second_moment.duplicate()
	optimizer_step = source.optimizer_step
	clear_gradients()
	return true


func perturb_parameters(
	rng: RandomNumberGenerator,
	relative_strength: float
) -> bool:
	if rng == null:
		return false
	var strength = clampf(relative_strength, 0.0, 0.5)
	if strength <= 0.0:
		return true
	var squared_total = 0.0
	for parameter in parameters:
		squared_total += parameter * parameter
	var parameter_rms = sqrt(
		squared_total / float(maxi(parameters.size(), 1))
	)
	var noise_deviation = maxf(parameter_rms, 0.0001) * strength
	for index in range(parameters.size()):
		parameters[index] += rng.randfn(0.0, noise_deviation)
		if not is_finite(parameters[index]):
			return false
	adam_first_moment.fill(0.0)
	adam_second_moment.fill(0.0)
	optimizer_step = 0
	clear_gradients()
	return true


func load_state(state: Dictionary) -> bool:
	if not _state_matches_architecture(state, input_size):
		return false
	return _load_parameter_state(state)


func load_state_with_appended_inputs(state: Dictionary) -> bool:
	var old_input_size = RLTrainingMath.finite_int_or(state.get("input_size", -1), -1)
	if (
		old_input_size <= 0
		or old_input_size > input_size
		or RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		!= STATE_SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("hidden_size", -1), -1)
		!= hidden_size
		or RLTrainingMath.finite_int_or(state.get("hidden_layer_count", -1), -1)
		!= hidden_layer_count
		or RLTrainingMath.finite_int_or(state.get("output_size", -1), -1)
		!= output_size
	):
		return false
	if old_input_size == input_size:
		return load_state(state)

	var old_network = DronePPOMLP.new(
		old_input_size,
		hidden_size,
		output_size,
		1,
		1.0,
		0.0,
		hidden_layer_count
	)
	if not old_network.load_state(state):
		return false

	parameters.fill(0.0)
	adam_first_moment.fill(0.0)
	adam_second_moment.fill(0.0)
	for row in range(hidden_size):
		for column in range(old_input_size):
			var old_index: int = int(old_network.weight_offsets[0]) + row * old_input_size + column
			var new_index: int = int(weight_offsets[0]) + row * input_size + column
			parameters[new_index] = old_network.parameters[old_index]
			adam_first_moment[new_index] = old_network.adam_first_moment[old_index]
			adam_second_moment[new_index] = old_network.adam_second_moment[old_index]
	_copy_state_range_from_network(
		old_network,
		int(old_network.bias_offsets[0]),
		int(bias_offsets[0]),
		hidden_size
	)
	for layer_index in range(1, hidden_layer_count + 1):
		var weight_count: int = int(layer_input_sizes[layer_index]) * int(layer_output_sizes[layer_index])
		_copy_state_range_from_network(
			old_network,
			int(old_network.weight_offsets[layer_index]),
			int(weight_offsets[layer_index]),
			weight_count
		)
		_copy_state_range_from_network(
			old_network,
			int(old_network.bias_offsets[layer_index]),
			int(bias_offsets[layer_index]),
			int(layer_output_sizes[layer_index])
		)
	optimizer_step = old_network.optimizer_step
	clear_gradients()
	return is_finite_state()


func is_finite_state() -> bool:
	for values: PackedFloat64Array in [parameters, adam_first_moment, adam_second_moment]:
		for value: float in values:
			if not is_finite(value):
				return false
	return true


func _configure_offsets() -> void:
	weight_offsets.resize(hidden_layer_count + 1)
	bias_offsets.resize(hidden_layer_count + 1)
	layer_input_sizes.resize(hidden_layer_count + 1)
	layer_output_sizes.resize(hidden_layer_count + 1)
	var cursor = 0
	for layer_index in range(hidden_layer_count):
		var layer_input_size: int = input_size if layer_index == 0 else hidden_size
		layer_input_sizes[layer_index] = layer_input_size
		layer_output_sizes[layer_index] = hidden_size
		weight_offsets[layer_index] = cursor
		cursor += hidden_size * layer_input_size
		bias_offsets[layer_index] = cursor
		cursor += hidden_size
	var output_layer_index: int = hidden_layer_count
	layer_input_sizes[output_layer_index] = hidden_size
	layer_output_sizes[output_layer_index] = output_size
	weight_offsets[output_layer_index] = cursor
	cursor += output_size * hidden_size
	bias_offsets[output_layer_index] = cursor
	cursor += output_size
	parameter_count = cursor


func _configure_workspaces() -> void:
	workspace_hidden_layers.clear()
	workspace_hidden_gradients.clear()
	for _layer_index in range(hidden_layer_count):
		var activation = PackedFloat64Array()
		activation.resize(hidden_size)
		workspace_hidden_layers.append(activation)
		var gradient = PackedFloat64Array()
		gradient.resize(hidden_size)
		workspace_hidden_gradients.append(gradient)
	workspace_output.resize(output_size)


func _allocate_hidden_layers() -> Array:
	var result: Array = []
	for _layer_index in range(hidden_layer_count):
		var activation = PackedFloat64Array()
		activation.resize(hidden_size)
		result.append(activation)
	return result


func _forward_into(input: PackedFloat64Array, hidden_layers: Array) -> PackedFloat64Array:
	var previous: PackedFloat64Array = input
	for layer_index in range(hidden_layer_count):
		var activation: PackedFloat64Array = hidden_layers[layer_index]
		var layer_input_size: int = int(layer_input_sizes[layer_index])
		var weight_offset: int = int(weight_offsets[layer_index])
		var bias_offset: int = int(bias_offsets[layer_index])
		for row in range(hidden_size):
			var value: float = parameters[bias_offset + row]
			var row_offset: int = weight_offset + row * layer_input_size
			for column in range(layer_input_size):
				value += parameters[row_offset + column] * previous[column]
			activation[row] = tanh(value)
		hidden_layers[layer_index] = activation
		previous = activation
	var output = PackedFloat64Array()
	output.resize(output_size)
	var output_layer_index: int = hidden_layer_count
	var output_weight_offset: int = int(weight_offsets[output_layer_index])
	var output_bias: int = int(bias_offsets[output_layer_index])
	for row in range(output_size):
		var value: float = parameters[output_bias + row]
		var row_offset: int = output_weight_offset + row * hidden_size
		for column in range(hidden_size):
			value += parameters[row_offset + column] * previous[column]
		output[row] = value
	return output


func _forward_into_reusable(input: PackedFloat64Array) -> void:
	var previous: PackedFloat64Array = input
	for layer_index in range(hidden_layer_count):
		var activation: PackedFloat64Array = workspace_hidden_layers[layer_index]
		var layer_input_size: int = int(layer_input_sizes[layer_index])
		var weight_offset: int = int(weight_offsets[layer_index])
		var bias_offset: int = int(bias_offsets[layer_index])
		for row in range(hidden_size):
			var value: float = parameters[bias_offset + row]
			var row_offset: int = weight_offset + row * layer_input_size
			for column in range(layer_input_size):
				value += parameters[row_offset + column] * previous[column]
			activation[row] = tanh(value)
		workspace_hidden_layers[layer_index] = activation
		previous = activation
	var output_layer_index: int = hidden_layer_count
	var output_weight_offset: int = int(weight_offsets[output_layer_index])
	var output_bias: int = int(bias_offsets[output_layer_index])
	for row in range(output_size):
		var value: float = parameters[output_bias + row]
		var row_offset: int = output_weight_offset + row * hidden_size
		for column in range(hidden_size):
			value += parameters[row_offset + column] * previous[column]
		workspace_output[row] = value


func _accumulate_backward(
	input: PackedFloat64Array,
	hidden_layers: Array,
	output_gradient: PackedFloat64Array
) -> void:
	for layer_index in range(hidden_layer_count):
		var empty_gradient: PackedFloat64Array = workspace_hidden_gradients[layer_index]
		empty_gradient.fill(0.0)
		workspace_hidden_gradients[layer_index] = empty_gradient

	var output_layer_index: int = hidden_layer_count
	var output_weight_offset: int = int(weight_offsets[output_layer_index])
	var output_bias: int = int(bias_offsets[output_layer_index])
	var last_hidden: PackedFloat64Array = hidden_layers[hidden_layer_count - 1]
	var last_hidden_gradient: PackedFloat64Array = workspace_hidden_gradients[hidden_layer_count - 1]
	for row in range(output_size):
		var delta: float = output_gradient[row]
		gradients[output_bias + row] += delta
		var row_offset: int = output_weight_offset + row * hidden_size
		for column in range(hidden_size):
			gradients[row_offset + column] += delta * last_hidden[column]
			last_hidden_gradient[column] += parameters[row_offset + column] * delta
	workspace_hidden_gradients[hidden_layer_count - 1] = last_hidden_gradient

	for layer_index in range(hidden_layer_count - 1, -1, -1):
		var activation: PackedFloat64Array = hidden_layers[layer_index]
		var activation_gradient: PackedFloat64Array = workspace_hidden_gradients[layer_index]
		var previous: PackedFloat64Array = (
			input if layer_index == 0 else hidden_layers[layer_index - 1]
		)
		var previous_size: int = int(layer_input_sizes[layer_index])
		var layer_weight_offset: int = int(weight_offsets[layer_index])
		var layer_bias_offset: int = int(bias_offsets[layer_index])
		var previous_gradient = PackedFloat64Array()
		if layer_index > 0:
			previous_gradient = workspace_hidden_gradients[layer_index - 1]
		for row in range(hidden_size):
			var delta: float = activation_gradient[row] * (
				1.0 - activation[row] * activation[row]
			)
			gradients[layer_bias_offset + row] += delta
			var row_offset: int = layer_weight_offset + row * previous_size
			for column in range(previous_size):
				gradients[row_offset + column] += delta * previous[column]
				if layer_index > 0:
					previous_gradient[column] += parameters[row_offset + column] * delta
		if layer_index > 0:
			workspace_hidden_gradients[layer_index - 1] = previous_gradient


func _initialize_parameters(
	random_seed: int,
	output_weight_scale: float,
	output_bias: float
) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	for layer_index in range(hidden_layer_count):
		var fan_in: int = int(layer_input_sizes[layer_index])
		var fan_out: int = hidden_size
		var deviation: float = sqrt(2.0 / float(fan_in + fan_out))
		var weight_offset: int = int(weight_offsets[layer_index])
		var bias_offset: int = int(bias_offsets[layer_index])
		for row in range(fan_out):
			for column in range(fan_in):
				parameters[weight_offset + row * fan_in + column] = (
					rng.randfn(0.0, deviation)
				)
			parameters[bias_offset + row] = 0.0
	var output_layer_index: int = hidden_layer_count
	var output_deviation: float = sqrt(1.0 / float(hidden_size)) * output_weight_scale
	var output_weight_offset: int = int(weight_offsets[output_layer_index])
	var output_bias_offset_value: int = int(bias_offsets[output_layer_index])
	for row in range(output_size):
		for column in range(hidden_size):
			parameters[output_weight_offset + row * hidden_size + column] = (
				rng.randfn(0.0, output_deviation)
			)
		parameters[output_bias_offset_value + row] = output_bias


func _valid_hidden_cache(hidden_layers: Array) -> bool:
	if hidden_layers.size() != hidden_layer_count:
		return false
	for value: Variant in hidden_layers:
		if not (value is PackedFloat64Array):
			return false
		var activation: PackedFloat64Array = value
		if activation.size() != hidden_size:
			return false
	return true


func _state_matches_architecture(state: Dictionary, expected_input_size: int) -> bool:
	return (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		== STATE_SCHEMA_VERSION
		and RLTrainingMath.finite_int_or(state.get("input_size", -1), -1)
		== expected_input_size
		and RLTrainingMath.finite_int_or(state.get("hidden_size", -1), -1)
		== hidden_size
		and RLTrainingMath.finite_int_or(state.get("hidden_layer_count", -1), -1)
		== hidden_layer_count
		and RLTrainingMath.finite_int_or(state.get("output_size", -1), -1)
		== output_size
	)


func _load_parameter_state(state: Dictionary) -> bool:
	var loaded_parameters = _packed_array(state.get("parameters", []))
	var loaded_first = _packed_array(state.get("adam_first_moment", []))
	var loaded_second = _packed_array(state.get("adam_second_moment", []))
	if (
		loaded_parameters.size() != parameter_count
		or loaded_first.size() != parameter_count
		or loaded_second.size() != parameter_count
	):
		return false
	for values: PackedFloat64Array in [loaded_parameters, loaded_first, loaded_second]:
		for value: float in values:
			if not is_finite(value):
				return false
	parameters = loaded_parameters
	adam_first_moment = loaded_first
	adam_second_moment = loaded_second
	optimizer_step = maxi(
		RLTrainingMath.finite_int_or(state.get("optimizer_step", 0), 0),
		0
	)
	clear_gradients()
	return true


func _copy_state_range_from_network(
	source: DronePPOMLP,
	source_offset: int,
	destination_offset: int,
	count: int
) -> void:
	for index in range(count):
		parameters[destination_offset + index] = source.parameters[source_offset + index]
		adam_first_moment[destination_offset + index] = source.adam_first_moment[source_offset + index]
		adam_second_moment[destination_offset + index] = source.adam_second_moment[source_offset + index]


func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		var packed_value: PackedFloat64Array = value
		return packed_value.duplicate()
	var result = PackedFloat64Array()
	if not (value is Array):
		return result
	for item: Variant in value:
		if not (item is int or item is float):
			return PackedFloat64Array()
		var numeric_value: float = float(item)
		if not is_finite(numeric_value):
			return PackedFloat64Array()
		result.append(numeric_value)
	return result
