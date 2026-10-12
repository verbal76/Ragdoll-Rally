shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, skip_vertex_transform;
// PROTOTYPE: comic-ink full-screen pass (GL Compatibility). Depth + colour edge lines, posterised colour wash, halftone shadows.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 c_dark : source_color = vec3(0.03, 0.05, 0.28);
uniform vec3 c_mid : source_color = vec3(0.10, 0.28, 0.85);
uniform vec3 c_light : source_color = vec3(0.62, 0.84, 1.0);
uniform float wash : hint_range(0.0, 1.0) = 0.85;
uniform float levels = 4.0;
uniform float line_px = 2.0;
uniform float depth_k = 0.035;
uniform float dot_px = 7.0;
uniform vec3 ink : source_color = vec3(0.02, 0.02, 0.06);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float d0 = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	// edges: depth discontinuities (silhouettes) + luminance steps (inner lines)
	float edge = 0.0;
	vec2 offs[8] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1), vec2(1, 1), vec2(-1, -1), vec2(1, -1), vec2(-1, 1));
	for (int i = 0; i < 8; i++) {
		vec2 uv = SCREEN_UV + offs[i] * px * line_px;
		float dn = lin_depth(uv, INV_PROJECTION_MATRIX);
		edge = max(edge, step(depth_k * d0 + 0.05, abs(dn - d0)));
		float ln = dot(texture(screen_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
		edge = max(edge, step(0.16, abs(ln - lum)) * 0.9);
	}
	// posterise + palette wash
	float p = floor(clamp(lum, 0.0, 0.999) * levels) / (levels - 1.0);
	p = clamp(p, 0.0, 1.0);
	vec3 pal = p < 0.5 ? mix(c_dark, c_mid, p * 2.0) : mix(c_mid, c_light, (p - 0.5) * 2.0);
	vec3 post = floor(col * 5.0) / 4.0;
	vec3 outc = mix(post, pal, wash);
	// accent: hot colours (fire, blood, sparks) keep their own hue, posterised, instead of taking the wash
	float warm = col.r - col.b;
	float acc = step(0.35, warm) * step(0.55, max(col.r, col.g));
	outc = mix(outc, floor(col * 4.0 + 0.5) / 4.0, acc);
	// halftone dots in the shadow band
	vec2 g = fract(FRAGCOORD.xy / dot_px) - 0.5;
	float dots = 1.0 - smoothstep(0.0, 0.08, length(g) - (0.55 - lum) * 0.9);
	outc = mix(outc, c_dark, dots * step(lum, 0.42) * 0.55 * (1.0 - acc));
	// sky stays clean
	float sky = step(0.9999, texture(depth_tex, SCREEN_UV).r);
	outc = mix(outc, mix(c_mid, c_light, SCREEN_UV.y * 0.0 + 0.6), sky * 0.0);
	ALBEDO = mix(outc, ink, edge * (1.0 - sky * 0.0));
}
