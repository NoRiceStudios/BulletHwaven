shader_type canvas_item;
// Picks one cell of a sprite sheet (columns = facing frames, rows = variants) per MultiMesh
// instance: INSTANCE_CUSTOM.r = frame, .g = row. shadow = true draws the silhouette only.

uniform int frames = 16;
uniform int rows = 1;
uniform bool shadow = false;
uniform vec4 shadow_color : source_color = vec4(0.184, 0.165, 0.239, 0.45);

varying vec2 cell;

void vertex() {
	cell = floor(INSTANCE_CUSTOM.rg + 0.5);
}

void fragment() {
	vec4 c = texture(TEXTURE, (UV + cell) / vec2(float(frames), float(rows)));
	COLOR = shadow ? vec4(shadow_color.rgb, c.a * shadow_color.a) : c;
}
