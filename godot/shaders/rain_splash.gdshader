shader_type spatial;
// 雨滴打到地面的水圈：平放的環，隨粒子生命往外擴、變淡。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

varying float eye_above;

void vertex() {
	eye_above = CAMERA_POSITION_WORLD.y - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float radius = mix(0.15, 0.9, COLOR.r);
	float ring = smoothstep(0.12, 0.0, abs(r - radius));
	ALBEDO = vec3(0.82, 0.87, 0.94);
	ALPHA = ring * (1.0 - COLOR.r) * 0.55 * smoothstep(0.05, 0.4, eye_above);   // 比眼睛高的水面看不到，也避免半空中出現水圈
}
