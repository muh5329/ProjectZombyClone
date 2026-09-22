// Blockout ground: base colour with 1 m grid lines and stronger 10 m lines.
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.30, 0.38, 0.24);
uniform vec3 line_color : source_color = vec3(0.22, 0.28, 0.18);
uniform float line_width = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	float d = min(g.x, g.y);
	return 1.0 - smoothstep(0.0, width, d);
}

void fragment() {
	float g1 = grid(world_pos.xz, 1.0, line_width);
	float g10 = grid(world_pos.xz, 10.0, line_width * 2.5);
	float m = max(g1 * 0.6, g10);
	ALBEDO = mix(base_color, line_color, m);
	ROUGHNESS = 0.95;
}
