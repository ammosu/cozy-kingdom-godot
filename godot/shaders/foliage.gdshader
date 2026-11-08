shader_type spatial;
// 樹葉／灌木：頂點色（Blender 烘好的樹冠明暗）× 世界座標的葉叢雜訊，風吹搖擺、逆光透光
render_mode diffuse_lambert_wrap, cull_back;

uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.9;      // 每公尺幾格葉叢
uniform float sway = 0.12;            // 樹冠擺動幅度（公尺，樹頂）
uniform float sway_height = 8.0;      // 擺幅隨高度增加的參考高度
uniform vec3 tint : source_color = vec3(1.0);
uniform float time_override = -1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = dot(origin.xz, vec2(0.37, 0.21));
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float big = sin(t * 0.9 + ph) * 0.7 + sin(t * 1.7 + ph * 1.3) * 0.3;
	float small = sin(t * 4.0 + dot(w, vec3(1.3, 0.7, 1.1))) * 0.25;
	vec3 off = vec3(0.8, 0.0, 0.6) * (big + small) * sway * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = w;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 三平面取樣葉叢雜訊：讓大團樹冠表面有一簇簇的葉子明暗
	vec3 bw = pow(abs(wnrm), vec3(4.0)); bw /= (bw.x + bw.y + bw.z);
	float n = texture(leaf_noise, wpos.yz * noise_scale).r * bw.x
	        + texture(leaf_noise, wpos.xz * noise_scale).r * bw.y
	        + texture(leaf_noise, wpos.xy * noise_scale).r * bw.z;
	float n2 = texture(leaf_noise, wpos.xz * noise_scale * 3.1 + wpos.y).r;
	float leaf = mix(0.62, 1.18, n) * mix(0.85, 1.1, n2);
	ALBEDO = COLOR.rgb * tint * leaf;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	BACKLIGHT = COLOR.rgb * vec3(0.6, 0.8, 0.3) * 0.6;
	// 葉縫的暗處當 AO
	AO = mix(0.55, 1.0, smoothstep(0.25, 0.7, n));
	AO_LIGHT_AFFECT = 0.5;
}
