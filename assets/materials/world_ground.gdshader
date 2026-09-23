shader_type spatial;
// Round 11: terrain of the generated world. The layout is baked into a
// low-res colour splat (1 texel per 2 m: meadow / woods floor / farmland
// soil / yards / water banks); value noise breaks up the texels so the
// ground reads as grass, not pixels.
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D splat : source_color, filter_linear, repeat_disable;
uniform vec2 world_size = vec2(768.0, 768.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Jitter the lookup a little so texel edges wobble.
	vec2 j = vec2(vnoise(wpos.xz * 0.5), vnoise(wpos.xz * 0.5 + 17.0)) - 0.5;
	vec3 c = texture(splat, (wpos.xz + j * 1.6) / world_size).rgb;
	float n = vnoise(wpos.xz * 0.4) * 0.55 + vnoise(wpos.xz * 2.1) * 0.3 + vnoise(wpos.xz * 7.0) * 0.15;
	c *= 0.84 + 0.3 * n;
	// Worn dirt patches and dry tufts on grass (greenish texels only).
	float grass = step(c.r * 1.04, c.g);
	float dp = vnoise(wpos.xz * 0.07 + 31.0) * 0.7 + vnoise(wpos.xz * 0.35) * 0.3;
	c = mix(c, vec3(0.4, 0.35, 0.26) * (0.9 + 0.2 * n), smoothstep(0.66, 0.8, dp) * 0.55 * grass);
	float dry = vnoise(wpos.xz * 0.9 + 5.0);
	c = mix(c, c * vec3(1.12, 1.05, 0.82), smoothstep(0.6, 0.9, dry) * 0.5 * grass);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
