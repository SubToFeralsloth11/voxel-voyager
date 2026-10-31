shader_type spatial;
// Flat-shaded low-poly surface: per-pixel face normals from screen derivatives.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float emission_strength = 0.0;

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.95;
	EMISSION = albedo.rgb * emission_strength;
}
