Shader "cubic/ops/tools/ID_GrabPass_Visualizer"
{
    Properties
    {
        // No properties needed, it just shows the global capture
    }
    
    SubShader
    {
        // Render in the Overlay or late Transparent queue so it's always visible
        Tags { "RenderType"="Opaque" "Queue"="Geometry"}

        // Link to your existing capture
        GrabPass { "_OPS_ID_HASH_TEXTURE" }

        Pass
        {
            ZTest Always
            ZWrite on
            Cull Back
            Blend Off // Pure overwrite for clear debugging

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"

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
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // Declare based on VR vs Desktop
            #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                Texture2DArray _OPS_ID_HASH_TEXTURE;
            #else
                Texture2D _OPS_ID_HASH_TEXTURE;
            #endif

            SamplerState sampler_PointClamp;

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT( v2f, o );
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv; // Use the quad's standard UVs

                // --- EDITOR / DX11 FIX ---
                // In some APIs, the screen texture is inverted. 
                // This ensures the visualizer isn't upside down in the Editor.
                // #if UNITY_UV_STARTS_AT_TOP
                // if (_ProjectionParams.x < 0 && _ProjectionParams.y < 0)
                //     o.uv.y = 1.0 - o.uv.y;
                // #endif

                //o.uv.y = 1.0 - o.uv.y;

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float4 col;
                #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                    // Sample the eye slice using the quad's UV coordinates
                    col = _OPS_ID_HASH_TEXTURE.Sample(sampler_PointClamp, float3(i.uv, unity_StereoEyeIndex));
                #else
                    col = _OPS_ID_HASH_TEXTURE.Sample(sampler_PointClamp, i.uv);
                #endif

                // If the data is tiny (1 pixel), it might be hard to see. 
                // We return the color as-is.
                return col;
            }
            ENDCG
        }
    }
}