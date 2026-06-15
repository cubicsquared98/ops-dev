Shader "cubic/ops/ops_ID_writer_vert"
{
    Properties
    {
        [Enum(orifice, 0, penetrator, 1, avatar, 2, animator, 3)] _ID_SPACE("ID_SPACE", Int) = 0
        _HASH_SEED ("Hash seed INTEGER", Int) = 0
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Background-610"}

        Pass
        {
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One One

            CGPROGRAM
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "../lib/ops_shader_defines.cginc"
            #include "../lib/ops_shader_packing_lib.cginc"
            #include "../lib/ops_id_utils.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                nointerpolation float4 colorData : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(uint, _ID_SPACE)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HASH_SEED)
            UNITY_INSTANCING_BUFFER_END(Props)

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                if (_ScreenParams.x <= 1.0 || _ScreenParams.y <= 1.0) {
                    o.vertex = float4(0, 0, 0, 0); 
                    return o; 
                }

                //Gets the vertex ID
                uint vid = (uint)(v.uv.x + 0.1); //0.1 here to fix rounding issues when flooring

                float3 worldPos = float3(UNITY_MATRIX_M._m03, UNITY_MATRIX_M._m13, UNITY_MATRIX_M._m23);
                
                uint ID_SPACE = UNITY_ACCESS_INSTANCED_PROP(Props, _ID_SPACE);
                if(ID_SPACE == ID_SPACE_AVATAR){
                    const float rounding_point = 100;
                    worldPos = round(worldPos * rounding_point) / rounding_point;
                    worldPos = (worldPos == 0.0) ? 0.0 : worldPos;
                }

                // // Convert float to exact IEEE 754 bits
                // uint bits = asuint(worldPos);

                // //Mask out / round the last 4 bits -> prevent small mathematical errors with positioning
                // // Add half the threshold (8) to force a carry-over if the bottom bits are 8 or higher,
                // // then mask out the bottom 4 bits to snap it perfectly.
                // // bits = (bits + 0x00000008) & 0xFFFFFFF0;
                // bits = (bits + 0x00000010) & 0xFFFFFFE0;
                // //bits = (bits + 0x00000020) & 0xFFFFFFC0;
                // // Convert back to float so the visual 7-segment display matches the new rounded bits
                // worldPos = asfloat(bits);

                uint4 ID_SPACE_SIZE = getIDSpace(ID_SPACE);
                uint hash_seed = UNITY_ACCESS_INSTANCED_PROP(Props, _HASH_SEED);
                
                uint2 ID_POS = getIDPos(worldPos, hash_seed, ID_SPACE_SIZE);
                float2 pixelSizeClip = 2.0f / _ScreenParams.xy;

                //Gets the specific quad based on vertexID
                uint quad = vid / 4; // Returns 0, 1, 2
                float left, right, bottom, top;
                float dist = 0;

                //First quad is a single pixel big
                if (quad == 0) 
                {
                    left   = -1.0 + (ID_POS.x * pixelSizeClip.x);
                    right  = -1.0 + ((ID_POS.x + 1.0) * pixelSizeClip.x);
                    bottom = 1.0 - (ID_POS.y * pixelSizeClip.y);
                    top    = 1.0 - ((ID_POS.y + 1.0) * pixelSizeClip.y);
                    dist = distance(_WorldSpaceCameraPos, worldPos);
                }
                //Second quad fills in from the first to the left of the screen
                else if (quad == 1) 
                {
                    left   = -1.0 + (ID_SPACE_SIZE.z * pixelSizeClip.x);
                    right  = -1.0 + (ID_POS.x * pixelSizeClip.x); // Original logic: rightEdge_1 = leftEdge
                    bottom = 1.0 - (ID_POS.y * pixelSizeClip.y);
                    top    = 1.0 - ((ID_POS.y + 1.0) * pixelSizeClip.y);
                }
                //Third quad fills the remaining space below the line
                else // quad == 2
                {
                    left   = -1.0 + (ID_SPACE_SIZE.z * pixelSizeClip.x);
                    right  = -1.0 + ((ID_SPACE_SIZE.z + ID_SPACE_SIZE.x) * pixelSizeClip.x);
                    bottom = 1.0 - (ID_SPACE_SIZE.w * pixelSizeClip.y);
                    top    = 1.0 - (ID_POS.y * pixelSizeClip.y); // Original logic: topEdge_2 = bottomEdge
                }

                // bit 1 (val 2) checks if it's the right side. bit 0 (val 1) checks if it's the top side.
                float xPos = (vid & 2) ? right : left; 
                float yPos = (vid & 1) ? top : bottom;
                float2 finalPos = float2(xPos, yPos);

                float rValue = getMultiplier();
                float4 finalColor = float4(rValue, dist, dist * dist, 0.0);

                o.colorData = finalColor;
                o.vertex = float4(finalPos, 0.5, 1.0);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                return i.colorData;
            }
            ENDCG
        }
    }
}