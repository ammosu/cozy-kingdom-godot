shader_type spatial;
// 落水：拉長的雜訊往下捲動，越往下越快、越破碎；上緣像玻璃，下緣打成白沫。UV：x 橫向、y 由上往下。
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 water : source_color = vec3(0.34, 0.74, 0.82);
uniform float stream = 0.0;       // 每道水的相位差
uniform float across = 2.2;       // 橫向細節密度
uniform float time_override = -1.0;

void vertex() {
	float t = time_override >= 0.0 ? time_override : TIME;
	VERTEX += NORMAL * sin(UV.y * 16.0 - t * 7.0 + UV.x * 5.0 + stream) * 0.006 * UV.y;
}

void fragment() {
	float t = time_override >= 0.0 ? time_override : TIME;
	float y = pow(UV.y, 0.72);         // 自由落體：越下面越快
	vec2 q1 = vec2(UV.x * across + stream, y * 0.55 - t * 0.62);
	vec2 q2 = vec2(UV.x * across * 2.3 - stream, y * 1.05 - t * 1.05);
	float a = texture(noise_tex, q1).r;
	float b = texture(noise_tex, q2).r;
	float streak = a * 0.6 + b * 0.4;
	float breakup = smoothstep(0.08, 0.95, UV.y);
	float white = smoothstep(0.56 - breakup * 0.14, 0.82, streak);
	float bottom = smoothstep(0.82, 1.0, UV.y + (b - 0.5) * 0.14);
	float top_lip = 1.0 - smoothstep(0.02, 0.14, UV.y);
	white = clamp(max(white * (0.55 + breakup * 0.6), bottom), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.2 + b * 0.22, UV.x) * smoothstep(1.0, 0.8 - b * 0.22, UV.x);   // 兩側羽化，水柱不是一條直邊的帶子
	float holes = mix(1.0, smoothstep(0.2, 0.42, streak), breakup * 0.7);
	vec3 col = mix(water * (0.75 + streak * 0.5), vec3(0.95, 0.98, 1.0), white);
	col = mix(col, water * 1.25, top_lip * 0.4);
	ALBEDO = col;
	EMISSION = col * 0.12;
	ROUGHNESS = mix(0.1, 0.65, white);
	SPECULAR = 0.7;
	ALPHA = edge * holes * mix(0.72, 0.97, white);
}
