shader_type spatial;
// Vertex-coloured voxels. Colour alpha encodes glow: 1 = matte, 0 = full emission.

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * 2.5;
}
