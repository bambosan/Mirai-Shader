// __multiversion__
#include "fragmentVersionCentroid.h"
#include "uniformShaderConstants.h"
#include "uniformPerFrameConstants.h"

#if __VERSION__ >= 300
	#ifndef BYPASS_PIXEL_SHADER
		_centroid in highp vec2 uv0;
		_centroid in highp vec2 uv1;
	#endif
#else
	#ifndef BYPASS_PIXEL_SHADER
		varying highp vec2 uv0;
		varying vec2 uv1;
	#endif
#endif

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;
LAYOUT_BINDING(1) uniform sampler2D TEXTURE_1;
LAYOUT_BINDING(2) uniform sampler2D TEXTURE_2;

precision highp float;

varying vec4 vcolor;
varying vec3 sunc;
varying vec3 moonc;
varying vec3 zcol;
varying vec3 cpos;
varying vec3 wpos;
varying vec3 lpos;
varying vec3 tlpos;
varying float sunv;

#include "common.glsl"

// https://github.com/origin0110/OriginShader
bool equ3(vec3 v) {
	return abs(v.x-v.y) < 0.000002 && abs(v.y-v.z) < 0.000002;
}
float getleaao(vec3 color){
	const vec3 O = vec3(0.682352941176471, 0.643137254901961, 0.164705882352941);
	const vec3 n = vec3(0.195996912842436, 0.978673548072766, -0.061508507207520);
	return length(color) / dot(O, n) * dot(normalize(color), n);
}
float getgraao(vec3 color){
	const vec3 O = vec3(0.745098039215686, 0.713725490196078, 0.329411764705882);
	const vec3 n = vec3(0.161675377098328, 0.970052262589970, 0.181272392504186);
	return length(color) / dot(O, n) * dot(normalize(color), n);
}
vec3 calcVco(vec4 color){
	if(equ3(color.rgb)) color.rgb = vec3(1.0); else {
		color.a = color.a < 0.001 ? getleaao(color.rgb) : getgraao(color.rgb);
		color.rgb = color.rgb / color.a;
	}
	return color.rgb;
}
bool isunderwater(vec3 n, vec2 uv1, float ndl) {
	return uv1.y < 0.9 && abs((2.0 * cpos.y - 15.0) / 16.0 - uv1.y) < 0.00002 && !equ3(textureLod(TEXTURE_0, uv0, 3.0).rgb)	&& (equ3(vcolor.rgb) || vcolor.a < 0.00001)	 && abs(fract(cpos.y) - 0.5) > 0.00001;
}
///////////////////


#if defined(ENABLE_WATERBUMP) || defined(ENABLE_FAKE_CLOUD_REFLECTION) || defined(ENABLE_UNDERWATER_CAUSTIC)
float hash(float n){ return fract(sin(n) * 43758.5453); }
float noise(vec2 pos){
	vec2 ip = floor(pos), fp = csmooth(fract(pos));
	float n = ip.x + ip.y * 57.0;
	return mix(mix(hash(n), hash(n + 1.0), fp.x), mix(hash(n + 57.0), hash(n + 58.0), fp.x), fp.y);
}
#endif

#if defined(ENABLE_WATERBUMP) || defined(ENABLE_UNDERWATER_CAUSTIC)
float cwav(vec2 pos){
    pos.x += TOTAL_REAL_WORLD_TIME;
	return noise(pos * rotate2d(0.3) * vec2(1.5, 0.5) + vec2(0, TOTAL_REAL_WORLD_TIME)) + noise(pos * rotate2d(-0.3) * vec2(1.7, 0.7) - vec2(0, TOTAL_REAL_WORLD_TIME * 1.1));
}
vec3 cnw(vec3 n){
vec2 wps = cpos.xz * 1.5;
	float w1 = cwav(wps), w2 = cwav(vec2(wps.x - 0.02, wps.y)), w3 = cwav(vec2(wps.x, wps.y - 0.02));
	vec3 wn = normalize(vec3(w1 - w2, w1 - w3, 1.0)) * 0.5 + 0.5;
	mat3 ftbn = mat3(abs(n.y) + n.z, 0.0, n.x, 0.0, 0.0, n.y, -n.x, n.y, n.z);
	return normalize((wn * 2.0 - 1.0) * ftbn);
}
#endif

#ifdef ENABLE_SPECULAR_REFLECTION
float ggx(vec3 n, float ndl, float ndv, float ndh, float roughness){
	float rs = pow(roughness, 4.0);
	float d = (ndh * rs - ndh) * ndh + 1.0;
	float nd = rs / (pi * d * d);
	float k = (roughness * roughness) * 0.5;
	float v = ndv * (1.0 - k) + k, l = ndl * (1.0 - k) + k;
	return max0(nd * (0.25 / (v * l)));
}
#endif

#ifdef ENABLE_FAKE_CLOUD_REFLECTION
vec4 ccc(vec3 vwpos, vec3 lpos, vec3 sunc, vec3 monc){
	float tot = 0.0, den = saturate(1.0 - wrain);
	vec2 movp = vwpos.xz / vwpos.y * 3.0;
		movp += TOTAL_REAL_WORLD_TIME * 0.001;
	for(int i = 0; i < 3; i++){
		tot += noise(movp) * den;
		den *= 0.5;
		movp *= 3.0;
		movp += TOTAL_REAL_WORLD_TIME * 0.01;
	}
		tot = 1.0 - pow(0.1, max0(1.0 - tot));
	float phase = cphase2(dot(vwpos, lpos));
	float cpowd = 1.0 - exp(-tot * 2.0);
	return mix(vec4((sunc * tau + monc) * cpowd * phase, exp(-tot)), vec4(0.0,0.0,0.0,1.0), smoothstep(0.5, 0.0, vwpos.y));
}
#endif

float fsc(float ndv, float f0){ return f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0); }

vec4 refl(vec4 albedo, vec3 n, float ndv){
	vec3 rv = reflect(normalize(wpos), n);
	vec3 sr = albedo.rgb;
	#ifdef ENABLE_SKY_REFLECTION
		sr = csky(rv, lpos);
	#endif
	#ifdef ENABLE_FAKE_CLOUD_REFLECTION
		vec4 cr = ccc(rv, tlpos, sunc, moonc);
		sr = sr * cr.a + cr.rgb;
	#endif
	#if defined(ENABLE_SKY_REFLECTION) || defined(ENABLE_FAKE_CLOUD_REFLECTION)
		float fresnel = fsc(ndv, REFLECTION_ROUGHNESS);
		albedo = mix(albedo, vec4(sr, 1.0), fresnel);
	#else
		albedo = vec4(sr, albedo.a);
	#endif
	return albedo;
}

void main(){
#ifdef BYPASS_PIXEL_SHADER
	gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
	return;
#else
	vec4 albedo = texture(TEXTURE_0, uv0);
	#ifdef SEASONS_FAR
		albedo.a = 1.0;
	#endif
	#ifdef ALPHA_TEST
		#ifdef ALPHA_TO_COVERAGE
			if(albedo.a < 0.05) discard;
		#else
			if(albedo.a < 0.5) discard;
		#endif
	#endif
	#ifndef SEASONS
		#if !defined(ALPHA_TEST) && !defined(BLEND)
			albedo.a = vcolor.a;
		#endif
		albedo.rgb *= calcVco(vcolor);
	#else
		albedo.rgb *= mix(vec3(1.0), texture2D(TEXTURE_2, vcolor.rg).rgb * 2.0, vcolor.b);
		albedo.rgb *= vcolor.aaa;
		albedo.a = 1.0;
	#endif
		albedo.rgb = tolin(albedo.rgb);

	float bls = uv1.x * max(smoothstep(sunv * uv1.y, 1.0, uv1.x), wrain * uv1.y), outd = smoothstep(0.845, 0.87, uv1.y);
	vec3 ambc = mix(vec3(length(zcol)), zcol, SHADOW_SATURATION) * SHADOW_BRIGHTNESS * uv1.y + vec3(BLOCK_LIGHT_C_R, BLOCK_LIGHT_C_G, BLOCK_LIGHT_C_B) * bls * (20.0 + pow(bls, 5.0) * 200.0);

	bool iswater = false;
	vec3 n = normalize(cross(dFdx(cpos.xyz), dFdy(cpos.xyz)));
	#if !defined(SEASONS) && !defined(ALPHA_TEST)
		if(vcolor.a > 0.54 && vcolor.a < 0.67){
			#ifdef ENABLE_WATERBUMP
				n = cnw(n);
			#endif
			iswater = true;
		}
	#endif

	float ndl = max0(dot(n, tlpos));
		ambc += (sunc + moonc) * ndl * outd * (1.0 - wrain);
		albedo.rgb = (albedo.rgb * ambc);

	if(isunderwater(n, uv1, ndl)){
		float abso = exp2(-(1.0 - uv1.y) * dens);
		albedo.rgb *= mix(vec3(ABSORBTION_C_R, ABSORBTION_C_G, ABSORBTION_C_B), vec3(1), abso);
		#ifdef ENABLE_UNDERWATER_CAUSTIC
			albedo.rgb += pow(cwav(cpos.xz * 2.0), CAUSTIC_ATTENUATION) * sunc * CAUSTIC_BRIGHTNESS * uv1.y * albedo.rgb;
		#endif
	}

	float fdist = max0(length(wpos) / FOG_DISTANCE);
		albedo.rgb = mix(albedo.rgb, zcol * hpi, fdist * mix(mix(SS_FOG_INTENSITY, NOON_FOG_INTENSITY, sunv), RAIN_FOG_INTENSITY, wrain));
		albedo.rgb += sunc * pi * mphase(max0(dot(normalize(wpos), lpos)), FOG_MIE_G) * fdist * FOG_MIE_COEFF;

	if(iswater){
		albedo.a *= 0.5;
		vec3 vdir = normalize(-wpos), hdir = normalize(vdir + tlpos);
		float ndv = max(0.001, dot(n, vdir)), ndh = max(0.001, dot(n, hdir));

		#if defined(ENABLE_SKY_REFLECTION) || defined(ENABLE_FAKE_CLOUD_REFLECTION)
			albedo = vec4(0);
			albedo = refl(albedo, n, ndv);
		#endif
		#ifdef ENABLE_SPECULAR_REFLECTION
			float sggx = ggx(n, ndl, ndv, ndh, SPECULAR_ROUGHNESS);
			albedo += vec4(sunc + moonc, 1.0) * sggx;
		#endif
	}

		albedo.rgb = colcor(albedo.rgb);
	gl_FragColor = albedo;
#endif
}
