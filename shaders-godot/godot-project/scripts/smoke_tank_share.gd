extends SceneTree

# Tank share codes + postcards (BROAD_DIRECTIONS #19).
#
# A share code is untrusted input the moment a player pastes one from a
# stranger, so half of this is round-tripping and half is refusing garbage
# without throwing.


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_tank_share")

	var cfg: Dictionary = {
		"tank_shape": "bowfront",
		"vessel_preset": "nano",
		"tank_preset": "community",
		"substrate_type": "eco_complete",
		"environment_preset": "room",
		"lighting_preset": "planted",
		"aeration_type": "disk",
		"tank_half_w": 5.0,
		"tank_half_d": 4.0,
		"tank_height": 6.0,
	}

	# --- Round trip ---
	var code: String = TankShare.make_code(123456, cfg)
	t.check(code.begins_with(TankShare.PREFIX),
		"a code must carry the %s prefix" % TankShare.PREFIX)
	t.check(TankShare.is_code(code), "is_code recognises our own output")
	t.check(code.length() < 600, "a code must be paste-able, got %d chars" % code.length())
	var back: Dictionary = TankShare.parse_code(code)
	t.check(not back.is_empty(), "a valid code must parse")
	t.equals(int(back.get("seed", -1)), 123456, "the seed round-trips")
	var rc: Dictionary = back.get("cfg", {})
	for key in cfg.keys():
		t.check(rc.has(key), "shared key %s must round-trip" % key)
	t.equals(String(rc.get("tank_shape", "")), "bowfront", "string values round-trip")
	t.approx(float(rc.get("tank_half_w", 0.0)), 5.0, "float values round-trip")

	# Leading/trailing whitespace is what a paste looks like.
	t.check(not TankShare.parse_code("  " + code + "  \n").is_empty(),
		"a pasted code with surrounding whitespace must still parse")

	# --- Negative seeds and extremes ---
	for s in [0, -1, 2147483647, -2147483648]:
		var c2: String = TankShare.make_code(s, cfg)
		t.equals(int(TankShare.parse_code(c2).get("seed", 99)), s,
			"seed %d must round-trip" % s)

	# --- Garbage in, {} out, never a throw ---
	for junk in ["", "   ", "hello", "WLTK1:", "WLTK1:!!!!not-base64!!!!",
			"WLBP2:abc", "WLST1:abc", TankShare.PREFIX + "AAAA"]:
		t.check(TankShare.parse_code(junk).is_empty(),
			"garbage must parse as empty: '%s'" % junk.substr(0, 24))
	# Another subsystem's code must not be accepted as a tank code.
	t.check(not TankShare.is_code("WLBP2:whatever"),
		"a blueprint code is not a tank code")
	# Oversized input is refused BEFORE decompression.
	var huge: String = TankShare.PREFIX + "A".repeat(TankShare.MAX_CODE_CHARS + 10)
	t.check(TankShare.parse_code(huge).is_empty(),
		"an oversized code must be refused, not decompressed")

	# --- A code must not be able to set arbitrary config ---
	# This is the important one: a stranger's code should change the tank, not
	# the player's AI endpoint or debug flags.
	var hostile: Dictionary = cfg.duplicate()
	hostile["ai_endpoint"] = "http://evil.example"
	hostile["guardian_custom_gguf_path"] = "/etc/passwd"
	hostile["spotify_client_secret"] = "stolen"
	hostile["debug_growth_logging"] = true
	var hostile_code: String = TankShare.make_code(7, hostile)
	var parsed_hostile: Dictionary = TankShare.parse_code(hostile_code)
	var hcfg: Dictionary = parsed_hostile.get("cfg", {})
	for bad_key in ["ai_endpoint", "guardian_custom_gguf_path",
			"spotify_client_secret", "debug_growth_logging"]:
		t.check(not hcfg.has(bad_key),
			"a share code must NOT be able to set %s" % bad_key)
	t.check(hcfg.has("tank_shape"), "legitimate keys still survive alongside")
	# Every surviving key is on the allowlist.
	for key in hcfg.keys():
		t.check(TankShare.SHARED_KEYS.has(String(key)),
			"%s is not in SHARED_KEYS but survived decoding" % String(key))

	# A payload with no seed is not a tank.
	var seedless: String = TankShare.PREFIX + Marshalls.raw_to_base64(
		JSON.stringify({"v": 1, "cfg": {}}).to_utf8_buffer()
			.compress(FileAccess.COMPRESSION_GZIP))
	t.check(TankShare.parse_code(seedless).is_empty(),
		"a code with no seed must be refused")
	# A non-numeric seed likewise.
	var badseed: String = TankShare.PREFIX + Marshalls.raw_to_base64(
		JSON.stringify({"v": 1, "seed": "banana", "cfg": {}}).to_utf8_buffer()
			.compress(FileAccess.COMPRESSION_GZIP))
	t.check(TankShare.parse_code(badseed).is_empty(),
		"a non-numeric seed must be refused")
	# A cfg of the wrong type must degrade to empty, not throw.
	var badcfg: String = TankShare.PREFIX + Marshalls.raw_to_base64(
		JSON.stringify({"v": 1, "seed": 5, "cfg": "not a dict"}).to_utf8_buffer()
			.compress(FileAccess.COMPRESSION_GZIP))
	var bc: Dictionary = TankShare.parse_code(badcfg)
	t.check(not bc.is_empty(), "a malformed cfg must not invalidate the seed")
	t.check((bc.get("cfg", {}) as Dictionary).is_empty(),
		"a malformed cfg must decode as empty")

	# --- Seed labels are stable and readable ---
	t.equals(TankShare.seed_label(0), "0000-0000", "zero seed label")
	var lbl: String = TankShare.seed_label(0xA3F291C7)
	t.equals(lbl, "A3F2-91C7", "seed label is grouped hex, got %s" % lbl)
	t.equals(TankShare.seed_label(123456), TankShare.seed_label(123456),
		"seed labels are deterministic")
	# Negative seeds still produce a clean label rather than a minus sign.
	t.check(not TankShare.seed_label(-5).contains("-0"),
		"a negative seed must still render as grouped hex: %s" % TankShare.seed_label(-5))

	# --- Caption: one line, all the provenance ---
	var cap: String = TankShare.caption({
		"tank_name": "Loom", "sim_day": "Day 42",
		"fish": 12, "plants": 30, "seed": 0xA3F291C7,
	})
	for want in ["Loom", "Day 42", "12 fish", "30 plants", "A3F2-91C7"]:
		t.check(cap.contains(want), "caption must contain '%s': %s" % [want, cap])
	t.check(not cap.contains("\n"), "a caption must be a single line")
	# Missing facts are omitted, not rendered as blanks or zeros.
	var sparse: String = TankShare.caption({"seed": 1})
	t.check(sparse.contains("walstad loom"),
		"an unnamed tank falls back to the game name: %s" % sparse)
	t.check(not sparse.contains("fish"),
		"absent counts must be omitted, not shown as 0: %s" % sparse)
	t.check(not sparse.contains("··"), "no doubled separators: %s" % sparse)
	t.check(not TankShare.caption({}).is_empty(),
		"an empty info dict still produces a caption")

	# --- Postcard filename carries the seed ---
	var fn: String = TankShare.postcard_filename(0xA3F291C7, 1700000000)
	t.check(fn.contains("A3F2-91C7"), "filename carries the seed: %s" % fn)
	t.check(fn.ends_with(".png"), "filename is a png: %s" % fn)
	t.check(not fn.contains(" "), "filename has no spaces: %s" % fn)

	# --- Caption strip: real pixels, bottom of the image ---
	var img: Image = Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.9, 0.9, 1.0))
	var out: Image = TankShare.add_caption_strip(img, "hello")
	t.equals(out.get_width(), 320, "strip must not change width")
	t.equals(out.get_height(), 180, "strip must not change height")
	# The strip darkens the bottom; the top is untouched.
	var top: Color = out.get_pixel(160, 10)
	var bottom: Color = out.get_pixel(160, 180 - TankShare.CAPTION_STRIP_H / 2)
	t.check(top.get_luminance() > bottom.get_luminance(),
		"the caption strip must be darker than the image body (%.3f vs %.3f)"
			% [top.get_luminance(), bottom.get_luminance()])
	t.approx(top.get_luminance(), Color(0.9, 0.9, 0.9, 1.0).get_luminance(),
		"the image body must be left alone", 0.02)

	# Degenerate inputs return something usable rather than an illegible strip.
	t.check(TankShare.add_caption_strip(null, "x") == null,
		"a null image returns null")
	var tiny: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	t.equals(TankShare.add_caption_strip(tiny, "x").get_height(), 16,
		"an image too small to caption is returned unchanged")
	# NB: compared by luminance with a tolerance, not is_equal_approx —
	# FORMAT_RGBA8 quantises 0.9 to 229/255 = 0.898, which is outside
	# Color.is_equal_approx's epsilon. That is 8-bit precision, not a bug.
	t.approx(TankShare.add_caption_strip(img, "   ").get_pixel(160, 175).get_luminance(),
		Color(0.9, 0.9, 0.9, 1.0).get_luminance(),
		"an empty caption must not darken anything", 0.01)

	# --- caption_rect sits inside the strip ---
	var r: Rect2i = TankShare.caption_rect(img)
	t.check(r.position.y >= 180 - TankShare.CAPTION_STRIP_H,
		"caption text must sit inside the strip")
	t.check(r.position.x + r.size.x <= 320, "caption rect must fit the width")
	t.check(r.size.y > 0 and r.size.x > 0, "caption rect must be non-empty")

	quit(t.finish())
