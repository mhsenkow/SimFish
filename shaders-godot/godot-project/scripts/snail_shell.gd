# Shared procedural snail-shell builder.
#
# Used by BOTH world.gd (live snails) and creature_creator.gd (preview) so the
# two never drift — previously each had its own copy of the shape match and the
# preview only knew the original four shapes. Geometry is emitted as voxel boxes
# through an add_box callback so each caller keeps its own mesh / material
# plumbing:
#     add_box.call(parent: Node3D, pos: Vector3, size: Vector3, color: Color)
#
# build() lays down the shell whorls + ornaments + foot. Eye-stalks are left to
# the caller: world.gd attaches an animated "EyeStalks" pivot; the preview adds
# a static pair.
#
# class_name intentionally omitted — preloaded as a const where used.
extends RefCounted


static func _field(d: Dictionary, k: String, def: Variant) -> Variant:
	return d[k] if d.has(k) else def


# g is a genome-style dict. Recognised keys (all optional, sensible defaults):
#   shell_color, shell_accent_color, body_color (Color)
#   shell_size, spire_height, aperture_flare, shell_spines, toxin_level (float)
#   whorl_count, shell_pattern, generation (int)
#   shell_shape, operculum
static func build(parent: Node3D, g: Dictionary, add_box: Callable) -> void:
	var ss: float = maxf(0.2, float(_field(g, "shell_size", 1.0)))
	var shape: String = String(_field(g, "shell_shape", "turbo"))
	var spire: float = clampf(float(_field(g, "spire_height", 1.0)), 0.4, 2.0)
	var whorls: int = clampi(int(_field(g, "whorl_count", 4)), 3, 8)
	var flare: float = clampf(float(_field(g, "aperture_flare", 0.0)), 0.0, 1.0)
	var operculum: bool = bool(_field(g, "operculum", false))
	var pattern: int = int(_field(g, "shell_pattern", 0))
	var spines: float = clampf(float(_field(g, "shell_spines", 0.0)), 0.0, 1.0)
	var toxin: float = clampf(float(_field(g, "toxin_level", 0.0)), 0.0, 1.0)
	var generation: int = int(_field(g, "generation", 0))
	var pat_scale: float = clampf(float(_field(g, "shell_pattern_scale", 0.5)), 0.0, 1.0)
	var pat_density: float = clampf(float(_field(g, "shell_pattern_density", 0.5)), 0.0, 1.0)

	var sc_v: Variant = _field(g, "shell_color", Color8(135, 44, 176))
	var shell_color: Color = sc_v if sc_v is Color else Color8(135, 44, 176)
	if toxin > 0.35:
		shell_color = shell_color.lerp(Color8(246, 220, 64), toxin * 0.35)
	# Banding colour: explicit shell_accent_color (alpha > 0.5) else a darker shade.
	var acc_v: Variant = _field(g, "shell_accent_color", null)
	var shell_dark: Color = (acc_v as Color) if (acc_v is Color and (acc_v as Color).a > 0.5) \
		else shell_color.darkened(0.22)
	var body_v: Variant = _field(g, "body_color", null)
	var body_color: Color = body_v if body_v is Color else Color8(44, 31, 21)

	# Alternate light / dark per whorl index for the classic banded look.
	var band := func(i: int) -> Color:
		return shell_color if (i % 2) == 0 else shell_dark

	match shape:
		"trochus":
			# Pointed cone: stacked whorls shrinking smoothly toward the tip.
			var n: int = whorls * 2
			for i in n:
				var t: float = float(i) / float(maxi(1, n - 1))
				var y: float = (0.02 + t * 0.42 * spire) * ss
				var s: float = (0.2 * (1.0 - t * 0.82)) * ss
				add_box.call(parent, Vector3(0, y, 0),
					Vector3(maxf(s, 0.02), maxf(s * 0.72, 0.02), maxf(s, 0.02)), band.call(i))
		"tower":
			# Tall narrow many-whorl spire (trumpet / rabbit / cerith).
			var n: int = maxi(whorls, 6) * 2
			for i in n:
				var t: float = float(i) / float(maxi(1, n - 1))
				var y: float = (0.02 + t * 0.66 * spire) * ss
				var s: float = (0.14 * (1.0 - t * 0.78)) * ss
				add_box.call(parent, Vector3(0, y, 0),
					Vector3(maxf(s, 0.02), maxf(s, 0.02), maxf(s, 0.02)), band.call(i))
		"ramshorn":
			# Flat planispiral coil: whorls wound in one vertical plane, thin in
			# Z, fattening toward the outer whorl.
			var n: int = maxi(whorls, 5) * 2
			for i in n:
				var t: float = float(i) / float(maxi(1, n - 1))
				var ang: float = t * TAU * 1.6
				var r: float = (0.02 + t * 0.17) * ss
				var s: float = (0.05 + t * 0.09) * ss
				add_box.call(parent, Vector3(cos(ang) * r, 0.04 * ss + sin(ang) * r, 0.0),
					Vector3(maxf(s, 0.02), maxf(s, 0.02), maxf(s * 0.45, 0.02)), band.call(i))
		"limpet":
			# Low conical cap: stacked flattened discs shrinking upward (smooth
			# dome), no spire.
			for i in 4:
				var t: float = float(i) / 3.0
				var s: float = (0.3 - t * 0.22) * ss
				var y: float = (0.01 + t * 0.07) * ss
				add_box.call(parent, Vector3(0, y, 0),
					Vector3(s, maxf(0.035 * ss, 0.02), s * 0.85), band.call(i))
		"conch":
			# Large globose body whorl (rounded cluster) plus a short spire.
			for off in [Vector3(0, 0, 0), Vector3(0.1, 0.03, 0.0), Vector3(-0.09, 0.03, 0.04),
					Vector3(0.0, 0.02, -0.08)]:
				add_box.call(parent, off * ss + Vector3(0, 0.07 * ss, 0),
					Vector3(0.2, 0.2, 0.22) * ss, shell_color)
			var nc: int = maxi(whorls - 1, 3)
			for i in nc:
				var t: float = float(i) / float(maxi(1, nc - 1))
				var y: float = (0.2 + t * 0.2 * spire) * ss
				var s: float = (0.12 * (1.0 - t * 0.7)) * ss
				add_box.call(parent, Vector3(0.02 * ss, y, -0.03 * ss),
					Vector3(maxf(s, 0.02), maxf(s, 0.02), maxf(s, 0.02)), band.call(i))
		"nassarius":
			# Small low ovoid that rides the substrate.
			add_box.call(parent, Vector3(0, 0.02 * ss, 0),
				Vector3(0.18, 0.11, 0.22) * ss, shell_color)
			add_box.call(parent, Vector3(0, 0.1 * ss, -0.03 * ss),
				Vector3(0.11, 0.08, 0.13) * ss, shell_dark)
			add_box.call(parent, Vector3(0, 0.15 * ss, -0.05 * ss),
				Vector3(0.05, 0.05, 0.06) * ss, shell_color)
		"apple":
			# Rounded globose shell: a 5-voxel body-whorl cluster + small apex.
			for off in [Vector3(0, 0, 0), Vector3(0.09, 0.03, 0.0), Vector3(-0.09, 0.03, 0.0),
					Vector3(0, 0.02, 0.09), Vector3(0, 0.02, -0.09)]:
				add_box.call(parent, off * ss + Vector3(0, 0.07 * ss, 0),
					Vector3(0.17, 0.17, 0.17) * ss, shell_color)
			add_box.call(parent, Vector3(0, 0.2 * ss, -0.03 * ss),
				Vector3(0.1, 0.09, 0.1) * ss, shell_dark)
		_:
			# turbo: low rounded vertical spiral, fattening toward the outer
			# whorl. More voxels than the legacy build so it reads as a curve.
			var n: int = whorls * 2 + 2
			for i in n:
				var t: float = float(i) / float(maxi(1, n - 1))
				var ang: float = t * TAU * (0.5 * float(whorls) + 0.5)
				var r: float = (0.03 + t * 0.15) * ss
				var s: float = (0.055 + t * 0.115) * ss
				add_box.call(parent, Vector3(cos(ang) * r, 0.03 * ss + sin(ang) * r * spire, 0.0),
					Vector3(s, s, s), band.call(i))

	# ---- Shell colour pattern overlay (on top of the per-whorl banding) ----
	if pattern == 1:
		# Banding rings: density adds more bands, scale thickens them.
		var band_n: int = clampi(1 + int(round(pat_density * 3.0)), 1, 4)
		var bw: float = 0.018 + pat_scale * 0.02
		var bsz: float = 0.18 + pat_scale * 0.06
		for bi in band_n:
			var bt: float = (float(bi) / float(maxi(1, band_n - 1))) if band_n > 1 else 0.0
			var by: float = lerpf(0.04, 0.16, bt)
			add_box.call(parent, Vector3(0, by * ss, 0.02 * ss),
				Vector3(bsz, bw, bsz) * ss, shell_dark)
	elif pattern == 2:
		# Spots: density adds more, scale enlarges them.
		var spot_n: int = clampi(2 + int(round(pat_density * 3.0)), 2, 5)
		var sps: float = 0.03 + pat_scale * 0.03
		for si in spot_n:
			var t2: float = float(si) / float(maxi(1, spot_n - 1))
			var ang2: float = lerpf(-1.0, 1.0, t2)
			add_box.call(parent,
				Vector3(cos(ang2) * 0.08 * ss, (0.06 + t2 * 0.08) * ss, sin(ang2) * 0.06 * ss),
				Vector3(sps, sps, sps) * ss, shell_dark)
	elif pattern == 3:
		# Zigzag: density adds segments, scale thickens them.
		var zz_n: int = clampi(4 + int(round(pat_density * 4.0)), 4, 8)
		var zzs: float = 0.025 + pat_scale * 0.02
		for i in zz_n:
			var ang: float = lerpf(-1.2, 1.2, float(i) / float(maxi(1, zz_n - 1)))
			var zz_y: float = (0.05 + (0.03 if i % 2 == 0 else -0.02)) * ss
			add_box.call(parent, Vector3(cos(ang) * 0.13 * ss, zz_y, sin(ang) * 0.13 * ss * 0.4),
				Vector3(zzs, 0.05, zzs) * ss, shell_dark)
	# Flared aperture lip (conch / apple).
	if flare > 0.05:
		var flare_col: Color = shell_color.lightened(0.06)
		var fr: float = (0.18 + flare * 0.12) * ss
		for i in 5:
			var ang: float = lerpf(-1.4, 1.4, float(i) / 4.0)
			add_box.call(parent,
				Vector3(cos(ang) * fr, 0.02 * ss, sin(ang) * fr * 0.5 + 0.06 * ss),
				Vector3(0.05, 0.06, 0.04) * ss, flare_col)
	# Defensive shell spines.
	if spines > 0.12:
		var spine_col: Color = shell_dark.lightened(0.08)
		var spine_count: int = clampi(int(round(2.0 + spines * 6.0)), 2, 8)
		for i in spine_count:
			var t: float = float(i) / float(maxi(1, spine_count - 1))
			var ang: float = lerpf(-1.2, 1.2, t)
			var r: float = (0.10 + 0.14 * spines) * ss
			var h: float = (0.03 + 0.08 * spines) * ss
			add_box.call(parent,
				Vector3(cos(ang) * r, 0.09 * ss + sin(ang) * r * 0.55, sin(ang) * r * 0.2),
				Vector3(0.03 * ss, h, 0.03 * ss), spine_col)
	# Toxic mantle frills (warning signal) + growth-ring ridges on old lineages.
	if toxin > 0.28:
		var mantle_col: Color = shell_color.lerp(Color8(246, 230, 128), clampf(toxin * 0.42, 0.0, 0.42))
		var frill_n: int = clampi(3 + int(toxin * 4.0), 3, 7)
		for i in frill_n:
			var t: float = float(i) / float(maxi(1, frill_n - 1))
			var ang: float = lerpf(-1.1, 1.1, t)
			var r2: float = (0.12 + ss * 0.10) * ss
			add_box.call(parent, Vector3(cos(ang) * r2, -0.01 * ss, sin(ang) * r2 * 0.35),
				Vector3(0.035, 0.028, 0.04) * ss, mantle_col)
	if generation >= 3:
		var ring_col: Color = shell_dark.lightened(0.18)
		var ring_count: int = clampi(1 + int(generation / 3.0), 1, 4)
		for i in ring_count:
			var frac: float = float(i + 1) / float(ring_count + 1)
			var ry: float = (0.02 + frac * 0.16) * ss
			var rs: float = (0.20 - frac * 0.04) * ss
			add_box.call(parent, Vector3(0, ry, -0.02 * ss),
				Vector3(rs, 0.016 * ss, rs), ring_col)

	# ---- Foot + operculum ----
	var foot_y: float = -0.05 * ss if shape == "nassarius" else -0.12 * ss
	var foot_size: Vector3
	if shape == "nassarius":
		foot_size = Vector3(0.28, 0.04, 0.20) * ss
	elif shape == "apple" or shape == "conch":
		foot_size = Vector3(0.3, 0.07, 0.22) * ss
	else:
		foot_size = Vector3(0.24, 0.06, 0.16) * ss
	add_box.call(parent, Vector3(0, foot_y, 0), foot_size, body_color)
	if operculum:
		var op_pivot := Node3D.new()
		op_pivot.name = "Operculum"
		parent.add_child(op_pivot)
		add_box.call(op_pivot, Vector3(0, foot_y + 0.05 * ss, 0.07 * ss),
			Vector3(0.12, 0.03, 0.1) * ss, shell_dark.darkened(0.1))
