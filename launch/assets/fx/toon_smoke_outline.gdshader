// Outline pass for toon_smoke (inverted-hull, from 3dFireSmoke_v1.0 ToonSmokeOutline.gdshader idea; displacement removed).
shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width = 1.2;
uniform float wobble = 0.08;

void vertex() {
	float ph = INSTANCE_CUSTOM.x + dot(VERTEX, vec3(7.0, 5.0, 6.0));
	vec3 p = VERTEX + NORMAL * wobble * sin(ph + TIME * 1.6);
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(p, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
	clip_position.xy += normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_position.w * outline_width * 2.0;
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
