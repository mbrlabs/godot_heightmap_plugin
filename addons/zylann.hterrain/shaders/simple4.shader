shader_type spatial;

uniform sampler2D height_texture;
uniform sampler2D normal_texture;
uniform sampler2D color_texture : hint_albedo;
uniform sampler2D splat_texture;
uniform vec2 heightmap_resolution;
uniform mat4 heightmap_inverse_transform;

uniform sampler2D detail_albedo_roughness_0 : hint_albedo;
uniform sampler2D detail_albedo_roughness_1 : hint_albedo;
uniform sampler2D detail_albedo_roughness_2 : hint_albedo;
uniform sampler2D detail_albedo_roughness_3 : hint_albedo;

uniform sampler2D detail_normal_bump_0;
uniform sampler2D detail_normal_bump_1;
uniform sampler2D detail_normal_bump_2;
uniform sampler2D detail_normal_bump_3;

uniform float detail_scale = 20.0;
uniform bool depth_blending = true;


vec3 unpack_normal(vec3 rgb) {
	return rgb * 2.0 - vec3(1.0);
}

void vertex() {
	vec4 tv = heightmap_inverse_transform * WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 uv = vec2(tv.x, tv.z) / heightmap_resolution;
	float h = texture(height_texture, uv).r;
	VERTEX.y = h;
	UV = uv;
	NORMAL = unpack_normal(texture(normal_texture, UV).xyz);
}

void fragment() {

	vec4 tint = texture(color_texture, UV);
	if(tint.a < 0.5)
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	
	vec4 splat = texture(splat_texture, UV);

	// TODO Detail should only be rasterized on nearby chunks (needs proximity management to switch shaders)
	
	vec2 detail_uv = UV * detail_scale;
	vec4 ar0 = texture(detail_albedo_roughness_0, detail_uv);
	vec4 ar1 = texture(detail_albedo_roughness_1, detail_uv);
	vec4 ar2 = texture(detail_albedo_roughness_2, detail_uv);
	vec4 ar3 = texture(detail_albedo_roughness_3, detail_uv);
	
	// TODO Should use local XZ
	vec3 col0 = ar0.rgb;
	vec3 col1 = ar1.rgb;
	vec3 col2 = ar2.rgb;
	vec3 col3 = ar3.rgb;
	
	float roughness0 = ar0.a;
	float roughness1 = ar1.a;
	float roughness2 = ar2.a;
	float roughness3 = ar3.a;
	
	vec4 nb0 = texture(detail_normal_bump_0, detail_uv);
	vec4 nb1 = texture(detail_normal_bump_1, detail_uv);
	vec4 nb2 = texture(detail_normal_bump_2, detail_uv);
	vec4 nb3 = texture(detail_normal_bump_3, detail_uv);
	
	vec3 normal0 = unpack_normal(nb0.xzy);
	vec3 normal1 = unpack_normal(nb1.xzy);
	vec3 normal2 = unpack_normal(nb2.xzy);
	vec3 normal3 = unpack_normal(nb3.xzy);
	
	vec3 detail_normal;
	
	// TODO An #ifdef macro would be nice! Or move in a different shader, heh
	if (depth_blending) {
		
		float dh = 0.2;

		// TODO Keep improving multilayer blending, there are still some edge cases...
		// Mitigation workaround is used for now.
		// Maybe should be using actual bumpmaps to be sure
				
		//splat *= 1.4; // Mitigation #1: increase splat range over bump
		vec4 h = vec4(nb0.a, nb1.a, nb2.a, nb3.a) + splat;
		
		// Mitigation #2: nullify layers with near-zero splat
		h *= smoothstep(0, 0.05, splat);
		
		vec4 d = h + dh;
		d.r -= max(h.g, max(h.b, h.a));
		d.g -= max(h.r, max(h.b, h.a));
		d.b -= max(h.g, max(h.r, h.a));
		d.a -= max(h.g, max(h.b, h.r));
		
		vec4 w = clamp(d, 0, 1);
		
		float w_sum = (w.r + w.g + w.b + w.a);
		
    	ALBEDO = tint.rgb * (w.r * col0.rgb + w.g * col1.rgb + w.b * col2.rgb + w.a * col3.rgb) / w_sum;
		ROUGHNESS = (w.r * roughness0 + w.g * roughness1 + w.b * roughness2 + w.a * roughness3) / w_sum;
		detail_normal = (w.r * normal0 + w.g * normal1 + w.b * normal2 + w.a * normal3) / w_sum;
		
	} else {
		
		float w0 = splat.r;
		float w1 = splat.g;
		float w2 = splat.b;
		float w3 = splat.a;

		float w_sum = (w0 + w1 + w2 + w3);
		
    	ALBEDO = tint.rgb * (w0 * col0.rgb + w1 * col1.rgb + w2 * col2.rgb + w3 * col3.rgb) / w_sum;
		ROUGHNESS = (w0 * roughness0 + w1 * roughness1 + w2 * roughness2 + w3 * roughness3) / w_sum;
		detail_normal = (w0 * normal0 + w1 * normal1 + w2 * normal2 + w3 * normal3) / w_sum;
	}
	
	// Combine terrain normals with detail normals (not sure if correct but looks ok)
	vec3 terrain_normal = unpack_normal(texture(normal_texture, UV).rgb);
	vec3 normal = normalize(vec3(terrain_normal.x + detail_normal.x, terrain_normal.y, terrain_normal.z + detail_normal.z));
	NORMAL = (INV_CAMERA_MATRIX * (WORLD_MATRIX * vec4(normal, 0.0))).xyz;

	//ALBEDO = splat.rgb;
}

