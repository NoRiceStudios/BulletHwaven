shader_type canvas_item;
// Rig guns (playtest: "the weapons on my rig are hard to see"): a 1px light rim around the gun's own dark
// outline lifts it off the hull, and the gunmetal is brightened a little. The rim is brighter on the
// top-left (the light side). `heat` 0..1 turns the rim hot for the ticks after a shot.

uniform vec4 rim_color : source_color = vec4(0.941, 0.851, 0.69, 0.9);  // SAND[5]
uniform vec4 hot_color : source_color = vec4(1.0, 0.894, 0.541, 1.0);  // FIRE[5]
uniform float lift = 0.3;
uniform float heat = 0.0;
// The protection shimmer of the rig (paint.gdshader's flash), so the guns shimmer with the hull.
uniform float flash = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	if (c.a < 0.5) {
		float lit = max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
		float any = max(lit, max(texture(TEXTURE, UV - vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
		if (any > 0.5) {
			// a rim pixel left of / above the gun faces the light
			vec4 rim = mix(rim_color, hot_color, heat);
			float a = rim.a * (lit > 0.5 ? 1.0 : 0.6);
			c = vec4(rim.rgb, a);
		}
	} else {
		float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		if (luma > 0.12) {  // keep the dark outline dark
			c.rgb = min(c.rgb * (1.0 + lift), vec3(1.0));
		}
		c.rgb = mix(c.rgb, vec3(1.0, 0.94, 0.78), flash);
	}
	COLOR = c * tint;
}
