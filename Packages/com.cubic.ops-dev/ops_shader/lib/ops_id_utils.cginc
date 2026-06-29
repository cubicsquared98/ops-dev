#ifndef OPS_ID_UTILS
#define OPS_ID_UTILS

//THIS IS A TEST. DO NOT REDISTRIBUTE.
#include "pcg4d_to_uint2.cginc"

// #pragma multi_compile _ UNITY_HDR_ON

#define ID_SPACE_ORIFICE 0
#define ID_SPACE_PENETRATOR 1
#define ID_SPACE_AVATAR 2
#define ID_SPACE_ANIMATOR 3

#define ID_SPACE_COUNT 4

//uint4 array, holds XY as space size, holds ZW as space offset
static const float ID_SPACE_F_ARRAY[] = {
    0.320f,
    0.320f,
    0.150f,
    0.210f
};
static const float ID_SPACE_F_TOTAL_ARRAY[] = {
    0.00f,
    0.320f,
    0.640f,
    0.790f
};

uint4 getIDSpace(uint ID_SPACE){
    float height_multiplier = ID_SPACE_F_ARRAY[ID_SPACE];
    float offset_multiplier = ID_SPACE_F_TOTAL_ARRAY[ID_SPACE];
    
    return max(uint4(1,1,0,0),
    #ifdef _OPS_ID_HASH_TEXTURE_Exists
        #if UNITY_SINGLE_PASS_STEREO && !(defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED))
            uint4(_OPS_ID_HASH_TEXTURE_TexelSize.z * 0.5f, _OPS_ID_HASH_TEXTURE_TexelSize.w * height_multiplier, 0, _OPS_ID_HASH_TEXTURE_TexelSize.w * offset_multiplier)
        #else
            uint4(_OPS_ID_HASH_TEXTURE_TexelSize.z, _OPS_ID_HASH_TEXTURE_TexelSize.w * height_multiplier, 0, _OPS_ID_HASH_TEXTURE_TexelSize.w * offset_multiplier)
        #endif
    #else
        uint4(_ScreenParams.x, _ScreenParams.y * height_multiplier, 0, _ScreenParams.y * offset_multiplier)
    #endif
    );
}

uint2 getIDPos(float3 position, uint seed, uint4 ID_SPACE_SIZE){
    uint2 hash = pcg4d_to_uint_2(uint4(asuint(position), seed)).xy;

    uint2 pixelCoord = hash % ID_SPACE_SIZE.xy; //Would be better to float2(hash) / 4294967295.0f; to avoid bias
    pixelCoord += ID_SPACE_SIZE.zw; //places this into the right spot on the screen
    return pixelCoord;
}

uint2 getIDPos(float3 position, uint seed, uint ID_SPACE){
    return getIDPos(position, seed, getIDSpace(ID_SPACE));
}

//Just use 1.255 for the IDs, hdr and non-hdr can handle it fine, just means that hdr can have more values still

float getMultiplier(){
    return 1.0/255.0;
    //return 1;
    //If using HDR, can read 
    #if defined(UNITY_HDR_ON)
        return 1.0;
    #else
        return 1.0/255.0;
    #endif
}

float getMultiplierDecode(){
    return 255.0;
    //return 1;
    //If using HDR, can read 
    #if defined(UNITY_HDR_ON)
        return 1.0;
    #else
        return 255.0;
    #endif
}

#endif