shader_type spatial;
// Vertex-coloured voxels. Vertex colours are authored in sRGB; alpha encodes
// glow: 1 = matte, 0 = full emission.

void fragment() {
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	EMISSION = col * (1.0 - COLOR.a) * 3.0;
}
