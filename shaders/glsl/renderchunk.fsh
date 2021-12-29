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
// https://github.com/origin0110/OriginShader/blob/main/shaders/glsl/shaderfunction.lin
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
	if(abs(color.x - color.y) < 2e-5 && abs(color.y - color.z) < 2e-5) color.rgb = vec3(1.0); else {
		color.a = color.a < 0.001 ? getleaao(color.rgb) : getgraao(color.rgb);
		color.rgb = color.rgb / color.a;
	}
	return color.rgb;
}

#ifdef ENABLE_WATER_REFLECTION
float hash(float n){ return fract(sin(n) * 43758.5453); }
float noise(vec2 pos){
	vec2 ip = floor(pos), fp = csmooth(fract(pos));
	float n = ip.x + ip.y * 57.0;
	return mix(mix(hash(n), hash(n + 1.0), fp.x), mix(hash(n + 57.0), hash(n + 58.0), fp.x), fp.y);
}
float cwav(vec2 pos){
	return noise(pos * 1.2 + TOTAL_REAL_WORLD_TIME) + noise(pos * 1.6 - TOTAL_REAL_WORLD_TIME * 1.2);
}

vec3 cnw(vec3 n){
	float w1 = cwav(cpos.xz), w2 = cwav(vec2(cpos.x - 0.02, cpos.z)), w3 = cwav(vec2(cpos.x, cpos.z - 0.02));
	vec3 wn = normalize(vec3(w1 - w2, w1 - w3, 1.0)) * 0.5 + 0.5;
	mat3 ftbn = mat3(abs(n.y) + n.z, 0.0, n.x, 0.0, 0.0, n.y, -n.x, n.y, n.z);
	return normalize((wn * 2.0 - 1.0) * ftbn);
}

float ggx(vec3 n, float ndl, float ndv, float ndh, float roughness){
	float rs = pow(roughness, 4.0);
	float d = (ndh * rs - ndh) * ndh + 1.0;
	float nd = rs / (pi * d * d);
	float k = (roughness * roughness) * 0.5;
	float v = ndv * (1.0 - k) + k, l = ndl * (1.0 - k) + k;
	return max0(nd * (0.25 / (v * l)));
}

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

float fsc(float ndv, float f0){ return f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0); }

vec4 refl(vec4 albedo, vec3 n, float ndv){
	vec3 rv = reflect(normalize(wpos), n);
	vec3 sr = csky(rv, lpos);
	vec4 cr = ccc(rv, tlpos, sunc, moonc);
		sr = sr * cr.a + cr.rgb;
		albedo = mix(albedo, vec4(sr, 1.0), fsc(ndv, 0.2));
	return albedo;
}
#endif

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
	vec3 ambc = zcol * hpi * uv1.y + vec3(BLOCK_LIGHT_C_R, BLOCK_LIGHT_C_G, BLOCK_LIGHT_C_B) * bls * (20.0 + pow(bls, 5.0) * 200.0);

	vec3 n = normalize(cross(dFdx(cpos.xyz), dFdy(cpos.xyz)));
	float ndl = max0(dot(n, tlpos));
		ambc += (sunc + moonc) * ndl * outd * (1.0 - wrain);
		albedo.rgb = (albedo.rgb * ambc);

	#if !defined(SEASONS) && !defined(ALPHA_TEST)
		if(vcolor.a > 0.54 && vcolor.a < 0.67){
			albedo.a *= 0.7;
			#ifdef ENABLE_WATER_REFLECTION
albedo = vec4(0);
				n = cnw(n);
				vec3 vdir = normalize(-wpos), hdir = normalize(vdir + tlpos);
				float ndv = max(0.001, dot(n, vdir)), ndh = max(0.001, dot(n, hdir));
				float sggx = ggx(n, ndl, ndv, ndh, 0.04);
				albedo = refl(albedo, n, ndv);
				albedo += vec4(sunc, 1.0) * sggx;
			#endif
		}
	#endif

	float fdist = max0(length(wpos) / FOG_DISTANCE);
		albedo.rgb = mix(albedo.rgb, zcol * hpi, fdist * mix(mix(SS_FOG_INTENSITY, NOON_FOG_INTENSITY, sunv), RAIN_FOG_INTENSITY, wrain));
		albedo.rgb += sunc * pi * mphase(max0(dot(normalize(wpos), lpos)), FOG_MIE_G) * fdist * FOG_MIE_COEFF;
		albedo.rgb = colcor(albedo.rgb);

	gl_FragColor = albedo;
#endif
}
