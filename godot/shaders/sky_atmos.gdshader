shader_type sky;
// 大氣散射的天空＋體積雲。雲在半解析度算，反射用的 cubemap 只算便宜版，雲飄動時才不會每幀重烘環境光。
// 雲的時間用 global uniform：一般 uniform 每次更新都會讓 cubemap 重算。
render_mode use_half_res_pass;

global uniform float cloud_t;
uniform sampler3D shape_tex : repeat_enable, filter_linear;
uniform sampler3D detail_tex : repeat_enable, filter_linear;
uniform float coverage = 0.47;
uniform float storm = 0.0;       // 0 白雲、1 雨雲
uniform float haze = 1.0;        // 空氣裡的懸浮微粒，越大太陽周圍越白、地平線越濁
uniform float flat_mix = 0.0;    // 濃霧時整片天空換成霧色，遠山才會融進去
uniform vec3 flat_col = vec3(0.85);

const float H0 = 1.1;            // 雲底（公里）
const float H1 = 2.0;            // 雲頂
const int VIEW_STEPS = 26;
const float PI_ = 3.14159265;

float airmass(float c) {
	c = clamp(c, 0.0, 1.0);
	return 1.0 / (c + 0.15 * pow(max(93.885 - degrees(acos(c)), 0.1), -1.253));
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI_ * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

vec3 sun_trans(vec3 s) {
	vec3 tr = vec3(0.046, 0.108, 0.265);
	return exp(-(tr + 0.03 * haze) * airmass(s.y));
}

vec3 atmosphere(vec3 d, vec3 s) {
	float mu = dot(d, s);
	float low_sun = 1.0 - smoothstep(0.08, 0.5, s.y);
	float up = max(d.y, 0.0);
	// 天頂到地平線的漸層：地平線那段路徑長、空氣厚，所以偏白；顏色寬度隨懸浮微粒變
	float grad = pow(1.0 - up, mix(5.5, 2.6, clamp((haze - 1.0) / 2.5, 0.0, 1.0)));
	vec3 zen = mix(vec3(0.018, 0.165, 0.74), vec3(0.075, 0.165, 0.430), low_sun);
	vec3 hor = mix(vec3(0.50, 0.76, 1.02), vec3(0.72, 0.68, 0.70), low_sun);
	vec2 flat_d = normalize(d.xz + vec2(1e-4));
	vec2 flat_s = normalize(s.xz + vec2(1e-4));
	float az = dot(flat_d, flat_s) * 0.5 + 0.5;
	hor = mix(hor, vec3(1.25, 0.74, 0.40), low_sun * az * az);        // 朝太陽那一側暖
	vec3 sky = mix(zen, hor, grad);
	sky *= 0.86 + 0.28 * (1.0 + mu * mu) * 0.5;                       // 瑞利散射：垂直太陽方向較暗
	vec3 sun_tint = sun_trans(s) * vec3(1.0, 0.95, 0.86);
	float m = max(mu, 0.0);
	sky += sun_tint * (pow(m, 900.0) * 1.4 + pow(m, 60.0) * 0.11 + pow(m, 8.0) * 0.025) * mix(1.0, 1.7, clamp(haze - 1.0, 0.0, 1.0));
	return sky;
}

float density(vec3 p, float lod_detail, float cov) {
	float h = clamp((p.y - H0) / (H1 - H0), 0.0, 1.0);
	vec3 wind = vec3(cloud_t * 0.03, 0.0, cloud_t * 0.012);
	float n = texture(shape_tex, (p + wind) * vec3(0.17, 0.3, 0.17)).r;
	float big = texture(shape_tex, (p + wind * 0.6) * vec3(0.05, 0.08, 0.05) + 0.37).r;
	n = n * 0.58 + big * 0.56;
	float profile = smoothstep(0.0, 0.14, h) * smoothstep(1.0, 0.38, h);
	float d = n - (1.0 - cov) * 1.02 - (1.0 - profile) * 0.32;
	if (d <= 0.0) {
		return 0.0;
	}
	if (lod_detail > 0.0) {
		float w = texture(detail_tex, (p + wind * 1.4) * vec3(1.25, 1.6, 1.25)).r;
		d -= (1.0 - w) * mix(0.22, 0.09, h) * lod_detail;   // 雲底侵蝕多，頂部保留圓潤的輪廓
	}
	return clamp(d * 11.0, 0.0, 1.0);
}

vec4 clouds(vec3 d, vec3 s, vec3 sky_col, float jitter) {
	if (d.y < 0.015) {
		return vec4(0.0);
	}
	float t0 = H0 / d.y;
	float t1 = min(H1 / d.y, t0 + 18.0);
	if (t0 > 90.0) {
		return vec4(0.0);
	}
	float dt = (t1 - t0) / float(VIEW_STEPS);
	float mu = dot(d, s);
	float phase = min(mix(hg(mu, 0.72), hg(mu, -0.2), 0.45) * 4.0 * PI_ * 0.55 + 0.45, 1.5);
	vec3 sun_c = sun_trans(s) * vec3(1.0, 0.97, 0.92) * 5.2 * mix(1.0, 0.14, storm);
	vec3 amb = mix(sky_col * 0.55 + vec3(0.30, 0.33, 0.40), vec3(0.34, 0.36, 0.40), storm);
	vec3 col = vec3(0.0);
	float tr = 1.0;
	float t = t0 + dt * jitter;
	float sig = 1.5 * mix(1.0, 1.6, storm);
	for (int i = 0; i < VIEW_STEPS; i++) {
		vec3 p = d * t;
		float rho = density(p, 1.0, coverage);
		if (rho > 0.002) {
			float ld = 0.0;
			float step_l = 0.09;
			vec3 q = p;
			for (int j = 0; j < 4; j++) {
				q += s * step_l;
				ld += density(q, 0.0, coverage) * step_l;
				step_l *= 1.7;
			}
			float beer = max(exp(-ld * 6.0), 0.42 * exp(-ld * 1.1));   // 第二項是多次散射，厚雲深處不會黑掉
			float powder = 1.0 - 0.55 * exp(-rho * 7.0);
			float hf = clamp((p.y - H0) / (H1 - H0), 0.0, 1.0);
			vec3 sc = sun_c * beer * powder * phase + amb * mix(0.48, 1.0, hf);
			float a = 1.0 - exp(-rho * sig * dt * 10.0);
			col += tr * a * sc;
			tr *= 1.0 - a;
			if (tr < 0.02) {
				break;
			}
		}
		t += dt;
	}
	// 越遠的雲越融進大氣
	float aerial = exp(-max(t0 - 4.0, 0.0) * 0.022);
	col = mix(sky_col * (1.0 - tr), col, aerial);
	float fade = smoothstep(0.015, 0.07, d.y);
	return vec4(col * fade, (1.0 - tr) * fade);
}

float ign(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, 1.0, 0.0);
	vec3 air = atmosphere(d, s);
	// 雨雲把整片大氣蓋掉，地平線也不該亮
	vec3 overcast = mix(air, vec3(0.42, 0.45, 0.50), storm);
	if (d.y < 0.0) {
		overcast = mix(overcast, vec3(0.25, 0.33, 0.22), smoothstep(0.0, -0.25, d.y));
	}
	if (AT_CUBEMAP_PASS) {
		vec3 cheap = mix(overcast, mix(vec3(0.95, 0.97, 1.0), vec3(0.3, 0.32, 0.36), storm), smoothstep(0.0, 0.3, d.y) * coverage * 0.55);
		COLOR = mix(cheap, flat_col, flat_mix);
	} else if (AT_HALF_RES_PASS) {
		if (flat_mix >= 1.0) {
			COLOR = vec3(0.0);
			ALPHA = 0.0;
		} else {
			vec4 c = clouds(d, s, overcast, ign(FRAGCOORD.xy));
			COLOR = c.rgb;
			ALPHA = c.a;
		}
	} else {
		float mu = dot(d, s);
		float r = acos(clamp(mu, -1.0, 1.0));
		float disk = smoothstep(0.0062, 0.0046, r) * (0.6 + 0.4 * sqrt(max(1.0 - pow(r / 0.0062, 2.0), 0.0)));
		vec3 sun = sun_trans(s) * disk * 34.0 * step(0.0, d.y) * (1.0 - storm);
		vec3 base = overcast + sun;
		base = base * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb;
		COLOR = mix(base, flat_col, flat_mix);
	}
}
