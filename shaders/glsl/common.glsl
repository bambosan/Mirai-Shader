//////////////////////////////////////////////////////////////
///////////////// ADJUSTABLE VARIABLE ////////////////////////
//////////////////////////////////////////////////////////////

//#define DYNAMIC_LIGHT_ANGLE
//#define DYNAMIC_L_ANGLE_SPEED 0.05
#define SUN_LIGHT_ANGLE 30.0 // range 0 - 360 (degrees) and will affected when disabling DYNAMIC_LIGHT_ANGLE
#define SUN_PATH_ROTATION -30.0

const vec3 rayleighCoefficient = vec3(5.8e-6,1.35e-5, 3.31e-5);
const vec3 mieCoefficient = vec3(2e-6);
const float mieZenithLength = 1.2e3;
const float rayleighZenithLength = 8e3;
const float mieDirectionalG = 0.7;

#define BLOCK_LIGHT_C_R 1.0
#define BLOCK_LIGHT_C_G 0.45
#define BLOCK_LIGHT_C_B 0.0

#define FOG_DISTANCE 100.0
#define SS_FOG_INTENSITY 0.5
#define NOON_FOG_INTENSITY 0.01
#define RAIN_FOG_INTENSITY 1.0
#define FOG_MIE_COEFF 0.05
#define FOG_MIE_G 0.7

#define SATURATION 1.0
#define EXPOSURE_MULTIPLICATION 0.05

///////////////////////////////////////////////////////////////
////////////// END OF ADJUSTABLE VARIABLE /////////////////////
///////////////////////////////////////////////////////////////

precision highp float;
uniform float TOTAL_REAL_WORLD_TIME;

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

float map(float value, float min1, float max1, float min2, float max2) { return min2 + (value - min1) * (max2 - min2) / (max1 - min1); }

float luma(vec3 color){
	return dot(color, vec3(0.2125, 0.7154, 0.0721));
}

float rPhase(float cost){
	return 0.0596831 * (1.0 + (cost * cost));
}

float mPhase(float cost, float g){
	return 0.07957747 * ((1.0 - (g * g)) / pow(1.0 - 2.0 * g * cost + (g * g), 1.5));
}

float cphase(float cost){
	float mie1 = mPhase(cost, 0.7), mie2 = mPhase(cost, -0.1);
	return mix(mie2, mie1, 0.3);
}

float cphase2(float cost){
	float mie1 = mPhase(cost, 0.75), mie2 = mPhase(cost, 0.0);
	return mix(mie2, mie1, 0.3);
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

vec3 cab(float depth){
	float rdn = rayleighZenithLength / max0(depth);
	float mdn = mieZenithLength / max0(depth);
	vec3 sc = (rayleighCoefficient * rdn) + (mieCoefficient * mdn);
	return exp(-sc);
}

vec3 catm(vec3 wpos, vec3 lpos, float ec, float ps){
	float cost = max0(dot(wpos, lpos)) * ps;
	vec3 ext = cab(wpos.y);
	vec3 brt = rayleighCoefficient * rPhase(cost);
	vec3 bmt = mieCoefficient * mPhase(cost, mieDirectionalG);
	vec3 tph = brt + bmt;
	vec3 tco = rayleighCoefficient + mieCoefficient;
	float suni = ec * max0(1.0 - exp(-(hpi - acos(lpos.y))));
	vec3 tsc = suni * (tph / tco);
	vec3 lo = tsc * (1.0 - ext);
		lo *= mix(vec3(1), sqrt(tsc * ext), saturate(pow(1.0 - lpos.y, 5.0)));
	return lo;
}

vec3 catm(vec3 wpos, vec3 lpos){
	vec3 datm = catm(wpos, lpos, 1000.0, 1.0);
	vec3 natm = catm(wpos, -lpos, 100.0, 0.8 + 0.2);
		datm += mix(vec3(luma(natm)), natm, 0.5);
	return datm;
}

float cir(vec3 spos, vec3 dpos, float size){
	float angle = saturate((1.0 - dot(spos, dpos)) * size);
	return cos(angle * hpi);
}

vec3 csky(vec3 nwpos, vec3 spos){
	vec3 sunc = cab(spos.y);
		sunc *= 1e3;
		sunc *= cir(nwpos, spos, 3e3);
	vec3 moonc = cab(-spos.y);
		moonc = mix(vec3(luma(moonc)), moonc, 0.5) * 500.0;
		moonc *= cir(nwpos, -spos, 2e3);
	vec3 tsky = catm(nwpos, spos) + sunc + moonc;
	return tsky;
}

void atml(vec3 spos, out vec3 sunc, out vec3 moonc, out vec3 zcol){
	sunc = cab(spos.y) * 70.0;
	moonc = cab(-spos.y);
	moonc = mix(vec3(luma(moonc)), moonc, 0.5);
	zcol = catm(vec3(0, 1, 0), spos);
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
