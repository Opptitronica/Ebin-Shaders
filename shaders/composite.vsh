#version 410 compatibility
#define composite0
#define vsh
#define ShaderStage 10
#include "/lib/Syntax.glsl"


uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;

uniform vec3 upPosition;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float sunAngle;
uniform float frameTimeCounter;

varying vec2 texcoord;

#include "/lib/Settings.glsl"
#include "/lib/Utility.glsl"
#include "/lib/Uniform/ShadowViewMatrix.vsh"
#include "/lib/Uniform/GlobalCompositeVariables.glsl"
#include "/lib/DebugSetup.glsl"


void main() {
#if (defined GI_ENABLED) || (defined VOLUMETRIC_FOG)
	texcoord    = gl_MultiTexCoord0.st;
	gl_Position = ftransform();
	
	gl_Position.xy = ((gl_Position.xy * 0.5 + 0.5) * COMPOSITE0_SCALE) * 2.0 - 1.0;
	
	
	#include "/lib/Uniform/CompositeCalculations.vsh"
	
	exit();
#else
	gl_Position = vec4(-1.0);
#endif
}