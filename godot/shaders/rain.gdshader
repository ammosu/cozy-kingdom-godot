shader_type spatial;
// 雨絲：沿著落下方向拉長，繞自身的軸轉向鏡頭；貼近鏡頭時淡掉，才不會有整條粗線掃過畫面。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

varying float cam_fade;

void vertex() {
	vec3 y = normalize(MODEL_MATRIX[1].xyz);
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	vec3 x = normalize(cross(y, normalize(to_cam)));
	vec3 z = cross(x, y);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x, 0.0), vec4(y, 0.0), vec4(z, 0.0), vec4(wp, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	cam_fade = smoothstep(0.8, 4.0, length(to_cam));
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = sin(UV.y * 3.14159);
	ALBEDO = vec3(0.78, 0.83, 0.92);
	ALPHA = across * along * 0.42 * cam_fade * COLOR.a;
}
