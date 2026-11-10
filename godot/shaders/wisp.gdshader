shader_type spatial;
// 小光靈的光暈：永遠面向鏡頭的加亮面片，核心偏白、外圈帶色。霧裡也要看得到，所以不吃霧。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 tint = vec3(1.0, 0.82, 0.48);
uniform float gain = 1.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float halo = pow(clamp(1.0 - r, 0.0, 1.0), 2.6);
	float core = smoothstep(0.22, 0.05, r);
	ALBEDO = mix(tint, vec3(1.0), core * 0.8) * (halo * 1.4 + core * 3.5) * gain;
	ALPHA = COLOR.a;
}
