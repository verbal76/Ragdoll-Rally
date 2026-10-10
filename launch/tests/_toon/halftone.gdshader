shader_type canvas_item;
uniform vec4 dot_col : source_color = vec4(0.0, 0.0, 0.0, 0.25);
uniform float dot_px = 9.0;
uniform float falloff_y = 0.0;
void fragment() {
	vec2 g = fract(FRAGCOORD.xy / dot_px) - 0.5;
	float r = mix(0.12, 0.5, UV.y * falloff_y + (1.0 - falloff_y) * 0.5);
	float d = 1.0 - smoothstep(r - 0.05, r, length(g));
	COLOR = vec4(dot_col.rgb, dot_col.a * d);
}
