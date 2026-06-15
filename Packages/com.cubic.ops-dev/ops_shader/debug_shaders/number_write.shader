Shader "cubic/ops/tools/orifice_debug_reader"
{
    Properties
    {
        _ID ("Channel to read", Int) = 0
        _IntDigits ("Integer Digits", Range(1, 6)) = 2
        _DecDigits ("Decimal Digits", Range(0, 4)) = 2
        _Color ("Text Color", Color) = (0, 1, 0, 1)
        _BgColor ("Background Color", Color) = (0, 0, 0, 1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        // GrabPass { "_OPS_GRAB_TEXTURE" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            #include "../lib/ops_shader_defines.cginc"
            #include "../lib/ops_shader_reader_lib.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(int, _ID)
                UNITY_DEFINE_INSTANCED_PROP(int, _IntDigits)
                UNITY_DEFINE_INSTANCED_PROP(int, _DecDigits)
                UNITY_DEFINE_INSTANCED_PROP(float4, _Color)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BgColor)
            UNITY_INSTANCING_BUFFER_END(Props)


            
            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // Returns a 15-bit mask for a 3x5 digit grid
            int GetDigitMask(int digit)
            {
                switch(digit)
                {
                    case 0: return 31599; // 111 101 101 101 111
                    case 1: return 9362;  // 010 010 010 010 010
                    case 2: return 29671; // 111 001 111 100 111
                    case 3: return 29327; // 111 001 111 001 111
                    case 4: return 23497; // 101 101 111 001 001
                    case 5: return 31183; // 111 100 111 001 111
                    case 6: return 31215; // 111 100 111 101 111
                    case 7: return 29257; // 111 001 001 001 001
                    case 8: return 31727; // 111 101 111 101 111
                    case 9: return 31711; // 111 101 111 001 111
                    case 10: return 2;    // Decimal point (Bottom-center pixel)
                    case 11: return 448;  // Minus sign (middle row only)
                    case 12: return 0;    // Blank space
                    default: return 0;
                }
            }

            // Draws a single digit in the 0-1 UV space
// Draws a single digit in the 0-1 UV space
            float DrawSingleDigit(float2 uv, int digit)
            {
                // Clip out of bounds
                if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;

                // FLIP THE X-AXIS FOR THE DIGIT ONLY
                uv.x = 1.0 - uv.x;

                // Divide into 3x5 grid
                int x = floor(uv.x * 3.0);
                int y = floor(uv.y * 5.0);
                
                // Find the specific pixel bit (0 to 14)
                int bitIndex = y * 3 + x;
                int mask = GetDigitMask(digit);

                // Check if the bit is turned on
                return (mask >> bitIndex) & 1;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                if(!_OPS_TextureExists()){
                    return float4(0,0,0,0);
                }

                // Read all data streams
                float3 values   = readInlineFloat3Data(offset_Orafice_world_pos, _ID);
                float3 values_2 = readInlineFloat3Data(offset_Orafice_world_forward_vec, _ID);
                float3 values_3 = readInlineFloat3Data(offset_Orafice_world_up_vec, _ID);
                float  value4   = readInlineUintData(offset_Orafice_avatar_id, _ID);

                int intDigits   = UNITY_ACCESS_INSTANCED_PROP(Props, _IntDigits);
                int decDigits   = UNITY_ACCESS_INSTANCED_PROP(Props, _DecDigits);
                float4 textColor = UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                float4 bgColor   = UNITY_ACCESS_INSTANCED_PROP(Props, _BgColor);

                float2 uv = i.uv;
                
                // --- FIX: SPLIT INTO 10 ROWS INSTEAD OF 9 ---
                uv.y *= 10.0;
                int currentRow = floor(uv.y); 
                uv.y = frac(uv.y);            

                // Determine which number to draw based on the row (0-9)
                float rawVal = 0;
                if      (currentRow == 9) rawVal = value4;      // The 10th value
                else if (currentRow == 8) rawVal = values_3.x;      
                else if (currentRow == 7) rawVal = values_3.y; 
                else if (currentRow == 6) rawVal = values_3.z; 
                else if (currentRow == 5) rawVal = values_2.x; 
                else if (currentRow == 4) rawVal = values_2.y; 
                else if (currentRow == 3) rawVal = values_2.z; 
                else if (currentRow == 2) rawVal = values.x; 
                else if (currentRow == 1) rawVal = values.y; 
                else                      rawVal = values.z; 
                
                // ... (The rest of your sign and digit drawing logic remains the same) ...
                
                bool isNegative = rawVal < 0.0;
                float val = abs(rawVal); 
                
                int totalSlots = 1 + intDigits + (decDigits > 0 ? decDigits + 1 : 0);

                uv.x *= totalSlots;
                int currentSlot = floor(uv.x); 
                uv.x = frac(uv.x); 
                
                uv.x = (uv.x - 0.1) * 1.25; 
                uv.y = (uv.y - 0.1) * 1.25;

                int digitToDraw = 12; 

                if (currentSlot == 0)
                {
                    if (isNegative) digitToDraw = 11; 
                    else digitToDraw = 12;
                }
                else if (currentSlot <= intDigits) 
                {
                    int intSlot = currentSlot - 1; 
                    float power = pow(10.0, float((intDigits - 1) - intSlot));
                    digitToDraw = int(floor((val / power) + 0.0001)) % 10;
                } 
                else if (currentSlot == intDigits + 1) 
                {
                    digitToDraw = 10; 
                } 
                else 
                {
                    int decIndex = currentSlot - (intDigits + 1); 
                    float multiplier = pow(10.0, float(decIndex));
                    float fraction = frac(val); 
                    float shifted = fraction * multiplier;
                    digitToDraw = int(floor(shifted + 0.0001)) % 10; 
                }

                float pixelValue = DrawSingleDigit(uv, digitToDraw);

                return lerp(bgColor, textColor, pixelValue);
            }
            ENDCG
        }
    }
}