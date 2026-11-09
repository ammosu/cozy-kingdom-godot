shader_type fog;
// 貼著地形的流動薄霧：用烘好的地面高度算「離地高度」，3D 雜訊隨風飄移，大塊雲團與細碎流動疊加。

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect;         // 世界座標 x0, z0, 寬, 深
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform float density = 0.25;
uniform float mist_height = 3.5;  // 霧層厚度（公尺，離地）
uniform float coverage = 0.45;    // 越大越多地方有霧
uniform vec3 albedo : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 glow : source_color = vec3(0.6);
uniform vec3 wind = vec3(0.9, 0.05, 0.5);
uniform float time_override = -1.0;
uniform float near_start = 8.0;
uniform vec3 cam_pos;     // 鏡頭附近不起霧：霧要隨距離累積，近景才維持清楚

void fog() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec2 uv = (WORLD_POSITION.xz - height_rect.xy) / height_rect.zw;
	float ground = texture(height_tex, uv).r;
	float h = WORLD_POSITION.y - ground;
	float layer = smoothstep(0.0, 0.5, h + 0.3) * (1.0 - smoothstep(mist_height * 0.35, mist_height, h));
	float big = texture(noise_tex, WORLD_POSITION * vec3(0.022, 0.05, 0.022) + wind * t * 0.012).r;
	float fine = texture(noise_tex, WORLD_POSITION * vec3(0.09, 0.14, 0.09) - wind * t * 0.035).r;
	float n = smoothstep(1.0 - coverage - 0.2, 1.0 - coverage + 0.25, big * 0.72 + fine * 0.28);
	float near_fade = smoothstep(near_start, near_start * 5.0, distance(WORLD_POSITION, cam_pos));
	DENSITY = density * layer * n * near_fade;
	ALBEDO = albedo;
	// 陰影裡的霧只吃天空反彈光會整片變藍：補一點自發光，讓霧在陰影中維持奶白色
	EMISSION = glow * DENSITY;
}
