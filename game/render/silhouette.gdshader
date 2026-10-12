shader_type canvas_item;
// Drop shadow for regular sprites: the sprite's silhouette in the cool shadow colour.

uniform vec4 shadow_color : source_color = vec4(0.184, 0.165, 0.239, 0.45);

void fragment() {
	COLOR = vec4(shadow_color.rgb, texture(TEXTURE, UV).a * shadow_color.a);
}
