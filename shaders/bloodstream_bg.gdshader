shader_type canvas_item;

uniform float scroll_speed = 0.18;
uniform vec4 color_deep : source_color = vec4(0.08, 0.015, 0.04, 1.0);
uniform vec4 color_mid : source_color = vec4(0.20, 0.03, 0.09, 1.0);
uniform vec4 color_vein : source_color = vec4(0.42, 0.07, 0.17, 1.0);
uniform vec4 color_wall : source_color = vec4(0.32, 0.05, 0.14, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Desplazamiento hacia abajo en pantalla (UV.y decrece al avanzar el tiempo).
	vec2 flow_far = vec2(UV.x * 3.0, UV.y * 5.2 - TIME * scroll_speed);
	vec2 flow_near = vec2(UV.x * 5.5 + 1.7, UV.y * 9.0 - TIME * (scroll_speed * 1.75));

	float n_far = fbm(flow_far);
	float n_near = fbm(flow_near + vec2(n_far * 0.8, 0.0));

	// Venas orgánicas finas que recorren el torrente.
	float vein_wave = abs(sin((UV.x * 4.5 + n_far * 1.4) * 3.14159));
	float veins = smoothstep(0.92, 0.995, 1.0 - vein_wave) * n_near;

	vec3 col = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.25, 0.78, n_far));
	col = mix(col, color_vein.rgb, smoothstep(0.45, 0.9, n_near) * 0.55 + veins * 0.65);

	// Paredes orgánicas en los bordes izquierdo y derecho para dar sensación de túnel.
	float wall_wobble = sin((UV.y * 6.28318 - TIME * scroll_speed * 2.2) + n_far * 2.0) * 0.035;
	float edge_dist = abs(UV.x - 0.5) * 2.0 + wall_wobble;
	float wall_mask = smoothstep(0.70, 0.98, edge_dist);
	col = mix(col, color_wall.rgb * (0.65 + 0.5 * n_near), wall_mask * 0.85);

	COLOR = vec4(col, 1.0);
}
