shader_type canvas_item;
// Rig layers (tools/artgen/rig.py): paint-keyed pixels (r = 1, g = 0, b = 8 + 16 * step) take the
// owner's paint from paint_ramps.png (row = SimVehicle.color_index, column = step). Every other
// pixel passes through, so one strip serves all eight paint jobs.

uniform sampler2D ramps : filter_nearest;
uniform int paint_row = 0;
// Protection shimmer (playtest round 1 #11): > 0 lifts the whole rig toward warm white.
uniform float flash = 0.0;

// fragment COLOR already holds texture x modulate, so keep the plain modulate from vertex().
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.r > 0.99 && c.g < 0.01 && c.a > 0.5) {
		int k = clamp(int(floor((c.b * 255.0 - 8.0) / 16.0 + 0.5)), 0, 4);
		c.rgb = texelFetch(ramps, ivec2(k, paint_row), 0).rgb;
	}
	c.rgb = mix(c.rgb, vec3(1.0, 0.94, 0.78), flash);
	COLOR = c * tint;
}
