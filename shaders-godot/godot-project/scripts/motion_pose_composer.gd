class_name MotionPoseComposer
extends RefCounted

# One writer per transform channel (CREATURE_MOTION_700 #44, #91).
#
# Several Phase 0 bugs were the same bug: two pieces of code wrote the same
# pivot channel in one frame and the second silently erased the first (the
# turn lean, the brake flare, the sleep roll, the body proportions). The
# composer collects every contribution to a channel as layers, then writes
# each channel exactly once:
#
#   value = (base + Σ add[i] · weight[i]) · Π mul[j]
#
# Channels are keyed by (node, property), property being a Node3D property
# path such as "rotation:z" or "scale". Float channels and Vector3 channels
# both work; a Vector3 channel multiplies component-wise.
#
# In debug builds, begin_frame()/apply() also catch writers that bypass the
# composer: a channel whose value changed between apply() and the next
# begin_frame() was written by someone else, and is reported once.

class Channel:
	extends RefCounted
	var node: Node3D
	var prop: NodePath
	var is_vec: bool = false
	var base: Variant = 0.0
	var add: Variant = 0.0
	var mul: Variant = 1.0
	var written: Variant = null
	var touched: bool = false

var _channels: Dictionary = {}
var foreign_writes: PackedStringArray = PackedStringArray()
var check_foreign: bool = OS.is_debug_build()


func _channel(node: Node3D, prop: String, is_vec: bool) -> Channel:
	var key: String = "%d:%s" % [node.get_instance_id(), prop]
	var c: Channel = _channels.get(key)
	if c == null:
		c = Channel.new()
		c.node = node
		c.prop = NodePath(prop)
		c.is_vec = is_vec
		_reset_layers(c)
		_channels[key] = c
	return c


func _reset_layers(c: Channel) -> void:
	if c.is_vec:
		c.base = Vector3.ZERO
		c.add = Vector3.ZERO
		c.mul = Vector3.ONE
	else:
		c.base = 0.0
		c.add = 0.0
		c.mul = 1.0
	c.touched = false


# Start a frame: clear layers, and in debug builds note any channel someone
# else changed since our last apply().
func begin_frame() -> void:
	for key in _channels:
		var c: Channel = _channels[key]
		if check_foreign and c.written != null and is_instance_valid(c.node):
			var now: Variant = c.node.get_indexed(c.prop)
			var moved: bool = (now as Vector3).distance_to(c.written as Vector3) > 1e-5 \
				if c.is_vec else absf(float(now) - float(c.written)) > 1e-5
			if moved:
				var label: String = "%s.%s" % [c.node.name, String(c.prop)]
				if not foreign_writes.has(label):
					foreign_writes.append(label)
		_reset_layers(c)


func set_base(node: Node3D, prop: String, value: Variant) -> void:
	if node == null:
		return
	var c: Channel = _channel(node, prop, value is Vector3)
	c.base = value
	c.touched = true


func add(node: Node3D, prop: String, value: Variant, weight: float = 1.0) -> void:
	if node == null:
		return
	var c: Channel = _channel(node, prop, value is Vector3)
	c.add = c.add + value * weight
	c.touched = true


func mul(node: Node3D, prop: String, factor: Variant) -> void:
	if node == null:
		return
	var c: Channel = _channel(node, prop, factor is Vector3)
	c.mul = c.mul * factor
	c.touched = true


func value_of(node: Node3D, prop: String) -> Variant:
	var key: String = "%d:%s" % [node.get_instance_id(), prop]
	var c: Channel = _channels.get(key)
	if c == null:
		return null
	return (c.base + c.add) * c.mul


# Write every touched channel once.
func apply() -> void:
	for key in _channels.keys():
		var c: Channel = _channels[key]
		if not is_instance_valid(c.node):
			_channels.erase(key)
			continue
		if not c.touched:
			c.written = null
			continue
		var v: Variant = (c.base + c.add) * c.mul
		c.node.set_indexed(c.prop, v)
		c.written = v


func channel_count() -> int:
	return _channels.size()
