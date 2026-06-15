Shader "cubic/ops/grab/id_grabber"
{
    Properties
    {
        // No material properties needed. It runs entirely on screen-space logic.
    }
    
    SubShader
    {
        // Queue 400 (Background = 1000, so we subtract 600)
        Tags { "RenderType"="Opaque" "Queue"="Background-600" "DisableBatching"="True"}

        // 1. The Unnamed GrabPass: Snapshots the screen right before this shader runs.
        GrabPass { "_OPS_ID_HASH_TEXTURE" }

        Pass
        {
            // Make this invisible
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            //Possibly not needed
            #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                Texture2DArray _OPS_ID_HASH_TEXTURE;
            #else
                Texture2D _OPS_ID_HASH_TEXTURE;
            #endif

            struct appdata { float4 vertex : POSITION; };
            struct v2f { float4 pos : SV_POSITION; };

            v2f vert (appdata v) {
                v2f o;
                // Move off-screen or make it a single point so it doesn't draw
                o.pos = float4(0,0,0,0); 
                return o;
            }

            fixed4 frag (v2f i) : SV_Target { return 0; }
            ENDCG
        }
    }
}