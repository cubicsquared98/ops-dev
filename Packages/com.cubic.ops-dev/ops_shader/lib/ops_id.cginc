#ifndef _OPS_ID_HASH_TEXTURE_Exists

#define _OPS_ID_HASH_TEXTURE_Exists

// Definitions to declare OPS_TEXTURE for use
#ifdef SHADER_TARGET_SURFACE_ANALYSIS
    sampler2D _OPS_ID_HASH_TEXTURE;
#else
    #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
        Texture2DArray _OPS_ID_HASH_TEXTURE;
    #else
        Texture2D _OPS_ID_HASH_TEXTURE;
    #endif
#endif


float4 _OPS_ID_HASH_TEXTURE_TexelSize;

bool _OPS_ID_TextureExists(){
    #ifdef SHADER_TARGET_SURFACE_ANALYSIS
        return false;
    #else
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            uint width, height, elements;
            _OPS_ID_HASH_TEXTURE.GetDimensions(width, height, elements);
        #else
            uint width, height;
            _OPS_ID_HASH_TEXTURE.GetDimensions(width, height);
        #endif
        return width > 16;
    #endif
}

#include "ops_id_utils.cginc"

//Read from a position on the screen, IF UNITY_SINGLE_PASS_STEREO then only read/write to first eye
float4 readDataFrom_ID_TEX(uint2 pos)
{
    uint x = pos.x;
    uint y = pos.y;

    //Commented out so only reading/writing to first eye
    // //To account for being on second screen / eye
    // #if UNITY_SINGLE_PASS_STEREO && !(defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED))
    //     x += (uint)(unity_StereoEyeIndex * (_OPS_ID_HASH_TEXTURE_TexelSize.z * 0.5));
    // #endif

    #if UNITY_UV_STARTS_AT_TOP
        // _TexelSize.w contains the actual height of the texture in pixels.
        // We subtract 1 because a 1024 texture goes from index 0 to 1023.
        //y = (int)_OPS_ID_HASH_TEXTURE_TexelSize.w - 1 - y;
    #endif

    #ifdef SHADER_TARGET_SURFACE_ANALYSIS
        return float4(0,0,0,0);
    #else
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            return _OPS_ID_HASH_TEXTURE.Load(int4(x, y, unity_StereoEyeIndex, 0));
        #else
            return _OPS_ID_HASH_TEXTURE.Load(int3(x, y, 0));
        #endif
    #endif
}

//Gets ID from the screen, corrected for UNITY_SINGLE_PASS_STEREO.
uint getID(float3 position, uint seed, float DistanceToCamera, uint ID_SPACE){

    //If using two eyes, unity_StereoWorldSpaceCameraPos[stero_index] will give camera position per eye


    // float x_dimension = _OPS_ID_HASH_TEXTURE_TexelSize.z;

    // // If using Single Pass Stereo (Double-Wide), the logical width for ONE eye is half the texture width.
    // #if UNITY_SINGLE_PASS_STEREO && !(defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED))
    //     x_dimension *= 0.5;
    // #endif

    // //Full screen width, half the height
    // uint2 ID_SPACE_SIZE = uint2(x_dimension, _OPS_ID_HASH_TEXTURE_TexelSize.w * 0.5f);

    if(ID_SPACE == ID_SPACE_AVATAR){
        //round number to nearest mm
        const float rounding_point = 100; //10mm instead of 1mm (1cm)
        position = round(position * rounding_point) / rounding_point;
        position = (position == 0.0) ? 0.0 : position;
    }

    // // Convert float to exact IEEE 754 bits
    // uint bits = asuint(position);

    // //Mask out / round the last 4 bits -> prevent small mathematical errors with positioning
    // // Add half the threshold (8) to force a carry-over if the bottom bits are 8 or higher,
    // // then mask out the bottom 4 bits to snap it perfectly.
    // //bits = (bits + 0x00000008) & 0xFFFFFFF0;
    // bits = (bits + 0x00000010) & 0xFFFFFFE0;
    // //bits = (bits + 0x00000020) & 0xFFFFFFC0;
    // // Convert back to float so the visual 7-segment display matches the new rounded bits
    // position = asfloat(bits);


    uint4 ID_SPACE_SIZE = getIDSpace(ID_SPACE);
    
    uint2 pixelCoord = getIDPos(position, seed, ID_SPACE_SIZE);
    float4 read_value = readDataFrom_ID_TEX(pixelCoord);

    uint2 next_pixel_Coord = pixelCoord;
    next_pixel_Coord.x += 1;
    //Make sure the pixel correctly wraps around
    next_pixel_Coord.y = next_pixel_Coord.y + (next_pixel_Coord.x >= ID_SPACE_SIZE.x + ID_SPACE_SIZE.z ? 1 : 0);
    next_pixel_Coord.x = (next_pixel_Coord.x < ID_SPACE_SIZE.x + ID_SPACE_SIZE.z) ? next_pixel_Coord.x : ID_SPACE_SIZE.z;

    float4 next_value = 0;
    if(next_pixel_Coord.y < (ID_SPACE_SIZE.y + ID_SPACE_SIZE.w)){
        //If we are processing the very bottom corner of the ID_SPACE, we dont fetch the next value and instead assume 0;
        next_value = readDataFrom_ID_TEX(next_pixel_Coord);
    }

    float multiplier = getMultiplierDecode();

    int currentID = round(read_value.r * multiplier); //May need a rounding funct here, but probs not needed with limits of 2048 or 256
    int ID_AHEAD = round(next_value.r * multiplier);

    int overlaps = currentID - ID_AHEAD;

    DistanceToCamera = (half)DistanceToCamera; //decapitate some of the bits
    //if(read_value.g < DistanceToCamera){
    //Really we just wanna check to make sure this actually holds and ID
    if(!(read_value.b > 0.0f)){
        return 0;
    }

    int myRank = 0;

    //Collision detection *only* works when HDR is enabled, technically can work in non-hdr, but limited to 8 bit floats

    // 2-Way Collision (Sum > 2 * myDist)
    if (overlaps == 2) //Should be quite rare
    {
        float distSum = read_value.g;
        if (distSum > 2.0 * DistanceToCamera)
        {
            myRank = 1; //The other value has a higher distance.
        }
    }
    // 3-Way Collision (Quadratic Solver)
    else if (overlaps == 3) //Should be impossibly rare
    {
        float S_total = read_value.g; //Read the sum of distances
        float Q_total = read_value.b; //Read the sum of squared distances
        if (!(isinf(Q_total) || Q_total > 65000.0 || isinf(S_total)))
        {

            float myDistSq = DistanceToCamera * DistanceToCamera;

            float S = S_total - DistanceToCamera;
            float Q = Q_total - myDistSq;

            float discriminant = max(0.0, 2.0 * Q - (S * S));
            float root = sqrt(discriminant);
            
            float otherDist1 = (S - root) * 0.5;
            float otherDist2 = (S + root) * 0.5;

            if (DistanceToCamera > otherDist1) myRank++;
            if (DistanceToCamera > otherDist2) myRank++;
        }
    }

    currentID += myRank;

    return currentID;

    //IF overlaps is less than 1, then something has gone wrong
    //OR it means we area reading from the last pixel on the screen, and the ID_AHEAD has wrappd around to the start.
    //IN this case, we can just check if the number is larger than 1.

}


#endif