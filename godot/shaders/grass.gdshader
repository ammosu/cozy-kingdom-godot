shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.22, 0.42, 0.14);
uniform vec3 tip_color : source_color = vec3(0.62, 0.78, 0.33);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.4;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float time_override = -1.0; // >=0 時以此取代 TIME（逐格截圖用）

varying float tip;

void vertex() {
	tip = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = time_override >= 0.0 ? time_override : TIME;
	float gust = sin(dot(world.xz, wind_dir) * 0.08 + t * wind_speed) * 0.5 + 0.5;
	float flutter = sin(world.x * 1.7 + world.z * 1.3 + t * 3.1) * 0.15;
	float bend = (gust * wind_strength + flutter * 0.4) * tip * tip;
	vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	VERTEX += normalize(local_wind) * bend;
	VERTEX.y -= bend * bend * 0.3;
	// 法線一律朝上，避免草葉正反面明暗差
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec3 c = mix(base_color, tip_color, smoothstep(0.0, 1.0, tip));
	c *= COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35, 0.45, 0.15) * tip;
	AO = mix(0.4, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
}
