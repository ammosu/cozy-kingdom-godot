shader_type spatial;
// 噴水池水面：位置＋時間的純函式（沒有模擬狀態）。水面不動，波紋、泡沫、荷葉全在 fragment 畫。
render_mode blend_mix, cull_disabled, depth_draw_always, diffuse_lambert_wrap;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 impacts[5];          // xz＝水落下的位置（模型單位）、z 分量＝強度
uniform vec3 deep : source_color = vec3(0.05, 0.28, 0.36);
uniform vec3 shallow : source_color = vec3(0.24, 0.66, 0.68);
uniform float radius = 0.9;
uniform float pads_on = 1.0;
uniform float time_override = -1.0;

varying vec2 p;

void vertex() { p = VERTEX.xz; }

float pad(vec2 q, vec2 c, float r, float notch) {
	vec2 d = q - c;
	float a = atan(d.y, d.x);
	float cut = smoothstep(0.0, 0.22, abs(mod(a - notch + PI, TAU) - PI));   // 荷葉的缺口
	return (1.0 - smoothstep(r - 0.008, r, length(d))) * cut;
}

void fragment() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec2 g = vec2(0.0);
	float foam = 0.0;
	float n1 = texture(noise_tex, p * 1.7 + vec2(t * 0.05, t * 0.03)).r;
	float n2 = texture(noise_tex, p * 3.6 - vec2(t * 0.07, -t * 0.05)).r;
	for (int i = 0; i < 5; i++) {
		float s = impacts[i].z;
		if (s <= 0.0) { continue; }
		vec2 d = p - impacts[i].xy;
		float r = length(d) + 0.0001;
		// 落水點往外擴散的同心圓：兩組不同波長疊加，距離越遠越弱
		float env = exp(-r * 5.5) * s;
		g += d / r * (cos(r * 62.0 - t * 9.0) * 0.5 + cos(r * 31.0 - t * 5.6 + n1 * 4.0) * 0.5) * env * 1.2;
		float jag = (n2 - 0.5) * 0.09;
		foam += (1.0 - smoothstep(0.03, 0.15 * s, r + jag)) * 1.15;
		foam += smoothstep(0.52, 0.8, n2 + n1 * 0.2) * (1.0 - smoothstep(0.08, 0.3, r)) * 0.8;
	}
	// 細碎水波（用雜訊的梯度）
	float e = 0.012;
	float h0 = texture(noise_tex, p * 2.4 + vec2(t * 0.09, t * 0.06)).r;
	vec2 chop = vec2(texture(noise_tex, p * 2.4 + vec2(t * 0.09 + e, t * 0.06)).r - h0, texture(noise_tex, p * 2.4 + vec2(t * 0.09, t * 0.06 + e)).r - h0) / e;
	g += chop * 0.018;
	vec3 local_n = normalize(vec3(-g.x, 1.0, -g.y));
	vec3 view_n = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * local_n);
	foam = clamp(foam, 0.0, 1.0);
	// 水底的光紋（兩層雜訊相乘）
	float caustic = pow(1.0 - abs(texture(noise_tex, p * 4.5 + vec2(t * 0.08, 0.0)).r - texture(noise_tex, p * 4.5 - vec2(0.0, t * 0.1) + 0.37).r), 14.0);
	float edge = smoothstep(radius * 0.55, radius, length(p));
	vec3 col = mix(deep, shallow, 0.35 + 0.35 * edge + n1 * 0.2) + vec3(0.55, 0.65, 0.5) * caustic * 0.55;
	col = mix(col, vec3(0.93, 0.97, 1.0), foam);
	float rough = mix(0.08, 0.7, foam);
	float alpha = mix(0.92, 1.0, foam);
	vec3 final_n = view_n;
	// 荷葉：畫在水面上，跟著水慢慢漂
	if (pads_on > 0.5) {
		float bob = sin(t * 0.5) * 0.008;
		float mask = 0.0;
		mask = max(mask, pad(p, vec2(-0.66, 0.27 + bob), 0.09, 0.8));
		mask = max(mask, pad(p, vec2(0.68, 0.20 - bob), 0.085, 2.6));
		mask = max(mask, pad(p, vec2(0.25, -0.67 + bob), 0.075, 4.4));
		if (mask > 0.0) {
			float vein = sin(atan(p.y, p.x) * 90.0) * 0.04 + n2 * 0.2;
			vec3 leaf = mix(vec3(0.18, 0.42, 0.14), vec3(0.42, 0.62, 0.2), vein + 0.45);
			col = mix(col, leaf, mask);
			rough = mix(rough, 0.55, mask);
			alpha = mix(alpha, 1.0, mask);
			final_n = normalize(mix(final_n, normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * vec3(0.0, 1.0, 0.0)), mask));
		}
	}
	NORMAL = final_n;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.65;
	ALPHA = alpha;
}
