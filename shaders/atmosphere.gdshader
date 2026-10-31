shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;
// Additive rim glow drawn on the inside of a sphere around a planet.

uniform vec4 tint : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float strength = 0.9;

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = tint.rgb * pow(rim, 2.5) * strength;
}
