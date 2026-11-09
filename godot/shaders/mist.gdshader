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
uniform float ground_density = 0.0;   // 貼地低霧：鏡頭近處也看得到，揮劍吹開時最明顯
uniform float ground_height = 1.3;    // 低霧厚度（公尺，離地）
// 揮劍的風：每道是一段往前推的膠囊。a＝起點＋目前長度，b＝方向＋強度（0 = 沒有），r＝半徑
uniform vec4 gust_a[4];
uniform vec4 gust_b[4];
uniform float gust_r[4];
// 下劈落地的衝擊波：a＝中心＋波前半徑（0 = 沒有），b＝x 清空半徑、y 堆積強度、z 霧團被推動的距離
uniform vec4 blast_a[2];
uniform vec4 blast_b[2];
uniform vec3 cam_pos;     // 鏡頭附近不起霧：霧要隨距離累積，近景才維持清楚

void fog() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec2 uv = (WORLD_POSITION.xz - height_rect.xy) / height_rect.zw;
	float ground = texture(height_tex, uv).r;
	float h = WORLD_POSITION.y - ground;
	float edge = texture(noise_tex, WORLD_POSITION * vec3(0.09, 0.14, 0.09) - wind * t * 0.035).r;
	float clear = 0.0;   // 被風清空的程度
	float pile = 0.0;    // 被推到波前、堆起來的程度
	vec3 warp = vec3(0.0);   // 霧團被推動的位移，讓一縷縷的霧真的往外走
	for (int i = 0; i < 4; i++) {
		float amt = gust_b[i].w;
		if (amt <= 0.0) { continue; }
		vec3 p = WORLD_POSITION - gust_a[i].xyz;
		float along = clamp(dot(p, gust_b[i].xyz), 0.0, gust_a[i].w);
		float d = length(p - gust_b[i].xyz * along);
		float r = gust_r[i] * (0.55 + along / max(gust_a[i].w, 1.0) * 1.1) * (0.7 + edge * 0.6);   // 風往前擴散成扇形，細雜訊把邊緣撕碎
		float inside = 1.0 - smoothstep(r * 0.45, r, d);
		clear = max(clear, inside * amt);
		warp += gust_b[i].xyz * gust_a[i].w * 0.2 * (1.0 - smoothstep(r, r * 1.8, d)) * amt;
	}
	for (int i = 0; i < 2; i++) {
		float front = blast_a[i].w;
		if (front <= 0.0) { continue; }
		vec3 q = WORLD_POSITION - blast_a[i].xyz;
		float dh = length(q.xz) + 0.001;
		float hole = blast_b[i].x * (0.8 + edge * 0.4);
		clear = max(clear, (1.0 - smoothstep(hole * 0.65, hole, dh)) * (1.0 - smoothstep(2.0, 6.0, q.y)));
		pile = max(pile, smoothstep(front * 0.68, front, dh) * (1.0 - smoothstep(front, front * 1.3, dh)) * blast_b[i].y);
		warp.xz += q.xz / dh * blast_b[i].z * (1.0 - smoothstep(front, front * 1.7, dh));
	}
	vec3 flow = WORLD_POSITION - warp;
	float layer = smoothstep(0.0, 0.5, h + 0.3) * (1.0 - smoothstep(mist_height * 0.35, mist_height, h));
	float big = texture(noise_tex, flow * vec3(0.022, 0.05, 0.022) + wind * t * 0.012).r;
	float fine = texture(noise_tex, flow * vec3(0.09, 0.14, 0.09) - wind * t * 0.035).r;
	// 平常的濃淡變化：每一片霧照自己的節奏慢慢變濃變淡，比整片一起呼吸自然
	float breathe = 0.8 + 0.2 * sin(t * 0.42 + big * 18.0) + 0.1 * sin(t * 0.91 + fine * 11.0);
	float n = smoothstep(1.0 - coverage - 0.2, 1.0 - coverage + 0.25, big * 0.72 + fine * 0.28) * breathe;
	float cam_d = distance(WORLD_POSITION, cam_pos);
	float near_fade = smoothstep(near_start, near_start * 5.0, cam_d);
	// 貼地低霧：被推到波前的霧會翻高、變濃
	float top = ground_height * (1.0 + 2.4 * pile);
	float low = smoothstep(-0.3, 0.1, h) * (1.0 - smoothstep(top * 0.3, top, h));
	float wisp = smoothstep(0.32, 0.68, big * 0.35 + texture(noise_tex, flow * vec3(0.16, 0.3, 0.16) + wind * t * 0.11).r * 0.65) * breathe;
	float low_fog = ground_density * low * mix(0.35, 1.0, wisp) * (1.0 + 1.5 * pile) * smoothstep(1.5, 5.0, cam_d) * (1.0 - smoothstep(30.0, 60.0, cam_d));   // 遠處體素太粗，薄層會變成一圈圈色階
	DENSITY = (density * layer * n * near_fade + low_fog) * (1.0 - clear);
	ALBEDO = albedo;
	// 陰影裡的霧只吃天空反彈光會整片變藍：補一點自發光，讓霧在陰影中維持奶白色
	EMISSION = glow * DENSITY;
}
