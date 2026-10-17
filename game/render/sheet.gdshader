shader_type canvas_item;
// Picks one cell of a sprite sheet (columns = facing frames, rows = variants) per MultiMesh
// instance: INSTANCE_CUSTOM.r = frame, .g = row, .b = hit flash (0..1, mixes toward warm white).
// shadow = true draws the silhouette only.

uniform int frames = 16;
uniform int rows = 1;
uniform bool shadow = false;
uniform vec4 shadow_color : source_color = vec4(0.184, 0.165, 0.239, 0.45);

varying vec2 cell;
varying float flash;

void vertex() {
	cell = floor(INSTANCE_CUSTOM.rg + 0.5);
	flash = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec4 c = texture(TEXTURE, (UV + cell) / vec2(float(frames), float(rows)));
	if (shadow) {
		COLOR = vec4(shadow_color.rgb, c.a * shadow_color.a);
	} else {
		// the dark 1 px outline stays dark, so a flashing alien keeps its silhouette
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(mix(c.rgb, vec3(1.0, 0.97, 0.9), flash * smoothstep(0.1, 0.22, lum)), c.a);
	}
}
