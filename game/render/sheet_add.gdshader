shader_type canvas_item;
render_mode blend_add;
// Additive glow version of sheet.gdshader (bioluminescence, tracers, muzzle flashes).

uniform int frames = 16;
uniform int rows = 1;
uniform float intensity = 1.0;

varying vec2 cell;

void vertex() {
	cell = floor(INSTANCE_CUSTOM.rg + 0.5);
}

void fragment() {
	vec4 c = texture(TEXTURE, (UV + cell) / vec2(float(frames), float(rows)));
	COLOR = vec4(c.rgb, c.a * intensity);
}
