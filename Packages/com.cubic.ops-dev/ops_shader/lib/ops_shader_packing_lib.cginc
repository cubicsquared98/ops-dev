#ifndef OPS_SHADER_PACKING
#define OPS_SHADER_PACKING

// Packs 32-bit float into a float4
float4 PackToFloat4(float v)
{
    // Reinterpret float as an unsigned 32-bit integer
    uint bits = asuint(v);
    
    // Extract four 8-bit chunks using bitwise shifts and masks
    uint r = (bits >> 24) & 0xFF;
    uint g = (bits >> 16) & 0xFF;
    uint b = (bits >> 8)  & 0xFF;
    uint a = bits         & 0xFF;
    
    // Normalize to -1 to 1 range
    return float4(r, g, b, a) / 255.0;
}
// Packs 32-bit uint into a float4
float4 PackToFloat4(uint v)
{  
    // Extract four 8-bit chunks using bitwise shifts and masks
    uint r = (v >> 24) & 0xFF;
    uint g = (v >> 16) & 0xFF;
    uint b = (v >> 8)  & 0xFF;
    uint a = v         & 0xFF;
    
    // Normalize to -1 to 1 range
    float4 value = float4(r, g, b, a) * 0.00392156862;
    return value;
}
// packs 4 uints (0-255) into float4
float4 PackToFloat4(uint4 v)
{
    return float4(v) / 255.0;
}

// Unpacks a float4 back into the exact original 32-bit float
float UnpackFloat4ToFloat(float4 color)
{
    // Denormalize into 0-255 integer range.
    // NOTE: Using round() is needed. It ensures that any minor floating-point drift from reading a 16-bit texture maps perfectly back to the exact whole integer byte.
    uint4 bytes = (uint4)round(color * 255.0);
    
    // Shift the bytes back into their original 32-bit positions
    uint bits = (bytes.x << 24) | (bytes.y << 16) | (bytes.z << 8) | bytes.w;
    
    // Reinterpret the 32-bit integer back into a float
    return asfloat(bits);
}

// Unpacks a float4 back into the exact original 32-bit uint
uint UnpackFloat4ToUint(float4 color)
{
    // Denormalize into 0-255 integer range.
    // NOTE: Using round() is needed. It ensures that any minor floating-point drift from reading a 16-bit texture maps perfectly back to the exact whole integer byte.
    uint4 bytes = uint4(round(color * 255.0));
    
    // Shift the bytes back into their original 32-bit positions
    uint bits = (bytes.r << 24) | (bytes.g << 16) | (bytes.b << 8) | bytes.a;

    return bits;
}

// packs 4 uints (0-255) into float4
uint4 UnpackFloat4ToUint4(float4 color){
    return uint4(round(color*255.0));
}

#endif