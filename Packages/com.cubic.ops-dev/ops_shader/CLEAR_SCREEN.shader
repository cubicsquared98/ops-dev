Shader "cubic/ops/FullscreenWriteZero_Geom"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Background-680" }
        
        // Force replace background with 0,0,0,0
        Blend Off
        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                // We don't actually need the input vertex position 
                // because the geometry shader will generate new ones.
                o.vertex = v.vertex;
                return o;
            }

            // [maxvertexcount(4)] tells the GPU we are outputting 4 vertices (a quad)
            [maxvertexcount(4)]
            void geom(point v2f input[1], uint id : SV_PrimitiveID, inout TriangleStream<v2f> tristream)
            {
                // ONLY run the generation logic for the very first primitive (ID 0)
                if (id == 0)
                {
                    v2f o;

                    // Bottom-Left
                    o.vertex = float4(-1, -1, 0, 1);
                    tristream.Append(o);

                    // Top-Left
                    o.vertex = float4(-1, 1, 0, 1);
                    tristream.Append(o);

                    // Bottom-Right
                    o.vertex = float4(1, -1, 0, 1);
                    tristream.Append(o);

                    // Top-Right
                    o.vertex = float4(1, 1, 0, 1);
                    tristream.Append(o);

                    tristream.RestartStrip();
                }
            }

            fixed4 frag (v2f i) : SV_Target
            {
                return fixed4(0, 0, 0, 0);
            }
            ENDCG
        }
    }
}