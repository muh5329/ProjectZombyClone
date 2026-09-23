shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// A flat ring on a 2x2 plane scaled to the ring radius: the band is
// [thickness_m] metres wide whatever the scale, faded at both edges.
uniform vec4 ring_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float alpha = 1.0;
uniform float radius_m = 5.0;
uniform float thickness_m = 0.24;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float t = clamp(thickness_m / max(radius_m, 0.01), 0.004, 0.5);
	float band = smoothstep(1.0 - t, 1.0 - t * 0.5, r) * (1.0 - smoothstep(1.0 - t * 0.5, 1.0, r));
	// A faint fill so big rings still read as an area.
	float fill = (1.0 - smoothstep(0.0, 1.0, r)) * 0.06 * step(r, 1.0);
	ALBEDO = ring_color.rgb;
	ALPHA = clamp(band + fill, 0.0, 1.0) * alpha * ring_color.a;
}
