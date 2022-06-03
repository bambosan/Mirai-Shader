//////////////////////////////////////////////////////////////
////////////////// TOGGLE FEATURES ///////////////////////////
//////////////////////////////////////////////////////////////
/* disable of the features by giving two slashes

example
this is enabled
#define ENABLE_DYNAMIC_LIGHT_ANGLE

this is disabled
//#define ENABLE_DYNAMIC_LIGHT_ANGLE
*/

#define ENABLE_DYNAMIC_LIGHT_ANGLE
#define ENABLE_VOLUMETRIC_CLOUD
#define ENABLE_CIRRUS_CLOUD

#define ENABLE_WATERBUMP
#define ENABLE_UNDERWATER_CAUSTIC
//#define ENABLE_SKY_REFLECTION
#define ENABLE_FAKE_CLOUD_REFLECTION
#define ENABLE_SPECULAR_REFLECTION

//////////////////////////////////////////////////////////////
///////////////// ADJUSTABLE VARIABLE ////////////////////////
/////////////// DONT DISABLE ANYTHING !! /////////////////////

// adjust how fast time passes
#define DYNAMIC_LIGHT_ANGLE_SPEED 0.05

// range 0 - 360 (degrees) and will affected when disabling DYNAMIC_LIGHT_ANGLE
// 0 - 180 is full daytime and 180 - 360 is full night time
#define SUN_LIGHT_ANGLE 210.0

// rotation of the sun in z direction
#define SUN_PATH_ROTATION -40.0

// atmospheric scattering settings
#define RAYLEIGH_COEFFICIENT_R 5.8e-6 // 5.8e-6 = 0.0000058
#define RAYLEIGH_COEFFICIENT_G 1.35e-5 // 1.35e-5 = 0.0000135
#define RAYLEIGH_COEFFICIENT_B 3.31e-5 // 3.31e-5 = 0.0000331
#define RAYLEIGH_HEIGHT 8e3 // 8e3 = 8000
#define MIE_COEFFICIENT 2e-6 // 2e-6 = 0.000002
#define MIE_HEIGHT 1.2e3 // 1.2e3 = 1200
#define MIE_DIRECTIONAL_G 0.73

// fog settings
#define FOG_DISTANCE 100.0
#define SS_FOG_INTENSITY 0.1
#define NOON_FOG_INTENSITY 0.05
#define RAIN_FOG_INTENSITY 1.0
#define FOG_MIE_COEFF 0.04
#define FOG_MIE_G 0.7

// cloud settings
// set volumetric cloud height in meters
#define VOLUMETRIC_CLOUD_HEIGHT 6e2 // 6e2 = 600
// set volumetric cloud thickness in meters
#define VOLUMETRIC_CLOUD_THICKNESS 1e3 // 1e3 = 1000
// volumetric cloud steps, this is the main value of quality. bigger is better, smaller will be more dither
#define VOLUMETRIC_CLOUD_STEPS 30
// volumetric cloud light steps, affected on the thickness of light absorbed by cloud
#define VOLUMETRIC_CLOUD_LIGHT_STEPS 4
// value of cloud brightness in the area near sun
#define VOLUMETRIC_CLOUD_MIE_STRENGTH 0.4
// light scatter of cloud from the area near sun
#define VOLUMETRIC_CLOUD_MIE_DIRECTIONAL_G 0.7
#define CIRRUS_CLOUD_MIE_STRENGTH 0.2
#define CIRRUS_CLOUD_MIE_DIRECTIONAL_G 0.75

// water reflection settings
#define SPECULAR_ROUGHNESS 0.04
#define REFLECTION_ROUGHNESS 0.3

// underwater settings
#define CAUSTIC_ATTENUATION 2.0
#define CAUSTIC_BRIGHTNESS 0.3
#define ABSORBTION_C_R 0.0
#define ABSORBTION_C_G 0.6
#define ABSORBTION_C_B 1.0
#define ABSORBTION_INTENSITY 6.0

// torch light value
#define BLOCK_LIGHT_C_R 1.0
#define BLOCK_LIGHT_C_G 0.45
#define BLOCK_LIGHT_C_B 0.0

// adjust exposure globally
#define EXPOSURE_MULTIPLICATION 0.05
// adjust saturation globally
#define COLOR_SATURATION 1.1
// adjust contrast globally
#define COLOR_CONTRAST 1.1

// adjust terrain shadow
#define SHADOW_BRIGHTNESS 0.4
// adjust saturation of terrain shadow, higher more bluish
#define SHADOW_SATURATION 0.8

// sorry my english is so bad :(
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
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
float rphase(float cost){
	return 0.0596831 * (1.0 + (cost * cost));
}
float mphase(float cost, float g){
	return 0.07957747 * ((1.0 - (g * g)) / pow(1.0 - 2.0 * g * cost + (g * g), 1.5));
}
float cphase(float cost){
	float mie1 = mphase(cost, VOLUMETRIC_CLOUD_MIE_DIRECTIONAL_G), mie2 = mphase(cost, -0.05);
	return mix(mie2, mie1, VOLUMETRIC_CLOUD_MIE_STRENGTH);
}
float cphase2(float cost){
	float mie1 = mphase(cost, CIRRUS_CLOUD_MIE_DIRECTIONAL_G), mie2 = mphase(cost, 0.0);
	return mix(mie2, mie1, CIRRUS_CLOUD_MIE_STRENGTH);
}
float hash13(vec3 p){
	p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 tolin(vec3 color){
	return mix(color * 0.07739938, pow(0.947867 * color + 0.0521327, vec3(2.4)), step(0.04045, color));
}
vec3 tosrgb(vec3 color){
	return mix(color * 12.92, pow(color, vec3(0.41666667)) * 1.055 - 0.055, step(0.0031308, color));
}
vec3 jodieReinhardTonemap(vec3 c){
	float lum = luma(c);
	vec3 tc = c / (c + 1.0);
	return mix(c / (lum + 1.0), tc, tc);
}
vec3 colcor(vec3 color){
	color *= EXPOSURE_MULTIPLICATION;
	color = pow(color, vec3(COLOR_CONTRAST));
	color = jodieReinhardTonemap(color);
	color = tosrgb(color);
	return mix(vec3(length(color)), color, COLOR_SATURATION);
}

const vec3 rcoeff = vec3(RAYLEIGH_COEFFICIENT_R, RAYLEIGH_COEFFICIENT_G, RAYLEIGH_COEFFICIENT_B);
const vec3 mcoeff = vec3(MIE_COEFFICIENT);
vec3 cab(float depth){
	float rdn = RAYLEIGH_HEIGHT / max0(depth);
	float mdn = MIE_HEIGHT / max0(depth);
	vec3 sc = (rcoeff * rdn) + (mcoeff * mdn);
	return exp(-sc);
}

vec3 catm(vec3 wpos, vec3 lpos, float ec){
	float cost = max0(dot(wpos, lpos));
	vec3 ext = cab(wpos.y);
	vec3 brt = rcoeff * rphase(cost);
	vec3 bmt = mcoeff * mphase(cost, MIE_DIRECTIONAL_G);
	vec3 tph = brt + bmt;
	vec3 tco = rcoeff + mcoeff;
	float suni = ec * saturate(1.0 - exp(-(hpi - acos(lpos.y * 0.95 + 0.05))));
	vec3 tsc = suni * (tph / tco);
	vec3 lo = tsc * (1.0 - ext);
		lo *= mix(vec3(1.0), sqrt(tsc * ext), saturate(pow(1.0 - lpos.y, 5.0)));
	return lo;
}
vec3 catm(vec3 wpos, vec3 lpos){
	vec3 datm = catm(wpos, lpos, 1000.0);
	vec3 natm = catm(wpos, -lpos, 100.0);
		datm += max(vec3(0), normalize(natm));
	return datm;
}

float cir(vec3 spos, vec3 dpos, float size){
	float angle = saturate((1.0 - dot(spos, dpos)) * size);
	return cos(angle * hpi);
}
float star(vec3 p){
	p = floor((abs(p) + 16.0) * 265.0);
	return smoothstep(0.9975, 1.0, hash13(p));
}

vec3 csky(vec3 nwpos, vec3 spos){
	vec3 sunc = cab(spos.y);
		sunc *= 500.0;
		sunc *= cir(nwpos, spos, 3e3);
	vec3 moonc = cab(-spos.y);
		moonc = mix(vec3(luma(moonc)), moonc, 0.5) * 100.0;
		moonc *= cir(nwpos, -spos, 2e3);
	vec3 tsky = catm(nwpos, spos) + sunc + moonc;
	return tsky + (star(nwpos + TOTAL_REAL_WORLD_TIME * 0.001) * tau * saturate(-spos.y) * saturate(exp(nwpos.y * 50.0)));
}

void atml(vec3 spos, out vec3 sunc, out vec3 moonc, out vec3 zcol){
	sunc = cab(spos.y) * 65.0;
	moonc = cab(-spos.y);
	moonc = mix(vec3(luma(moonc)), moonc, 0.3) * pi;
	zcol = catm(vec3(0, 1, 0), spos);
}
void clpos(out vec3 tlpos, out vec3 lpos){
	#ifdef ENABLE_DYNAMIC_LIGHT_ANGLE
		float ang = TOTAL_REAL_WORLD_TIME * DYNAMIC_LIGHT_ANGLE_SPEED;
		lpos = normalize(vec3(cos(ang), sin(ang), 0.0));
	#else
		float langrad = radians(SUN_LIGHT_ANGLE);
		lpos = normalize(vec3(cos(langrad), sin(langrad), 0.0));
	#endif
	float protrad = radians(SUN_PATH_ROTATION);
	lpos.yz *= rotate2d(protrad);
	tlpos = lpos.y > 0.0 ? lpos : -lpos;
}
