#version 410 compatibility
#define composite2
#define fsh
#define ShaderStage 2
#include "/lib/Syntax.glsl"


/* DRAWBUFFERS:1 */

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D gdepthtex;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float frameTimeCounter;
uniform float rainStrength;

uniform float near;
uniform float far;

uniform int isEyeInWater;

varying vec2 texcoord;

#include "/lib/Settings.glsl"
#include "/lib/Util.glsl"
#include "/lib/DebugSetup.glsl"
#include "/lib/GlobalCompositeVariables.glsl"
#include "/lib/Masks.glsl"
#include "/lib/CalculateFogFactor.glsl"
#include "/lib/ReflectanceModel.fsh"

const bool colortex2MipmapEnabled = true;


vec3 GetColor(in vec2 coord) {
	return DecodeColor(texture2D(colortex2, coord).rgb);
}

vec3 GetColorLod(in vec2 coord, in float lod) {
	return DecodeColor(texture2DLod(colortex2, coord, lod).rgb);
}

float GetDepth(in vec2 coord) {
	return texture2D(gdepthtex, coord).x;
}

float GetTransparentDepth(in vec2 coord) {
	return texture2D(depthtex1, coord).x;
}

vec4 CalculateViewSpacePosition(in vec2 coord, in float depth) {
	vec4 position  = gbufferProjectionInverse * vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
	     position /= position.w;
	
	return position;
}

vec3 ViewSpaceToScreenSpace(vec3 viewSpacePosition) {
	vec4 screenSpace = gbufferProjection * vec4(viewSpacePosition, 1.0);
	
	return (screenSpace.xyz / screenSpace.w) * 0.5 + 0.5;
}

vec3 ViewSpaceToScreenSpace(vec4 viewSpacePosition) {
	vec4 screenSpace = gbufferProjection * viewSpacePosition;
	
	return (screenSpace.xyz / screenSpace.w) * 0.5 + 0.5;
}

vec3 GetNormal(in vec2 coord) {
	return DecodeNormal(texture2D(colortex1, coord).xy);
}

#include "/lib/WaterWaves.fsh"

void GetColortex3(in vec2 coord, out vec2 Colortex3, out float buffer0r, out float buffer0g, out float buffer0b, out float buffer1r) {
	Colortex3.r = texture2D(colortex3, texcoord).r;
	Colortex3.g = texture2D(colortex3, texcoord).g;
	
	float buffer1g, buffer1b;
	
	Decode32to8(Colortex3.r, buffer0r, buffer0g, buffer0b);
	Decode32to8(Colortex3.g, buffer1r, buffer1g, buffer1b);
}

float GetVolumetricFog(in vec2 coord) {
	return texture2D(colortex4, coord).a;
}

float noise(in vec2 coord) {
    return fract(sin(dot(coord, vec2(12.9898, 4.1414))) * 43758.5453);
}

#include "/lib/Sky.fsh"

bool ComputeRaytracedIntersection(in vec3 startingViewPosition, in vec3 rayDirection, in float firstStepSize, cfloat rayGrowth, cint maxSteps, cint maxRefinements, out vec3 screenSpacePosition, out vec4 viewSpacePosition) {
	if (dot(vec3(0.0, 0.0, -1.0), rayDirection) < 0.0) return false;
	
	vec3 rayStep = rayDirection * firstStepSize;
	vec4 ray = vec4(startingViewPosition + rayStep, 1.0);
	
	screenSpacePosition = ViewSpaceToScreenSpace(ray);
	
	float refinements = 0;
	float refinementCoeff = 1.0;
	
	cbool doRefinements = (maxRefinements > 0);
	
	for (int i = 0; i < maxSteps; i++) {
		if (screenSpacePosition.x < 0.0 || screenSpacePosition.x > 1.0 ||
			screenSpacePosition.y < 0.0 || screenSpacePosition.y > 1.0 ||
			screenSpacePosition.z < 0.0 || screenSpacePosition.z > 1.0 ||
			-ray.z > far * 1.6 + 16.0)
		{   return false; }
		
		float sampleDepth = GetDepth(screenSpacePosition.st);
		
		viewSpacePosition = CalculateViewSpacePosition(screenSpacePosition.st, sampleDepth);
		
		float diff = viewSpacePosition.z - ray.z;
		
		if (diff >= 0) {
			if (doRefinements) {
				float error = firstStepSize * pow(rayGrowth, i) * refinementCoeff;
				
				if(diff <= error * 2.0 && refinements <= maxRefinements) {
					ray.xyz -= rayStep * refinementCoeff;
					refinementCoeff = 1.0 / exp2(++refinements);
				} else if (diff <= error * 4.0 && refinements > maxRefinements) {
					screenSpacePosition.z = sampleDepth;
					return true;
				}
			}
			
			else return true;
		}
		
		ray.xyz += rayStep * refinementCoeff;
		
		rayStep *= rayGrowth;
		
		screenSpacePosition = ViewSpaceToScreenSpace(ray);
	}
	
	return false;
}

#ifndef PBR
void ComputeReflectedLight(inout vec3 color, in vec4 viewSpacePosition, in vec3 normal, in float smoothness, in float skyLightmap, in float sunlight, in Mask mask) {
	if (smoothness < 0.01) return;
	
	vec3  rayDirection  = normalize(reflect(viewSpacePosition.xyz, normal));
	float firstStepSize = mix(1.0, 30.0, pow2(length((gbufferModelViewInverse * viewSpacePosition).xz) / 144.0));
	vec3  reflectedCoord;
	vec4  reflectedViewSpacePosition;
	vec3  reflection;
	
	float roughness = 1.0 - smoothness;
	
	float vdoth   = clamp01(dot(-normalize(viewSpacePosition.xyz), normal));
	vec3  sColor  = mix(vec3(0.15), color * 0.2, vec3(mask.metallic));
	vec3  fresnel = Fresnel(sColor, vdoth);
	
	vec3 reflectedSky  = CalculateSky(vec4(reflect(viewSpacePosition.xyz, normal), 1.0), false);
	     reflectedSky *= clamp(pow(skyLightmap, 5.0) + sunlight, 0.002, 1.0);
	
	vec3 reflectedSunspot = CalculateSpecularHighlight(lightVector, normal, fresnel, -normalize(viewSpacePosition.xyz), roughness) * sunlight;
	
	vec3 offscreen = reflectedSky + reflectedSunspot * sunlightColor * 100.0;
	
	if (!ComputeRaytracedIntersection(viewSpacePosition.xyz, rayDirection, firstStepSize, 1.3, 30, 3, reflectedCoord, reflectedViewSpacePosition))
		reflection = offscreen;
	else {
		reflection = GetColor(reflectedCoord.st);
		
		vec3 reflectionVector = normalize(reflectedViewSpacePosition.xyz - viewSpacePosition.xyz) * length(reflectedViewSpacePosition.xyz); // This is not based on any physical property, it just looked around when I was toying around
		
		CompositeFog(reflection, vec4(reflectionVector, 1.0), GetVolumetricFog(reflectedCoord.st));
		
		#ifdef REFLECTION_EDGE_FALLOFF
			float angleCoeff = clamp(pow(dot(vec3(0.0, 0.0, 1.0), normal) + 0.15, 0.25) * 2.0, 0.0, 1.0) * 0.2 + 0.8;
			float dist       = length8(abs(reflectedCoord.xy - vec2(0.5)));
			float edge       = clamp(1.0 - pow2(dist * 2.0 * angleCoeff), 0.0, 1.0);
			reflection       = mix(reflection, reflectedSky, pow(1.0 - edge, 10.0));
		#endif
	}
	
	color = mix(color, reflection, fresnel * smoothness);
}

#else
void ComputeReflectedLight(inout vec3 color, in vec4 viewSpacePosition, in vec3 normal, in float smoothness, in float skyLightmap, in float sunlight, in Mask mask) {
	float firstStepSize = mix(1.0, 30.0, pow2(length((gbufferModelViewInverse * viewSpacePosition).xz) / 144.0));
	vec3  reflectedCoord;
	vec4  reflectedViewSpacePosition;
	vec3  reflection;
	
	float roughness = 1.0 - smoothness;
	
	float vdoth   = clamp01(dot(-normalize(viewSpacePosition.xyz), normal));
	vec3  sColor  = mix(vec3(0.15), color * 0.2, vec3(mask.metallic));
	vec3  fresnel = Fresnel(sColor, vdoth);
	
	vec3 alpha = fresnel * smoothness;
	
	
	vec3 reflectedSky  = CalculateSky(vec4(reflect(viewSpacePosition.xyz, normal), 1.0), false);
	     reflectedSky *= (pow(skyLightmap, 5.0) + sunlight) * 0.998 + 0.002;
	
	vec3 reflectedSunspot = CalculateSpecularHighlight(lightVector, normal, fresnel, -normalize(viewSpacePosition.xyz), roughness) * sunlight;
	
	vec3 offscreen = reflectedSky + reflectedSunspot * sunlightColor * 100.0;
	
	
	for (int i = 1; i <= PBR_RAYS; i++) {
		vec2 epsilon  = vec2(noise(texcoord * i), noise(texcoord * i * 3));
		vec3 BRDFSkew = skew(epsilon, roughness);
		
		vec3 reflectDir  = normalize(normal + BRDFSkew * roughness / 12.0);
		     reflectDir *= sign(dot(normal, reflectDir));
		
		vec3 rayDirection = reflect(normalize(viewSpacePosition.xyz), reflectDir);
		
		
		if (!ComputeRaytracedIntersection(viewSpacePosition.xyz, rayDirection, firstStepSize, 1.3, 30, 3, reflectedCoord, reflectedViewSpacePosition)) { //this is much faster I tested
			reflection += offscreen + 0.1 * mask.metallic;
		} else {
			vec3 reflectionVector = normalize(reflectedViewSpacePosition.xyz - viewSpacePosition.xyz) * length(reflectedViewSpacePosition.xyz); // This is not based on any physical property, it just looked around when I was toying around
			// Maybe give previous reflection Intersection to make sure we dont compute rays in the same pixel twice.
			
			vec3 colorSample = GetColorLod(reflectedCoord.st, 2);
			
			CompositeFog(colorSample, vec4(reflectionVector, 1.0), GetVolumetricFog(reflectedCoord.st));
			
			#ifdef REFLECTION_EDGE_FALLOFF
				float angleCoeff = clamp(pow(dot(vec3(0.0, 0.0, 1.0), normal) + 0.15, 0.25) * 2.0, 0.0, 1.0) * 0.2 + 0.8;
				float dist       = length8(abs(reflectedCoord.xy - vec2(0.5)));
				float edge       = clamp(1.0 - pow2(dist * 2.0 * angleCoeff), 0.0, 1.0);
				colorSample      = mix(colorSample, reflectedSky, pow(1.0 - edge, 10.0));
			#endif
			
			reflection += colorSample;
		}
	}
	
	reflection /= PBR_RAYS;
	
	color = mix(color * (1.0 - mask.metallic * 0.9), reflection, alpha);
}
#endif

void GetWaterTBN(out mat3 tbnMatrix) {
	vec3 normal = DecodeNormal(texture2D(colortex0, texcoord).xy);
	vec3 tangent = DecodeNormal(texture2D(colortex6, texcoord).xy);
	vec3 binormal = normalize(cross(normal, tangent));
	
	tbnMatrix = transpose(mat3(tangent, binormal, normal));
}


void main() {
	vec3  color = GetColor(texcoord);
	float depth = GetDepth(texcoord);
	
	if (depth >= 1.0) {
		gl_FragData[0] = vec4(EncodeColor(color), 1.0); exit(); return; }
	
	
	vec2 Colortex3; float torchLightmap, skyLightmap, smoothness; Mask mask;
	
	GetColortex3(texcoord, Colortex3, torchLightmap, skyLightmap, mask.materialIDs, smoothness);
	
	
	vec3  normal = GetNormal(texcoord);
	vec4  viewSpacePosition = CalculateViewSpacePosition(texcoord, depth);
	float depth1 = GetTransparentDepth(texcoord);
	
	smoothness = pow(smoothness, 2.2 * 2.2);
	
	
	CalculateMasks(mask);
	
	
	vec3 color1 = color; // Underwater color
	
	mat3 tbnMatrix;
	GetWaterTBN(tbnMatrix);
	
	if (mask.water > 0.5)  { color = vec3(0.0, 0.03, 0.35); normal = GetWaveNormals(viewSpacePosition, transpose(tbnMatrix)[2], tbnMatrix); smoothness = 0.85; }
	
	
	ComputeReflectedLight(color, viewSpacePosition, normal, smoothness, skyLightmap, 1.0, mask);
	
	
	if (mask.water > 0.5 && depth1 < 1.0) color = mix(color, color1, 0.2);
	
	
	CompositeFog(color, viewSpacePosition, GetVolumetricFog(texcoord));
	
	
	gl_FragData[0] = vec4(EncodeColor(color), 1.0);
	
	exit();
}