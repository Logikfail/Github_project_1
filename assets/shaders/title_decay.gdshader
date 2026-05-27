shader_type canvas_item;

// Title decay — three stacked effects on the title text:
//   1. Chromatic aberration that breathes in and out (sickly-green ↔ rot-purple split).
//   2. An outer halo: multi-tap blur of the letter alpha, tinted with the glow colour,
//      so the title appears to leak plague light into the air around it.
//   3. Drip trails: each letter sheds a thin column of ichor that fades downward,
//      with a faint vertical wobble for organic motion.

uniform float aberration : hint_range(0.0, 8.0) = 2.5;
uniform float halo_radius : hint_range(0.0, 8.0) = 3.0;
uniform float halo_strength : hint_range(0.0, 4.0) = 1.6;
uniform float drip_length : hint_range(0.0, 0.8) = 0.35;
uniform float drip_strength : hint_range(0.0, 2.0) = 0.7;
uniform float wobble_amount : hint_range(0.0, 4.0) = 1.0;
uniform float wobble_speed : hint_range(0.0, 8.0) = 1.5;
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.6;
uniform vec3 tint_low : source_color = vec3(0.55, 0.95, 0.35);
uniform vec3 tint_high : source_color = vec3(0.85, 0.55, 1.0);
uniform vec3 halo_color : source_color = vec3(0.35, 0.85, 0.20);
uniform vec3 drip_color : source_color = vec3(0.25, 0.65, 0.15);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);

	// === Wobble — subtle per-row horizontal offset on the main sample. ===
	float wob = sin(UV.y * 30.0 + TIME * wobble_speed) * wobble_amount;

	// === Chromatic aberration on the letter alpha. ===
	float ab = aberration * (0.6 + 0.6 * pulse);
	vec2 off = vec2((ab + wob) * px.x, 0.0);
	float r = texture(TEXTURE, UV - off).a;
	float g = texture(TEXTURE, UV).a;
	float b = texture(TEXTURE, UV + off).a;
	float letter_a = max(r, max(g, b));
	vec3 tint = mix(tint_low, tint_high, pulse);
	vec3 letter_rgb = vec3(r * tint.r, g * tint.g, b * tint.b);

	// === Halo — 8-tap ring blur of the alpha, tinted to bleed light outward. ===
	float halo = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853981;  // π/4
		vec2 dir = vec2(cos(a), sin(a)) * halo_radius;
		halo += texture(TEXTURE, UV + dir * px).a;
	}
	halo *= 0.125;
	// Subtract the letter itself so the halo only shows outside the glyphs.
	halo = max(halo - letter_a, 0.0);
	float halo_pulse = 0.7 + 0.5 * pulse;
	vec3 halo_rgb = halo_color * halo * halo_strength * halo_pulse;
	float halo_alpha = halo * halo_strength * halo_pulse;

	// === Drip trails — sample alpha at progressively higher UV.y; if a letter
	//     is overhead, the current pixel inherits some of its alpha, fading off
	//     with vertical distance.
	float drip = 0.0;
	for (int i = 1; i < 6; i++) {
		float dy = float(i) * (drip_length / 6.0);
		float jitter = sin(UV.x * 80.0 + TIME * 2.0 + float(i)) * 0.6 * px.x;
		float sample_a = texture(TEXTURE, vec2(UV.x + jitter, UV.y - dy)).a;
		float falloff = 1.0 - float(i) / 6.0;
		// Per-column drip mask — only ~25% of columns drip, so it's a sparse trail.
		float column_gate = step(0.75, hash(vec2(floor(UV.x * 60.0), 0.0)));
		drip = max(drip, sample_a * falloff * column_gate);
	}
	// Drip only appears below the letter, not behind it.
	drip = max(drip - letter_a, 0.0) * drip_strength;
	vec3 drip_rgb = drip_color * drip;

	// === Composite — letter on top, then halo, then drips behind. ===
	vec3 rgb = letter_rgb + halo_rgb + drip_rgb;
	float a = max(letter_a, max(halo_alpha, drip));

	COLOR = vec4(rgb, a);
}
