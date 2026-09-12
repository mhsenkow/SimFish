class_name ToastStack
extends RefCounted

# Lays out live toasts in their layer (messaging pass).
#
# The old stacking maths was `layer_h - (index + 1) * 74.0` — a hardcoded
# 74 px per toast. Any toast whose body wrapped to two lines was taller than
# that and overlapped its neighbour. Toasts now report their real height and
# the stack reads it, so a tall one simply pushes the rest up.
#
# Kept as a static helper on the layer rather than a Node: there is one
# toast layer, it is owned by main, and this only needs to reposition
# children.

const GAP: float = 6.0
# Never let the stack run off the top of its layer; older toasts past this
# are dismissed rather than drawn out of bounds.
const MAX_VISIBLE: int = 3


# Reposition every live toast, newest at the bottom. Returns how many are
# currently live (not dismissing).
static func relayout(layer: Control) -> int:
	if layer == null or not is_instance_valid(layer):
		return 0
	var live: Array[Toast] = []
	for child in layer.get_children():
		var t := child as Toast
		if t == null or not is_instance_valid(t):
			continue
		# Re-hug EVERY toast, including one on its way out: a dismissing
		# toast is still on screen for half a second, and skipping it left
		# trimmed toasts drawn at their un-shrunk size while they faded.
		t.custom_minimum_size.x = PanelTheme.TOAST_STACK_W - 8.0
		t.size.x = t.custom_minimum_size.x
		t.reset_size()
		if not t.is_dismissing():
			live.append(t)
	var layer_h: float = layer.size.y
	if layer_h < 1.0:
		layer_h = PanelTheme.TOAST_STACK_H
	# Newest last in child order; stack upward from the bottom.
	var y: float = layer_h
	for i in range(live.size() - 1, -1, -1):
		var t: Toast = live[i]
		# Re-hug content before measuring: a toast that was stretched by its
		# parent would otherwise report a height far larger than it draws.
		# Width first, then shrink: reset_size() would otherwise discard the
		# width and the autowrap body would re-measure at zero.
		t.custom_minimum_size.x = PanelTheme.TOAST_STACK_W - 8.0
		t.size.x = t.custom_minimum_size.x
		t.reset_size()
		var h: float = maxf(t.get_combined_minimum_size().y, 24.0)
		y -= h
		# Only animate the shuffle for toasts already settled, so a new one
		# still plays its own entrance.
		t.position.y = y
		y -= GAP
	return live.size()


# Trim the oldest toasts down to MAX_VISIBLE. Older ones are dismissed
# rather than left to stack off-screen.
static func trim(layer: Control) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var live: Array[Toast] = []
	for child in layer.get_children():
		var t := child as Toast
		if t != null and is_instance_valid(t) and not t.is_dismissing():
			live.append(t)
	var excess: int = live.size() - MAX_VISIBLE
	for i in maxi(0, excess):
		live[i].dismiss()


# Add a toast to the layer and wire its lifecycle into the stack.
static func present(layer: Control, cfg: Dictionary) -> Toast:
	if layer == null or not is_instance_valid(layer):
		return null
	var t: Toast = Toast.create(cfg)
	layer.add_child(t)
	t.dismissed.connect(func(_x): relayout(layer))
	trim(layer)
	# Height is only known after a layout pass, so settle first.
	t.call_deferred("set", "position", Vector2(PanelTheme.TOAST_STACK_W, 0.0))
	# The layer is a plain Control, not a Container - it has no queue_sort.
	# _deferred_relayout is what actually places the toast, two frames on.
	_deferred_relayout(layer)
	return t


static func _deferred_relayout(layer: Control) -> void:
	# Two frames: one for the container to measure the new child, one for
	# the position to take effect before it is drawn.
	var tree: SceneTree = layer.get_tree()
	if tree == null:
		relayout(layer)
		return
	await tree.process_frame
	await tree.process_frame
	relayout(layer)
