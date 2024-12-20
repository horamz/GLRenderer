#version 330 core

out vec4 FragColor;

in VS_OUT {
    vec2 TexCoords;
    vec3 WorldPos;
    vec3 Normal;
    vec4 WorldPosLightSpace;
} fs_in;

struct MaterialSolid {
    vec3 albedo;
    float metallic;
    float roughness;
    float ao;
};

struct MaterialTexture {
    sampler2D albedoMap;
    sampler2D normalMap;
    sampler2D metallicMap;
    sampler2D roughnessMap;
    sampler2D aoMap;
};

uniform bool gammaCorrect=true;

uniform bool hasAlbedo;
uniform bool hasMetallic;
uniform bool hasRoughness;
uniform bool hasAo;
uniform bool hasNormal;

uniform vec3 metallicChannel = vec3(1.0, 0.0, 0.0);
uniform vec3 roughnessChannel = vec3(0.0, 1.0, 0.0);

// IBL
uniform samplerCube irradianceMap;
uniform samplerCube prefilterMap;
uniform sampler2D brdfLUT;
uniform bool hasIBLMaps=false;

#define NR_MAX_LIGHTS 10

struct PointLight {
    vec3 position;
    vec3 color;
};

struct DirectionalLight {
    vec3 direction;
    vec3 color;
};

uniform PointLight pointLights[NR_MAX_LIGHTS];
uniform int pointLightsSize;
uniform DirectionalLight directionalLight;

uniform MaterialSolid material;
uniform MaterialTexture materialMaps;


uniform vec3 camPos;

uniform sampler2D shadowMap;
uniform bool hasShadow;

const float PI = 3.14159265359;
// ----------------------------------------------------------------------------
// Easy trick to get tangent-normals to world-space to keep PBR code simplified.
// Don't worry if you don't get what's going on; you generally want to do normal
// mapping the usual way for performance anyways; I do plan make a note of this
// technique somewhere later in the normal mapping tutorial.
vec3 getNormalFromMap()
{
    vec3 tangentNormal = texture(materialMaps.normalMap, fs_in.TexCoords).xyz * 2.0 - 1.0;

    vec3 Q1  = dFdx(fs_in.WorldPos);
    vec3 Q2  = dFdy(fs_in.WorldPos);
    vec2 st1 = dFdx(fs_in.TexCoords);
    vec2 st2 = dFdy(fs_in.TexCoords);

    vec3 N   = normalize(fs_in.Normal);
    vec3 T  = normalize(Q1*st2.t - Q2*st1.t);
    vec3 B  = -normalize(cross(N, T));
    mat3 TBN = mat3(T, B, N);

    return normalize(TBN * tangentNormal);
}
// ----------------------------------------------------------------------------
float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}
// ----------------------------------------------------------------------------
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}
// ----------------------------------------------------------------------------
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}
// ----------------------------------------------------------------------------
vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}
// ----------------------------------------------------------------------------
vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float ShadowCalculation(vec4 fragPosLightSpace, vec3 normal, vec3 lightDir) {

    // not required for ortho, but do it anyways
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;

    projCoords = projCoords * 0.5 + 0.5;

    if (projCoords.z > 1.0)
        return 0.0;

    float closestDepth = texture(shadowMap, projCoords.xy).r;
    float currentDepth = projCoords.z;

    float bias = max(0.05 * (1.0 - dot(normal, lightDir)), 0.005);
    float shadow = 0.0;

    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    for(int x = -1; x <= 1; ++x)
    {
        for(int y = -1; y <= 1; ++y)
        {
            float pcfDepth = texture(shadowMap, projCoords.xy + vec2(x, y) *
                                     texelSize).r;
            shadow += currentDepth - bias > pcfDepth ? 1.0 : 0.0;
        }
    }

    shadow /= 9.0;

    return shadow;
}

vec3 CalcPointLightRadiance(
    PointLight light,
    vec3 N,
    vec3 V,
    vec3 F0,
    vec3 albedo,
    float roughness,
    float metallic
) {
    vec3 L = normalize(light.position - fs_in.WorldPos);
    vec3 H = normalize(L + V);

    float distance = length(light.position - fs_in.WorldPos);
    float attenuation = 1.0 / (distance * distance);
    vec3 radiance = light.color * attenuation;

    float NDF = DistributionGGX(N, H, roughness);
    float G   = GeometrySmith(N, V, L, roughness);
    vec3 F    = fresnelSchlick(clamp(dot(H, V), 0.0, 1.0), F0);

    vec3 specular = (NDF * G * F) /
        (4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001);

    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;

    kD *= 1.0 - metallic;

    float NdotL = max(dot(N, L), 0.0);

    vec3 Lo = (kD * albedo / PI + specular) * radiance * NdotL;

    return Lo;
}

vec3 CalcDirLightRadiance(
    DirectionalLight light,
    vec3 N,
    vec3 V,
    vec3 F0,
    vec3 albedo,
    float roughness,
    float metallic
) {
    vec3 lightPos = normalize(-light.direction);
    //vec3 worldPos = normalize(fs_in.WorldPos);
    vec3 L = lightPos;
    vec3 H = normalize(L + V);

    float NDF = DistributionGGX(N, H, roughness);
    float G   = GeometrySmith(N, V, L, roughness);
    vec3 F    = fresnelSchlick(clamp(dot(H, V), 0.0, 1.0), F0);

    vec3 specular = (NDF * G * F) /
        (4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001);

    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;

    kD *= 1.0 - metallic;

    float NdotL = max(dot(N, L), 0.0);

    vec3 Lo = (kD * albedo / PI + specular) * light.color * NdotL;

    if (hasShadow) {
        float shadow = ShadowCalculation(fs_in.WorldPosLightSpace, N, -light.direction);
        Lo = (1.0 - shadow) * Lo;
    }
    return Lo;
}

void main()
{
    vec3 _Albedo, _Normal;
    float _Metallic, _Roughness, _Ao;

    if (hasAlbedo) {
        vec4 albedoSample = texture(materialMaps.albedoMap, fs_in.TexCoords);
        // TODO: Make this bias better
        if (albedoSample.a < 0.05)
            discard;
        _Albedo = albedoSample.rgb;
    }
    else {
        _Albedo = material.albedo;
    }

    _Normal = hasNormal ? getNormalFromMap()
        : fs_in.Normal;

    if (hasMetallic) {
        vec3 metal_sample = texture(materialMaps.metallicMap, fs_in.TexCoords).rgb;

        if (metallicChannel.r != 0) _Metallic = metal_sample.r;
        if (metallicChannel.g != 0) _Metallic = metal_sample.g;
        if (metallicChannel.b != 0) _Metallic = metal_sample.b;
    }
    else {
        _Metallic = material.metallic;
    }

    if (hasRoughness) {
        vec3 rough_sample = texture(materialMaps.roughnessMap, fs_in.TexCoords).rgb;

        if (roughnessChannel.r != 0) _Roughness = rough_sample.r;
        if (roughnessChannel.g != 0) _Roughness = rough_sample.g;
        if (roughnessChannel.b != 0) _Roughness = rough_sample.b;
    }
    else if (hasMetallic) {
        // If does not include a dedicated roughness map most likely its embedded
        // in metallic map's green channel
        _Roughness = texture(materialMaps.metallicMap, fs_in.TexCoords).g;
    } else {
        _Roughness = material.roughness;
    }

    _Ao = hasAo ? texture(materialMaps.aoMap, fs_in.TexCoords).r
        : material.ao;

    if (gammaCorrect && hasAlbedo) _Albedo = pow(_Albedo, vec3(2.2));

    vec3 N = normalize(_Normal);
    vec3 V = normalize(camPos - fs_in.WorldPos);
    vec3 R = reflect(-V, N);

    vec3 F0 = vec3(0.04);
    F0 = mix(F0, _Albedo, _Metallic);

    vec3 Lo = vec3(0.0);


    Lo += CalcDirLightRadiance(directionalLight, N, V, F0, _Albedo, _Roughness, _Metallic);

    for (int i = 0; i < pointLightsSize; i++)
        Lo += CalcPointLightRadiance(pointLights[i], N, V, F0, _Albedo, _Roughness, _Metallic);


    vec3 _Ambient;

    if (hasIBLMaps) {
        vec3 kS = fresnelSchlick(max(dot(N, V), 0.0), F0);
        vec3 kD = 1.0 - kS;
        kD *= 1.0 - _Metallic;

        vec3 irradiance = texture(irradianceMap, N).rgb;
        vec3 diffuse = irradiance * _Albedo;

        const float MAX_REFLECTION_LOD = 4.0;
        vec3 prefilteredColor = textureLod(prefilterMap, R, _Roughness * MAX_REFLECTION_LOD).rgb;
        vec2 brdf = texture(brdfLUT, vec2(max(dot(N, V), 0.0), _Roughness)).rg;
        vec3 specular = prefilteredColor * (kS * brdf.x + brdf.y);

        _Ambient = (kD * diffuse + specular) * _Ao;
    } else {
        _Ambient = vec3(0.03) * _Albedo * _Ao;
    }

    vec3 color = Lo + _Ambient;

    // Tone mapping and gamma correction is handled in postprocess
    // color = color / (color + vec3(1.0));
    // gamma correct
    // color = pow(color, vec3(1.0/2.2));

    FragColor = vec4(color, 1.0);
}
