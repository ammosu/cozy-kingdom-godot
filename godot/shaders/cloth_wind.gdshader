shader_type spatial;
// 攤位遮棚：生成模型是一整塊網格，用模型空間位置推算哪裡是布（上段、避開四角的柱子），只讓那部分隨風擺動。
render_mode diffuse_lambert_wrap, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform mat3 node_basis;   // 生成模型的節點帶旋轉（mesh 的上方是 +Z），先轉回模型空間
uniform vec3 box_min;
uniform vec3 box_size;
uniform float cloth_low = 0.66;    // 模型高度比例：這以上才算遮棚
uniform float amount = 0.018;     // 模型單位（攤位放大約 1.5 倍，布邊最大約 5 公分）
uniform float time_override = -1.0;

void vertex() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec3 q = node_basis * VERTEX;
	vec3 n = (q - box_min) / box_size;
	vec2 c = abs(n.xz * 2.0 - 1.0);
	float not_post = 1.0 - smoothstep(0.62, 0.86, min(c.x, c.y));       // 四角的柱子不動
	float mask = smoothstep(cloth_low, cloth_low + 0.12, n.y) * not_post;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.31 + o.z * 0.47;
	// 布是繃在棚架上的：棚面幾乎不動，只有慢而長的起伏，垂下的布邊才看得出飄
	float wave = sin(t * 1.4 + q.x * 2.2 + ph) * 0.7 + sin(t * 2.3 + q.z * 3.1 + q.x * 1.7 + ph * 2.0) * 0.3;
	float s = 0.5 + 0.5 * sin(t * 0.37 + ph);
	float gust = 0.35 + 0.65 * s * s;   // 多數時間微風，偶爾才吹一陣
	float lip = 0.35 + 1.65 * c.y * c.y;
	VERTEX += transpose(node_basis) * (vec3(0.25, 1.0, 0.45) * wave * gust * lip * amount * mask);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
