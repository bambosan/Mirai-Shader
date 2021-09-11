// __multiversion__
#include "fragmentVersionSimple.h"
#include "uniformPerFrameConstants.h"

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;

#define vcloudh 1000.0
#define vcloudthick 1200.0
#define vcloudsteps 20
#define vcloudlsteps 5

precision highp float;
#include "common.glsl"
varying vec3 cPos;

float noise3d(vec3 pos){
	vec3 f = csmooth(fract(pos));
	pos = floor(pos);
	vec2 uv =  (pos.xy + pos.z * vec2(17.0, 37.0)) + f.xy;
	vec2 uv2 = (pos.xy + (pos.z + 1.0) * vec2(17.0, 37.0)) + f.xy;
	return mix(texture2D(TEXTURE_0, (uv + 0.5) * 0.00390625).r, texture2D(TEXTURE_0, (uv2 + 0.5) * 0.00390625).r, f.z);
}

float sint(float yalt, float h){
	float r = 6371e3 + h, ds = yalt * 6371e3;
	return -ds + sqrt((ds * ds) + (r * r) - 4.058964e13);
}

const float cminh = vcloudh;
const float cmaxh = vcloudh + vcloudthick;

// https://github.com/robobo1221/robobo1221Shaders
float ccdens(vec3 pos){
	if(pos.y < cminh || pos.y > cmaxh) return 0.0;
	float tot = 0.0, den = saturate(1.0 - wrain);
	vec3 movpos = pos * 0.001;
	for(int i = 0; i < 5; i++){
		tot += noise3d(movpos) * den;
		den *= 0.5;
		movpos *= 3.0;
		movpos.xz += TOTAL_REAL_WORLD_TIME * 0.01;
	}
	float heightf = (pos.y - cminh) / vcloudthick;
	float heighta = saturate(remap(heightf, 0.0, 0.4, 0.0, 1.0) * remap(heightf, 0.6, 1.0, 1.0, 0.0));
	float locov = texture2D(TEXTURE_0, pos.xz * 1e-5 + TOTAL_REAL_WORLD_TIME * 1e-4).b;
		locov = saturate(locov * 3.0 - 0.75) * 0.5 + 0.5;
	return saturate(tot * heighta * locov - (heighta * 0.5 + heightf * 0.5 + 0.31)) * 0.03;
}

void ccloudscatter(inout vec2 clisha, vec3 rpos, vec3 lpos, float cdens, float cost, float transmitt){
	float stepsp = vcloudthick / float(vcloudlsteps), codl = 0.0, powder = 1.0 - exp(-cdens * hpi);
	for(int i = 0; i < vcloudlsteps; i++, rpos += lpos * stepsp) codl += ccdens(rpos) * stepsp;
	clisha.x += powder * exp(-codl) * cphase(cost) * transmitt;
	clisha.y += powder * transmitt;
}

vec4 ccloudvolume(vec3 vwpos, vec3 lpos, vec3 sunc, vec3 monc, vec3 skyzc, float dither){
	vec3 startp = vwpos * sint(vwpos.y, cminh), endp = vwpos * sint(vwpos.y, cmaxh);
	vec3 direction = (endp - startp) / float(vcloudsteps);
		startp = startp + direction * dither;
	vec2 clisha = vec2(0.0);
	float cost = dot(vwpos, lpos), transmitt = 1.0;

	for(int i = 0; i < vcloudsteps; i++, startp += direction){
		float cloudDens = ccdens(startp) * length(direction);
		if(cloudDens <= 0.0) continue;
		ccloudscatter(clisha, startp, lpos, cloudDens, cost, transmitt);
		transmitt *= exp(-cloudDens);
	}

	vec3 clig = (sunc + monc) * clisha.x;
	vec3 csha = skyzc * clisha.y * invpi;
	return mix(vec4(clig + csha, transmitt), vec4(0, 0, 0, 1), saturate(length(startp) * 3e-5));
}

vec4 ccloudplane(vec3 vwpos, vec3 lpos, vec3 sunc, vec3 monc){
	float tot = 0.0, den = saturate(1.0 - wrain);
	vec2 movpos = vwpos.xz / vwpos.y;
		movpos *= 2.0;
		movpos.x += TOTAL_REAL_WORLD_TIME * 0.001;
	for(int i = 0; i < 4; i++){
		tot += texture2D(TEXTURE_0, movpos * 0.00390625).r * den;
		den *= 0.55;
		movpos *= 2.0;
		movpos.y += movpos.y * (0.8 + tot * 0.2);
		movpos.x += TOTAL_REAL_WORLD_TIME * 0.01;
	}
		tot = 1.0 - pow(0.9, max0(1.0 - tot));
	float phase = cphase2(dot(vwpos, lpos)), cpowder = 1.0 - exp(-tot * 2.0);
	return mix(vec4((sunc + monc) * cpowder * phase, exp(-tot)), vec4(0, 0, 0, 1), saturate(vwpos.y * 0.5));
}

void main(){
	vec3 ajpos = normalize(vec3(cPos.x, -cPos.y + 0.128, -cPos.z));
	vec3 spos = vec3(0.0), tlpos = vec3(0.0), sunc = vec3(0.0), monc = vec3(0.0), skyzc = vec3(0.0);
	calcLpos(tlpos, spos);
	atml(spos, sunc, monc, skyzc);

	float dbnoise = texelFetch(TEXTURE_0, ivec2(gl_FragCoord.xy % 256.0), 0).g;
	vec4 vcloud = ccloudvolume(ajpos, tlpos, sunc, monc, skyzc, dbnoise);
	vec4 pcloud = ccloudplane(ajpos, tlpos, sunc, monc);

	vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
		color.rgb = csky(ajpos, spos);
		color.rgb = color.rgb * pcloud.a + pcloud.rgb;
		color.rgb = color.rgb * vcloud.a + vcloud.rgb;
		color.rgb = colorCorrection(color.rgb);
	gl_FragColor = color;
}
