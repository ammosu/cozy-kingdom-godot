shader_type spatial;
// 草叢／花叢卡片：Codex 生成的透明元件貼在交叉面片上。
// 法線一律朝上（雙面卡片背面不會變黑、整片草光照一致）；根部壓暗接地；成片色差由世界座標低頻雜訊決定。
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform float alpha_cut = 0.45;
uniform vec3 root_color : source_color = vec3(0.16, 0.30, 0.10);
uniform vec3 dry_tint : source_color = vec3(0.98, 0.92, 0.58);
uniform vec3 lush_tint : source_color = vec3(0.62, 0.84, 0.6);
uniform float tint_amount = 0.75;
uniform float wind_strength = 0.2;
uniform vec2 wind_dir = vec2(0.86, 0.5);
uniform float time_override = -1.0;
// 踩過的位置：xyz＝世界座標、w＝影響半徑（0 = 不作用）。第 0 個是玩家當下位置，其餘是腳印，半徑隨時間縮小，草就慢慢彈回來
uniform vec4 pushers[6];

varying float hgt;
varying float gust_v;
varying vec3 wpos;

void vertex() {
	hgt = 1.0 - UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float t = time_override >= 0.0 ? time_override : TIME;
	// 一陣陣的風從一個方向掃過，加上個別草叢的小抖動
	float gust = sin(t * 0.6 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + 0.7;
	// 一道道風浪沿風向掃過草原（寬約 25 m、每秒走約 9 m）
	float front = dot(origin.xz, wind_dir);
	float wave = pow(sin(front * 0.24 - t * 2.1) * 0.5 + 0.5, 3.0);
	gust += wave * 1.1;
	gust_v = wave;
	float wv = (sin(t * 1.9 + origin.x * 0.35 + origin.z * 0.21) * 0.6 + sin(t * 3.3 + origin.x * 0.8) * 0.2) * gust;
	float hh = hgt * hgt;
	vec3 off = vec3(1.0, 0.0, 0.6) * wv * hh * wind_strength * 2.0;
	off.y = -abs(wv) * hh * wind_strength * 0.5;
	off.xz += wind_dir * wave * hh * wind_strength * 1.6;   // 風浪經過時整片往下風處倒
	vec2 to_player = origin.xz - pushers[0].xz;
	if (dot(to_player, to_player) < 64.0) {   // 離玩家 8 m 外跳過，幾十萬叢草不用每叢都算
		float inst_h = length(MODEL_MATRIX[1].xyz);
		for (int i = 0; i < 6; i++) {
			if (pushers[i].w <= 0.0) { continue; }
			vec2 d = origin.xz - pushers[i].xz;
			float len = length(d) + 0.0001;
			float k = smoothstep(pushers[i].w, pushers[i].w * 0.3, len);
			if (k <= 0.0) { continue; }
			off.xz += d / len * k * hh * inst_h * 0.85;
			off.y -= k * hh * inst_h * 0.45;
		}
	}
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
	c *= 1.0 + gust_v * hgt * 0.22;   // 被風壓彎的草反光變亮，遠看像一道光掃過
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
