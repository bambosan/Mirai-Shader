// __multiversion__
#include "vertexVersionCentroid.h"
#if __VERSION__ >= 300
	#ifndef BYPASS_PIXEL_SHADER
		_centroid out vec2 uv0;
		_centroid out vec2 uv1;
	#endif
#else
	#ifndef BYPASS_PIXEL_SHADER
		varying vec2 uv0;
		varying vec2 uv1;
	#endif
#endif
#ifndef BYPASS_PIXEL_SHADER
	varying vec4 vcolor;
	varying vec3 sunCol;
	varying vec3 moonCol;
	varying vec3 szCol;
	varying POS3 cPos;
	varying POS3 wPos;
	varying POS3 nWPos;
	varying POS3 lPos;
	varying POS3 tlPos;
	varying float sunVis;
	varying float moonVis;
#endif

#include "uniformWorldConstants.h"
#include "uniformPerFrameConstants.h"
#include "uniformShaderConstants.h"
#include "uniformRenderChunkConstants.h"
#include "common.glsl"

attribute POS4 POSITION;
attribute vec4 COLOR;
attribute vec2 TEXCOORD_0;
attribute vec2 TEXCOORD_1;

const float rA = 1.0;
const float rB = 1.0;
const vec3 UNIT_Y = vec3(0, 1, 0);
const float DIST_DESATURATION = 56.0 / 255.0;

void main(){

	POS4 worldPos;

#ifdef AS_ENTITY_RENDERER
		POS4 pos = WORLDVIEWPROJ * POSITION;
		worldPos = pos;
#else
		worldPos.xyz = (POSITION.xyz * CHUNK_ORIGIN_AND_SCALE.w) + CHUNK_ORIGIN_AND_SCALE.xyz;
		POS4 pos = WORLDVIEW * vec4(worldPos.xyz, 1.0);
		pos = PROJ * pos;
#endif

	gl_Position = pos;

#ifndef BYPASS_PIXEL_SHADER
	uv0 = TEXCOORD_0;
	uv1 = TEXCOORD_1;
	vcolor = COLOR;
	cPos = POSITION.xyz;
	wPos = worldPos.xyz;
	nWPos = normalize(worldPos.xyz);
	calcLpos(tlPos, lPos);
	sunVis = saturate(lPos.y);
	moonVis = saturate(-lPos.y);
	atml(lPos, sunCol, moonCol, szCol);
#endif

#ifdef BLEND
	if(vcolor.a < 0.95){
		#ifdef FANCY
			vcolor = COLOR;
		#else
			vcolor = vec4(COLOR.rgb, 1.0);
		#endif
		float camDist = length(-worldPos.xyz) / FAR_CHUNKS_DISTANCE;
		vcolor.a = mix(vcolor.a, 1.0, saturate(camDist));
	}
#endif

#ifndef BYPASS_PIXEL_SHADER
	#ifndef FOG
		vcolor.rgb += FOG_COLOR.rgb * 1e-5;
	#endif
#endif
}
