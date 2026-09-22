shader_type canvas_item;
// Red screen-edge flash when the player takes damage. HUD tweens `strength`.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.75, 0.05, 0.03);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.2, 0.72, length(d));
	COLOR = vec4(tint, v * strength);
}
