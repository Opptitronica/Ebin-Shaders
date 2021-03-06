float Encode16(in vec2 encodedBuffer) {
	cvec2 encode = vec2(1.0, exp2(8.0));
	
	encodedBuffer = round(encodedBuffer * 255.0);
	
	return dot(encodedBuffer, encode) / (exp2(16.0) - 1.0);
}

vec2 Decode16(in float encodedBuffer) {
	cvec2 decode = 1.0 / (exp2(8.0) - 1.0) / vec2(1.0, exp2(8.0));
	
	vec2 decoded;
	
	encodedBuffer *= exp2(16.0) - 1.0;
	
	decoded.r = mod(encodedBuffer, exp2(8.0));
	decoded.g = encodedBuffer - decoded.r;
	
	return decoded * decode;
}

vec3 EncodeColor(in vec3 color) { // Prepares the color to be sent through a limited dynamic range pipeline
	return pow(color * 0.001, vec3(1.0 / 2.2));
}

vec3 DecodeColor(in vec3 color) {
	return pow(color, vec3(2.2)) * 1000.0;
}

vec2 EncodeNormal(vec3 normal) {
    float p = sqrt(normal.z * 8.0 + 8.0);
    return vec2(normal.xy / p + 0.5);
}

vec3 DecodeNormal(vec2 encodedNormal) {
    vec2 fenc = encodedNormal * 4.0 - 2.0;
	float f = lengthSquared(fenc);
	float g = sqrt(1.0 - f * 0.25);
	return vec3(fenc * g, 1.0 - f * 0.5);
}

vec2 encodeNormal(vec3 normal) {
	vec2 p = normal.xy / (abs (normal.z) + 1.0);
	float d = abs (p.x) + abs (p.y) + 0.0;
	float r = length (p);
	vec2 q = p * r / d;
	float z_is_negative = max (-sign (normal.z), 0.0);
	vec2 q_sign = sign (q);
	q_sign = sign (q_sign + vec2 (0.5, 0.5));
	q -= z_is_negative * (dot (q, q_sign) - 1.0) * q_sign;
	
	return q * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 encodedNormal) {
	vec2 p = encodedNormal * 2.0 - 1.0;
	
	float zsign = sign (1.0 - abs(p.x) - abs(p.y));
	float z_is_negative = max (-zsign, 0.0);
	vec2 p_sign = sign (p);
	p_sign = sign (p_sign + vec2(0.5, 0.5));
	p -= z_is_negative * (dot (p, p_sign) - 1.0) * p_sign;
	
	float r = abs(p.x) + abs(p.y);
	float d = length (p) + 0.0;
	vec2 q = p * r / d;
	
	float den = 2.0 / (dot (q, q) + 1.0);
	vec3 v = vec3(den * q, zsign * (den - 1.0));
	
	return v;
}
