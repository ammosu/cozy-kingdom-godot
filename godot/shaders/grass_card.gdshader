shader_type spatial;
// 草叢／花叢卡片：Codex 生成的透明元件貼在交叉面片上。
// 法線一律朝上（雙面卡片背面不會變黑、整片草光照一致）；根部壓暗接地；成片色差由世界座標低頻雜訊決定。
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform float alpha_cut = 0.45;
uniform vec3 root_color : source_color = vec3(0.16, 0.30, 0.10);
uniform vec3 dry_tint : source_color = vec3(1.15, 1.05, 0.6);
uniform vec3 lush_tint : source_color = vec3(0.8, 1.0, 0.75);
uniform float tint_amount = 0.6;
uniform float wind_strength = 0.18;
uniform float time_override = -1.0;

varying float hgt;
varying vec3 wpos;

void vertex() {
	hgt = 1.0 - UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float t = time_override >= 0.0 ? time_override : TIME;
	// 一陣陣的風從一個方向掃過，加上個別草叢的小抖動
	float gust = sin(t * 0.6 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + 0.7;
	float wv = (sin(t * 1.9 + origin.x * 0.35 + origin.z * 0.21) * 0.6 + sin(t * 3.3 + origin.x * 0.8) * 0.2) * gust;
	float hh = hgt * hgt;
	vec3 off = vec3(1.0, 0.0, 0.6) * wv * hh * wind_strength * 2.0;
	off.y = -abs(wv) * hh * wind_strength * 0.5;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = w;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float pn = texture(patch_noise, wpos.xz * 0.012).r;      // 80 m 尺度的成片色差
	float pn2 = texture(patch_noise, wpos.xz * 0.05 + 0.3).r; // 20 m 尺度
	vec3 tint = mix(lush_tint, dry_tint, smoothstep(0.35, 0.75, pn * 0.7 + pn2 * 0.3));
	vec3 c = tex.rgb * mix(vec3(1.0), tint, tint_amount) * COLOR.rgb;
	// 根部往地面色壓暗，看起來像長在土裡
	c = mix(root_color, c, smoothstep(0.0, 0.45, hgt));
	ALBEDO = c;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = alpha_cut;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.5 * hgt;
	AO = mix(0.45, 1.0, smoothstep(0.0, 0.6, hgt));
	AO_LIGHT_AFFECT = 0.4;
}
