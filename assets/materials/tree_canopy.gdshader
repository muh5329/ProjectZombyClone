shader_type spatial;
// Round 11: tree canopies (MultiMesh, per-instance colour). Canopies
// between the camera and the player are dithered out (PZ-style tree
// fade) so the player is never lost under the woods. WorldBuilder feeds
// fade_center (player) / eye_dir (flat direction scene -> eye) per frame.
render_mode diffuse_lambert, specular_disabled;

uniform vec3 fade_center = vec3(0.0, -1000.0, 0.0);
uniform vec2 eye_dir = vec2(0.7, 0.7);
uniform float fade_width = 3.2;
uniform float fade_length = 14.0;

varying vec3 wpos;
varying vec3 tint;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = COLOR.rgb;
}

void fragment() {
	vec2 d = wpos.xz - fade_center.xz;
	float along = dot(d, eye_dir);
	float perp = length(d - along * eye_dir);
	float in_zone = step(-2.5, along) * (1.0 - smoothstep(fade_length, fade_length + 3.0, along))
		* (1.0 - smoothstep(fade_width, fade_width + 1.5, perp));
	if (in_zone > 0.01) {
		// 4x4 ordered dither: keep ~25 % of the pixels in the fade zone.
		ivec2 q = ivec2(FRAGCOORD.xy) % 4;
		int idx = q.x + q.y * 4;
		float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if (bayer[idx] / 16.0 < 0.75 * in_zone) {
			discard;
		}
	}
	float shade = 0.85 + 0.15 * clamp((wpos.y - 2.0) / 4.0, 0.0, 1.0);
	ALBEDO = tint * shade;
	ROUGHNESS = 1.0;
}
