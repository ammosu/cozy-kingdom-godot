shader_type spatial;
// 地形：近處是草地貼圖；越遠越靠大尺度色塊（深林、草坡、岩石），讓山不是一塊平滑的綠幕
render_mode diffuse_lambert_wrap;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear, repeat_enable;
uniform float wet = 0.0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
	vec2 uv = wp.xz * 0.18;
	vec3 tex = texture(albedo_tex, uv).rgb;
	float d = length(wp.xz);
	float m1 = texture(macro_tex, wp.xz * 0.0045).r;
	float m2 = texture(macro_tex, wp.xz * 0.016 + 0.3).r;
	float m3 = texture(macro_tex, wp.xz * 0.06 + 0.7).r;
	vec3 near_col = tex * vec3(0.50, 0.60, 0.36) * mix(0.82, 1.08, m2);
	near_col = mix(near_col, vec3(0.30, 0.25, 0.14), smoothstep(0.55, 0.78, m3) * 0.35);   // 局部露土
	float far = smoothstep(120.0, 210.0, d);
	vec3 land = mix(vec3(0.07, 0.17, 0.10), vec3(0.34, 0.47, 0.20), smoothstep(0.3, 0.66, m1 + m2 * 0.35 - 0.16));   // 深林與向陽草坡的大色塊
	land = mix(land, vec3(0.60, 0.62, 0.32), smoothstep(0.6, 0.78, m2) * 0.55);
	float slope = 1.0 - wn.y;
	vec3 rock = vec3(0.34, 0.31, 0.26) * mix(0.7, 1.15, m3);
	land = mix(land, rock, smoothstep(0.5, 0.72, slope + (m3 - 0.5) * 0.2) * 0.5);
	land = mix(land, rock * 1.15, smoothstep(150.0, 240.0, wp.y + (m2 - 0.5) * 40.0) * 0.55);
	land *= mix(0.82, 1.15, m3);
	ALBEDO = mix(near_col, land, far) * mix(1.0, 0.74, wet * (1.0 - far));
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - far);
	ROUGHNESS = mix(0.95, 0.55, wet);
	SPECULAR = mix(0.15, 0.35, wet);
}
