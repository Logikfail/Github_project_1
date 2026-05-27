shader_type canvas_item;

// Plague miasma — layered atmospheric composition:
//   1. Warped radial glow: a sickly green plague-heart pulses at the centre,
//      ringed by necrotic purple and fading to a black void.
//   2. Concentric pulse rings emanate outward like a slow heartbeat.
//   3. Vertical wisps of haze rise from below, stretched and drifting upward.
//   4. Floating embers / spores drift up through the haze in three depth layers.
//   5. Heavy vignette + film grain to keep edges atmospheric.

uniform vec3 color_void : source_color = vec3(0.015, 0.005, 0.03);
uniform vec3 color_mid : source_color = vec3(0.22, 0.06, 0.28);
uniform vec3 color_glow : source_color = vec3(0.45, 0.95, 0.30);
uniform vec3 color_ember : source_color = vec3(0.85, 1.0, 0.55);

uniform float glow_radius : hint_range(0.1, 1.5) = 0.55;
uniform float glow_softness : hint_range(0.05, 1.5) = 0.75;
uniform float warp_strength : hint_range(0.0, 0.5) = 0.16;
uniform float drift_speed : hint_range(0.0, 0.5) = 0.04;

uniform float pulse_speed : hint_range(0.0, 8.0) = 1.6;
uniform float pulse_strength : hint_range(0.0, 0.5) = 0.10;
uniform float pulse_frequency : hint_range(1.0, 30.0) = 11.0;

uniform float wisp_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wisp_speed : hint_range(0.0, 1.0) = 0.18;

uniform float ember_density : hint_range(0.90, 1.0) = 0.965;
uniform float ember_brightness : hint_range(0.0, 4.0) = 1.4;
uniform float ember_speed : hint_range(0.0, 1.0) = 0.22;

uniform float vignette_strength : hint_range(0.0, 2.5) = 1.5;
uniform float grain_amount : hint_range(0.0, 0.1) = 0.018;


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// One layer of upward-drifting embers; sparse glowing dots at random positions in a grid.
float ember_layer(vec2 uv, float scale, float speed, float t) {
	vec2 cell_uv = uv * scale;
	cell_uv.y += t * speed;
	vec2 cell = floor(cell_uv);
	vec2 f = fract(cell_uv);

	// Per-cell random gate — most cells are empty, a few hold an ember.
	float gate = step(ember_density, hash(cell));

	// Random sub-cell position so embers don't sit on a grid.
	vec2 pos = vec2(hash(cell + 17.0), hash(cell + 31.0));
	float d = distance(f, pos);

	// Random brightness + slow twinkle so each ember has its own pulse.
	float twinkle = 0.5 + 0.5 * sin(t * 2.5 + hash(cell) * 12.0);
	float dot_val = smoothstep(0.06, 0.0, d) * twinkle;

	return dot_val * gate;
}


void fragment() {
	// Aspect-correct UV so radial features stay round on any window shape.
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = (1.0 / px.x) / (1.0 / px.y);
	vec2 uv = UV - 0.5;
	uv.x *= aspect;

	float t = TIME;
	float td = t * drift_speed;

	// === Radial warp field — large slow noise nudges the radial coordinate. ===
	float n1 = fbm(uv * 1.5 + vec2(td, -td * 0.7));
	float n2 = fbm(uv * 3.2 + vec2(-td * 0.5, td * 0.3));
	float warp = (n1 - 0.5) * 0.7 + (n2 - 0.5) * 0.3;
	float r = length(uv) + warp * warp_strength;

	// === Heartbeat pulse — concentric rings emanate outward periodically. ===
	float beat = 0.5 + 0.5 * sin(t * pulse_speed);
	beat = pow(beat, 3.0);
	float ring = sin(r * pulse_frequency - t * pulse_speed * 2.0);
	ring *= smoothstep(glow_radius * 1.4, glow_radius * 0.2, r);
	r -= ring * pulse_strength * beat;

	// === Three-stop radial palette: glow core → necrotic ring → void. ===
	float core = 1.0 - smoothstep(0.0, glow_radius * 0.55, r);
	float mid = 1.0 - smoothstep(glow_radius * 0.4, glow_radius * 0.95, r);
	float edge = 1.0 - smoothstep(glow_radius * 0.85, glow_radius + glow_softness, r);

	vec3 col = color_void;
	col = mix(col, color_mid, edge);
	col = mix(col, color_glow * 0.9, mid * 0.85);
	col = mix(col, color_glow, core);

	// Hot core boost: when the heartbeat peaks, the centre flares brighter.
	col += color_glow * core * core * beat * 0.4;

	// === Rising wisps — vertical-stretched noise drifting upward. ===
	vec2 wuv = vec2(uv.x * 1.8, uv.y * 0.7 + t * wisp_speed);
	float wisps = fbm(wuv * 2.0);
	wisps = smoothstep(0.45, 0.85, wisps);
	// Wisps are denser at the bottom of the screen, fading out near the top.
	float wisp_mask = smoothstep(0.6, -0.2, UV.y);
	col += color_glow * wisps * wisp_mask * wisp_strength * 0.5;
	col += color_mid * wisps * wisp_mask * wisp_strength * 0.3;

	// === Floating embers — three depth layers at different scales / speeds. ===
	float embers = 0.0;
	embers += ember_layer(uv, 14.0, ember_speed, t) * 1.0;
	embers += ember_layer(uv + vec2(0.13, 0.0), 22.0, ember_speed * 1.4, t) * 0.7;
	embers += ember_layer(uv + vec2(-0.07, 0.0), 34.0, ember_speed * 1.9, t) * 0.45;
	col += color_ember * embers * ember_brightness;

	// === Vignette darkens the corners to focus the eye on the centre. ===
	float vig = 1.0 - dot(uv, uv) * vignette_strength;
	col *= clamp(vig, 0.0, 1.0);

	// === Subtle film grain breaks up smooth gradients. ===
	float grain = (hash(UV * 1024.0 + t) - 0.5) * grain_amount;
	col += grain;

	COLOR = vec4(col, 1.0);
}
