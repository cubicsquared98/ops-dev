#ifndef OPS_SHADER_READER
#define OPS_SHADER_READER

#include "ops_shader_packing_lib.cginc"

// Definitions to declare OPS_TEXTURE for use
#ifdef SHADER_TARGET_SURFACE_ANALYSIS
    sampler2D _OPS_GRAB_TEXTURE;
#else
    #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
        Texture2DArray _OPS_GRAB_TEXTURE;
    #else
        Texture2D _OPS_GRAB_TEXTURE;
    #endif
#endif


float4 _OPS_GRAB_TEXTURE_TexelSize;

bool _OPS_TextureExists(){
    #ifdef SHADER_TARGET_SURFACE_ANALYSIS
        return false;
    #else
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            uint width, height, elements;
            _OPS_GRAB_TEXTURE.GetDimensions(width, height, elements);
        #else
            uint width, height;
            _OPS_GRAB_TEXTURE.GetDimensions(width, height);
        #endif
        return width > 16;
    #endif
}

//Assume we are always reading/writing to one eye, so when reading read using first eye
float4 readDataFrom(uint2 pos)
{
    int x = pos.x;
    int y = pos.y;

    //To account for being on second screen / eye
    // #if UNITY_SINGLE_PASS_STEREO && !(defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED))
    //     x += (uint)(unity_StereoEyeIndex * (_OPS_GRAB_TEXTURE_TexelSize.z * 0.5));
    // #endif

    //IF UNITY_SINGLE_PASS_STEREO, THEN the texture is 2x wider / both eyes are squished into one texture. !!IT IS NOT a Texture2DArray!!

    // On modern APIs (DX, Metal, Vulkan), texture memory starts at the Top-Left.
    // On older APIs (OpenGL), texture memory starts at the Bottom-Left.
    // We flip the Y coordinate based on the API to normalize it.
    #if UNITY_UV_STARTS_AT_TOP
        // _TexelSize.w contains the actual height of the texture in pixels.
        // We subtract 1 because a 1024 texture goes from index 0 to 1023.
        y = (int)_OPS_GRAB_TEXTURE_TexelSize.w - 1 - y;
    #endif

    #ifdef SHADER_TARGET_SURFACE_ANALYSIS
        return float4(0,0,0,0);
    #else
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            // VR Texture2DArray: Load(int4(x, y, slice, mipLevel))
            return _OPS_GRAB_TEXTURE.Load(int4(x, y, unity_StereoEyeIndex, 0));
        #else
            // Desktop Texture2D: Load(int3(x, y, mipLevel))
            return _OPS_GRAB_TEXTURE.Load(int3(x, y, 0));
        #endif
    #endif
}




float readInlineFloatData(uint offset, uint _ID)
{
    return UnpackFloat4ToFloat(readDataFrom(float2(offset, _ID)));
}

float2 readInlineFloat2Data(uint offset, uint _ID)
{
    return float2(
        UnpackFloat4ToFloat(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 1, _ID)))
    );
}

float3 readInlineFloat3Data(uint offset, uint _ID)
{
    return float3(
        UnpackFloat4ToFloat(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 1, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 2, _ID)))
    );
}

float4 readInlineFloat4Data(uint offset, uint _ID)
{
    return float4(
        UnpackFloat4ToFloat(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 1, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 2, _ID))),
        UnpackFloat4ToFloat(readDataFrom(float2(offset + 3, _ID)))
    );
}

uint readInlineUintData(uint offset, uint _ID)
{
    return UnpackFloat4ToUint(readDataFrom(float2(offset, _ID)));
}

uint2 readInlineUint2Data(uint offset, uint _ID)
{
    return uint2(
        UnpackFloat4ToUint(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 1, _ID)))
    );
}

uint3 readInlineUint3Data(uint offset, uint _ID)
{
    return uint3(
        UnpackFloat4ToUint(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 1, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 2, _ID)))
    );
}

uint4 readInlineUint4Data(uint offset, uint _ID)
{
    return uint4(
        UnpackFloat4ToUint(readDataFrom(float2(offset, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 1, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 2, _ID))),
        UnpackFloat4ToUint(readDataFrom(float2(offset + 3, _ID)))
    );
}

#endif