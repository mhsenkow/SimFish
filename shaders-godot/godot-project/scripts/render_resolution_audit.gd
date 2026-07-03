class_name RenderResolutionAudit
extends RefCounted

# PERFORMANCE_UNTHROTTLED #86 — post chain must quantize at internal res, not display res.

const INTERNAL_W: int = 512
const INTERNAL_H: int = 288


static func internal_size_ok(w: int, h: int) -> bool:
	return w == INTERNAL_W and h == INTERNAL_H


static func post_matches_3d(render_w: int, render_h: int, post_w: int, post_h: int) -> bool:
	return post_w == render_w and post_h == render_h
