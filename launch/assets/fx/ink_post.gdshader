shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, skip_vertex_transform;
// PROTOTYPE v2: comic ink WITHOUT a colour wash. Every surface keeps its own hue (cel-banded, saturated), shadows lean cool,
// halftone dots in shadow, black ink lines. The sky is left alone.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float bands = 6.0;
uniform float detail_keep = 0.5;    // how much of the original shading survives the cel bands (texture / window / trim detail)
uniform float sat_boost = 1.45;
uniform float contrast = 1.12;
uniform vec3 shadow_tint : source_color = vec3(0.55, 0.5, 0.95);
uniform float line_px = 1.0;
uniform float depth_k = 0.035;
uniform float dot_px = 5.0;
uniform vec3 ink : source_color = vec3(0.03, 0.02, 0.06);

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
	float raw_d = texture(depth_tex, SCREEN_UV).r;
	float sky = step(0.9999, raw_d);
	float lum = max(dot(col, vec3(0.299, 0.587, 0.114)), 0.0001);
	float d0 = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float edge = 0.0;
	// 1-pixel lines: depth steps (silhouettes, creases between surfaces) and a Sobel on brightness (windows, trim, panel edges)
	vec2 offs[8] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1), vec2(1, 1), vec2(-1, -1), vec2(1, -1), vec2(-1, 1));
	float l[8];
	for (int i = 0; i < 8; i++) {
		vec2 uv = SCREEN_UV + offs[i] * px * line_px;
		float dn = lin_depth(uv, INV_PROJECTION_MATRIX);
		float nsky = step(0.9999, texture(depth_tex, uv).r);
		// only the nearer side of a depth step is inked, so the line stays one pixel wide
		edge = max(edge, step(depth_k * d0 + 0.05, abs(dn - d0)) * step(d0, dn) * (1.0 - sky * nsky));
		l[i] = dot(texture(screen_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
	}
	float gx = (l[0] - l[1]) * 2.0 + (l[4] - l[7]) + (l[6] - l[5]);
	float gy = (l[2] - l[3]) * 2.0 + (l[4] - l[6]) + (l[7] - l[5]);
	edge = max(edge, smoothstep(0.34, 0.5, length(vec2(gx, gy))) * (1.0 - sky));
	// cel bands on brightness only: hue and saturation stay the surface's own
	float band = (floor(clamp(lum * contrast, 0.0, 0.999) * bands) + 0.5) / bands;
	vec3 hue = col / lum;
	float shade_l = mix(band, lum * contrast, detail_keep);
	vec3 cel = hue * shade_l;
	cel = mix(vec3(shade_l), cel, sat_boost);
	// the darkest band leans cool (purple-blue shadows) instead of just going grey
	float shade = 1.0 - smoothstep(0.0, 0.45, band);
	cel = mix(cel, cel * shadow_tint * 1.35, shade * 0.6);
	// halftone dots in the darker bands, in a darker shade of the surface colour
	vec2 g = fract(FRAGCOORD.xy / dot_px) - 0.5;
	float dots = 1.0 - smoothstep(0.0, 0.08, length(g) - (0.6 - band) * 0.8);
	cel = mix(cel, cel * 0.7, dots * step(band, 0.34));
	vec3 outc = mix(cel, col, sky);                 // sky: untouched
	ALBEDO = mix(outc, ink, edge);
}
