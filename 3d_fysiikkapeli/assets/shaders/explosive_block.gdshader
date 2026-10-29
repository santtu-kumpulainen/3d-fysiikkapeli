// Räjähtävän palikan materiaali: sykkivä hehku (TIME) ja kohinaan perustuva liukeneminen.
shader_type spatial;

group_uniforms surface;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 base_color : source_color = vec4(1.0, 0.82, 0.75, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

group_uniforms pulse;
uniform vec4 emission_color_a : source_color = vec4(1.0, 0.42, 0.05, 1.0); // oranssi
uniform vec4 emission_color_b : source_color = vec4(0.95, 0.08, 0.02, 1.0); // punainen
uniform vec4 emission_color_c : source_color = vec4(1.0, 0.82, 0.12, 1.0); // keltainen
uniform float pulse_speed : hint_range(0.1, 5.0, 0.05) = 1.2;
uniform float color_cycle_speed : hint_range(0.0, 2.0, 0.05) = 0.35;
uniform float emission_intensity : hint_range(0.0, 4.0, 0.05) = 1.4;
uniform float pulse_amount : hint_range(0.0, 1.0, 0.05) = 0.75;

group_uniforms dissolve;
uniform sampler3D dissolve_noise : filter_linear, repeat_enable, hint_default_white;
uniform float noise_scale : hint_range(0.05, 4.0, 0.05) = 0.5;
uniform float dissolve_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.0, 0.3, 0.005) = 0.07;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float edge_intensity : hint_range(0.0, 10.0, 0.1) = 4.0;

varying vec3 world_pos;

void vertex() {
	// Maailmakoordinaatit pitävät kohinan yhtenäisenä palikan kaikissa mesheissä.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 cycle_color(float t) {
	// Kolmen värin kierto: a -> b -> c -> a.
	float phase = fract(t) * 3.0;
	if (phase < 1.0) {
		return mix(emission_color_a.rgb, emission_color_b.rgb, phase);
	} else if (phase < 2.0) {
		return mix(emission_color_b.rgb, emission_color_c.rgb, phase - 1.0);
	}
	return mix(emission_color_c.rgb, emission_color_a.rgb, phase - 2.0);
}

void fragment() {
	// Liukeneminen: kohina-arvon alittavat pikselit hylätään (myös varjosta).
	float noise = texture(dissolve_noise, world_pos * noise_scale).r;
	if (noise < dissolve_amount) {
		discard;
	}

	vec3 tex = texture(albedo_texture, UV).rgb;
	ALBEDO = tex * base_color.rgb;
	ROUGHNESS = roughness;

	// Sykintä 0..1 sinistä; pulse_amount määrää, kuinka paljon hehku himmenee pohjalla.
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed * TAU);
	float strength = emission_intensity * mix(1.0 - pulse_amount, 1.0, pulse);
	// Tekstuuri moduloi hehkua, jotta laatikon pinta erottuu.
	EMISSION = cycle_color(TIME * color_cycle_speed) * strength * (0.35 + 0.65 * tex);

	// Kapea hehkuva reuna liukenemisrajalla; ei näy ennen kuin liukeneminen alkaa.
	float edge = 1.0 - smoothstep(dissolve_amount, dissolve_amount + edge_width, noise);
	edge *= step(0.001, dissolve_amount);
	EMISSION += edge_color.rgb * edge_intensity * edge;
}
