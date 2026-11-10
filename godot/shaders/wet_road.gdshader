shader_type spatial;
// 道路：乾的時候跟原本的貼圖材質相同；wet 拉高後整體變深、變亮面，低窪處積水。
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D puddle_tex : filter_linear, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform float base_rough = 1.0;
uniform float wet = 0.0;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	float p = texture(puddle_tex, wp.xz * 0.08).r;
	float puddle = smoothstep(0.54, 0.62, p) * wet;
	ALBEDO = texture(albedo_tex, uv).rgb * mix(1.0, 0.6, wet) * mix(1.0, 0.68, puddle);
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), puddle);
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(mix(base_rough, 0.38, wet), 0.05, puddle);
	SPECULAR = mix(0.5, 0.65, wet);
}
