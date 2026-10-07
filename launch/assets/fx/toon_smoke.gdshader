// Ragdoll Rally adaptation of 3dFireSmoke_v1.0 ToonSmoke.gdshader (see third_party/NOTICE.md).
// Changes: no screen-texture read, no per-vertex Voronoi (cheap sine wobble), fixed-direction two-band toon shade.
// Opaque (no alpha blending): meant for low-poly sphere puffs from CPUParticles3D that shrink to nothing.
shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform vec4 smoke_color : source_color = vec4(0.70, 0.70, 0.70, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.97, 0.98, 0.98, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.18, 0.27, 0.30, 1.0);
uniform float wobble = 0.08;
uniform float emissive = 0.0;       // >0 makes it self-lit (fireball / flash puffs)
varying vec3 nrm_view;

void vertex() {
	float ph = INSTANCE_CUSTOM.x + dot(VERTEX, vec3(7.0, 5.0, 6.0));
	VERTEX += NORMAL * wobble * sin(ph + TIME * 1.6);
	nrm_view = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	vec3 L = normalize((VIEW_MATRIX * vec4(0.4, 0.8, 0.35, 0.0)).xyz);
	float l = floor(clamp(dot(normalize(nrm_view), L), 0.0, 1.0) * 2.0) / 2.0;   // posterize
	vec3 shaded = mix(smoke_color.rgb * 0.62 + shadow_color.rgb * 0.12, min(smoke_color.rgb * 1.3 + highlight_color.rgb * 0.08, vec3(1.0)), l);
	ALBEDO = mix(shaded, smoke_color.rgb, emissive);
	EMISSION = smoke_color.rgb * emissive;
}
