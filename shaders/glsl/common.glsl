//////////////////////////////////////////////////////////////
///////////////// ADJUSTABLE VARIABLE ////////////////////////
//////////////////////////////////////////////////////////////

//#define DYNAMIC_LIGHT_ANGLE
#define DYNAMIC_L_ANGLE_SPEED 0.008
#define SUN_LIGHT_ANGLE 20.0 // range 0 - 360 (degrees) and will affected when disabling DYNAMIC_LIGHT_ANGLE
#define SUN_PATH_ROTATION -30.0

#define SKY_COEFF_R 0.03
#define SKY_COEFF_G 0.0455
#define SKY_COEFF_B 0.09
#define SKY_NIGHT_SATURATION 0.4
#define SKY_MIE_COEFF 0.004
#define SKY_MIE_G 0.75

#define BLOCK_LIGHT_C_R 1.0
#define BLOCK_LIGHT_C_G 0.45
#define BLOCK_LIGHT_C_B 0.0

#define FOG_DISTANCE 100.0
#define SS_FOG_INTENSITY 0.2
#define NOON_FOG_INTENSITY 0.01
#define RAIN_FOG_INTENSITY 1.0
#define FOG_MIE_COEFF 0.08
#define FOG_MIE_G 0.7

#define SATURATION 1.3
#define EXPOSURE_MULTIPLICATION 1.0

///////////////////////////////////////////////////////////////
////////////// END OF ADJUSTABLE VARIABLE /////////////////////
///////////////////////////////////////////////////////////////

uniform highp float TOTAL_REAL_WORLD_TIME;

const float pi = 3.14159265;
const float hpi = 1.57079633;
const float invpi = 0.31830989;
const float tau = 6.28318531;
const float invtau = 0.15915494;

#define max0(x) max(0.0, x)
#define saturate(x) clamp(x, 0.0, 1.0)
#define csmooth(x) x * x * (3.0 - 2.0 * x)
#define rotate2d(r) mat2(cos(r), sin(r), -sin(r), cos(r))
#define wrain smoothstep(0.6, 0.3, FOG_CONTROL.x)

float remap(float value, float low1, float high1, float low2, float high2){
	return low2 + (value - low1) * (high2 - low2) / (high1 - low1);
}

float luma(vec3 color){
	return dot(color, vec3(0.2125, 0.7154, 0.0721));
}

float rPhase(float cosT){
	return 0.375 * (cosT * cosT + 1.0);
}

float mPhase(float cosT, float g){
	float g2 = g * g;
	return 0.78539816 * ((1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosT, 1.5));
}

float cphase(float cost){
	float mie1 = mPhase(cost, 0.7), mie2 = mPhase(cost, -0.1);
	return mix(mie2, mie1, 0.2);
}

float cphase2(float cost){
	float mie1 = mPhase(cost, 0.85), mie2 = mPhase(cost, 0.0);
	return mix(mie2, mie1, 0.3);
}

vec2 pDens(float d){
	d = -2.0 * d * 900.0;
	return vec2(sqrt(364e3 + d * d - 36e4) + d, sqrt(372e3 + d * d - 36e4) + d);
}

vec3 toLinear(vec3 color){
	return mix(color * 0.07739938, pow(0.947867 * color + 0.0521327, vec3(2.4)), step(0.04045, color));
}

vec3 toSrgb(vec3 color){
	return mix(color * 12.92, pow(color, vec3(0.41666667)) * 1.055 - 0.055, step(0.0031308, color));
}

// aces approximation https://github.com/TheRealMJP/BakingLab/blob/master/LICENSE
vec3 RRTandODTFit(vec3 color){
	vec3 a = color * (color + 0.0245786) - 0.000090537;
	vec3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
	return a / b;
}

vec3 colorCorrection(vec3 color){
	color *= EXPOSURE_MULTIPLICATION;
	color *= mat3(0.59719, 0.35458, 0.04823, 0.07600, 0.90834, 0.01566, 0.02840, 0.13383, 0.83777);
	color = RRTandODTFit(color);
	color *= mat3(1.60475, -0.53108, -0.07367, -0.10208,  1.10813, -0.00605, -0.00327, -0.07276,  1.07602);
	color = saturate(color);
	color = toSrgb(color);
	color = mix(vec3(luma(color)), color, SATURATION);
	return color;
}

const vec3 rCoeff = vec3(SKY_COEFF_R, SKY_COEFF_G, SKY_COEFF_B);
#define sc(coeff, coeff2, d) (coeff * d + coeff2 * d)

vec3 calcphase(vec3 wpos, vec3 lpos, float vod){
	float lcdist = max0(1.0 - distance(wpos, lpos));
	float raylphase = rPhase(lcdist), miephase = mPhase(lcdist, SKY_MIE_G * exp2(-vod * 0.005));
	return sc(rCoeff * raylphase, SKY_MIE_COEFF * miephase, vod);
}

vec3 cdscatter(vec3 sabsorb, vec3 vabsorb, vec3 nwpos, vec3 spos, vec2 od){
	vec3 scatterc = abs(sabsorb - vabsorb) / abs(sc(rCoeff, SKY_MIE_COEFF, od.y) - sc(rCoeff, SKY_MIE_COEFF, od.x));
	vec3 phase = calcphase(nwpos, spos, od.x);
 	return scatterc * phase * exp2(-od.y * 0.001);
}

vec3 cnscatter(vec3 sabsorb, vec3 vabsorb, vec3 nwpos, vec3 mpos, vec2 od){
	vec3 scatterc = abs(sabsorb - vabsorb) / abs(sc(rCoeff, SKY_MIE_COEFF, od.y) - sc(rCoeff, SKY_MIE_COEFF, od.x));
	vec3 phase = calcphase(nwpos, mpos, od.x);
 	return scatterc * phase * exp2(-od.x * 0.005);
}

vec3 catmosphere(vec3 skyzc, vec3 nwpos, vec3 spos, out vec3 sabsorb, out vec3 mabsorb, out vec3 vabsorb){
	float vod = pDens(nwpos.y).x, sod = pDens(spos.y).y, mood = pDens(-spos.y).y;

	sabsorb = exp2(-sc(rCoeff, SKY_MIE_COEFF, sod));
	mabsorb = exp2(-sc(rCoeff, SKY_MIE_COEFF, mood));
	vabsorb = exp2(-sc(rCoeff, SKY_MIE_COEFF, vod));

	vec3 dscatter = cdscatter(sabsorb, vabsorb, nwpos, spos, vec2(vod, sod));
	vec3 nscatter = cnscatter(mabsorb, vabsorb, nwpos, -spos, vec2(vod, mood));
	vec3 mscatter = (vabsorb / sc(rCoeff, SKY_MIE_COEFF, vod)) * sc(rCoeff, SKY_MIE_COEFF, vod);

	return dscatter * tau + skyzc * mscatter + mix(vec3(luma(nscatter)), nscatter, SKY_NIGHT_SATURATION) * invpi;
}
#undef sc

vec3 catmosphere(vec3 nwpos, vec3 spos, out vec3 sabsorb, out vec3 mabsorb, out vec3 vabsorb){
	vec3 skyzc = catmosphere(vec3(0.0), vec3(0, 1, 0), spos, sabsorb, mabsorb, vabsorb);
	return catmosphere(skyzc, nwpos, spos, sabsorb, mabsorb, vabsorb);
}

float getdisk(vec3 spos, vec3 dpos, float size){
	float angle = saturate((1.0 - dot(spos, dpos)) * size);
	return cos(angle * hpi);
}

vec3 csky(vec3 nwpos, vec3 spos){
	vec3 useless = vec3(0.0), absorbc = vec3(0.0);
	float vod = pDens(nwpos.y).x;
	vec3 tsky = catmosphere(nwpos, spos, useless, useless, absorbc);
		absorbc = mix(vec3(0.0), absorbc, exp2(-vod * 0.128));
		tsky += absorbc * 1000.0 * getdisk(nwpos, spos, 3e3);
		tsky += absorbc * 100.0 * getdisk(nwpos, -spos, 6e3);
	return tsky;
}

void atml(vec3 spos, out vec3 sunC, out vec3 moonC, out vec3 szColor){
	sunC = vec3(0.0), moonC = vec3(0.0);
	vec3 useless = vec3(0.0);
	szColor = catmosphere(vec3(0, 1, 0), spos, sunC, moonC, useless);
	sunC *= pi, moonC = vec3(luma(moonC)) * invtau, szColor *= pi;
}

void calcLpos(out vec3 tlPos, out vec3 lPos){
	#ifdef DYNAMIC_LIGHT_ANGLE
		highp float ang = TOTAL_REAL_WORLD_TIME * DYNAMIC_L_ANGLE_SPEED;
		lPos = normalize(vec3(cos(ang), sin(ang), 0.0));
	#else
		float langrad = radians(SUN_LIGHT_ANGLE);
		lPos = normalize(vec3(cos(langrad), sin(langrad), 0.0));
	#endif
	float protrad = radians(SUN_PATH_ROTATION);
	lPos.yz *= rotate2d(protrad);
	tlPos = lPos.y >= 0.0 ? lPos : -lPos;
}
