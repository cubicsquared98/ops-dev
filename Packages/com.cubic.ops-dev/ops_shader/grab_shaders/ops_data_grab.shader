Shader "cubic/ops/grab/data_grabber"
{
    Properties
    {
        // No material properties needed. It runs entirely on screen-space logic.
    }
    
    SubShader
    {
        // Queue 500 (Background = 1000, so we subtract 500)
        Tags { "RenderType"="Opaque" "Queue"="Background-500" "DisableBatching"="True" }

        GrabPass { "_OPS_GRAB_TEXTURE" }

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

            #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                Texture2DArray _OPS_GRAB_TEXTURE;
            #else
                Texture2D _OPS_GRAB_TEXTURE;
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