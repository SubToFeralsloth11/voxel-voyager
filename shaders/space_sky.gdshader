shader_type sky;
// Procedural starfield with a faint two-tone nebula band.

uniform vec3 nebula_a : source_color = vec3(0.16, 0.05, 0.28);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.12, 0.25);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 center = cell + 0.5 + (vec3(hash13(cell + 7.0), hash13(cell + 13.0), hash13(cell + 29.0)) - 0.5) * 0.6;
	float d = length(p - center);
	return smoothstep(0.12, 0.0, d) * (h - threshold) / (1.0 - threshold);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float s = stars(dir, 160.0, 0.93) * 1.6 + stars(dir, 420.0, 0.96);
	float band = exp(-pow(dir.y + 0.25 * sin(dir.x * 3.0), 2.0) * 9.0);
	float n = noise3(dir * 3.0) * 0.6 + noise3(dir * 7.0) * 0.4;
	vec3 neb = mix(nebula_a, nebula_b, noise3(dir * 2.0 + 4.0)) * band * n * 1.4;
	vec3 tint = mix(vec3(1.0, 0.9, 0.8), vec3(0.7, 0.85, 1.0), hash13(floor(dir * 160.0)));
	COLOR = vec3(0.004, 0.005, 0.012) + neb + tint * s;
}
