Shader "cubic/ops/OpsPenetrator_writer"
{
    //World position of skinned mesh this is attached to must be the same as the penetrator
    //Place root bone of the skinned mesh this is on to line up with SPS penetrator, so that start point, end point and radius match

    Properties
    {
        _ID ("Channel to write to if auto-channel is disabled", Int) = 0
        _HASH_SEED ("Hash seed INTEGER", Int) = 0
        _HASH_SEED_AVI_ID ("Hash seed AVI ID INTEGER", Int) = 0
        _OVERRIDE_USE_ID ("OVERRIDE AUTO ID (1 = enable)", Int) = 0
        _OpsPenetrator_GLOW_COLOR ("Color", Color) = (0,0,0,0)
        _OpsPenetrator_EMISSION_STRENGTH ("Emission strength", Float) = 0
        _OpsPenetrator_AVOID_ON_SELF_MASK ("Avoid on self mask (Must be higher than -1)", Int) = -1
        _OPS_ID_CHANNEL("OPS Channel (to select set higher than -1)", Int) = -1
        _OPS_SKINNED_BONES_OFFSET("Starting ID to write bone scaling data", Int) = 0
        [Enum(Disabled, 0, Enabled, 1)] _OPS_SKINNED_BONES_ENABLED("enables skinned bones mode", Int) = 0
        [Enum(Disabled, 0, Enabled, 1)] _OPS_FROT_MODE("enables frot mode", Int) = 0
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Background-510" "DisableBatching"="True"}

        Pass
        {
            ZTest Always   // Draw even if blocked by geometry
            ZWrite Off     // Don't mess up the depth buffer
            Cull Off       // Draw both sides
            Blend Off      // No blending

            //This makes it so that when writing, closest - to - furthest (queue < 2500), any further away components with the same ID will not overwrite.
            Stencil {
                Ref 17
                Comp NotEqual
                Pass Replace
            }

            CGPROGRAM
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "../lib/ops_shader_defines.cginc"
            #include "../lib/ops_shader_packing_lib.cginc"
            #include "../lib/ops_id.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                uint VertexId : SV_VertexID;           
                UNITY_VERTEX_INPUT_INSTANCE_ID // Required for VR
            };

            struct v2g
            {
                float4 vertex : POSITION;
                uint VertexId : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                uint OpsPenetrator_ID : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
                float4 dataValue : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO     // Required for VR
            };

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _ID)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HASH_SEED)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HASH_SEED_AVI_ID)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OVERRIDE_USE_ID)
                UNITY_DEFINE_INSTANCED_PROP(float,  _OpsPenetrator_EMISSION_STRENGTH)
                UNITY_DEFINE_INSTANCED_PROP(int,    _OPS_ID_CHANNEL)
                UNITY_DEFINE_INSTANCED_PROP(int,    _OpsPenetrator_AVOID_ON_SELF_MASK)
                UNITY_DEFINE_INSTANCED_PROP(float4, _OpsPenetrator_GLOW_COLOR)
                UNITY_DEFINE_INSTANCED_PROP(uint,   _OPS_SKINNED_BONES_OFFSET)
                UNITY_DEFINE_INSTANCED_PROP(uint,   _OPS_SKINNED_BONES_ENABLED)
                UNITY_DEFINE_INSTANCED_PROP(uint,   _OPS_FROT_MODE)
            UNITY_INSTANCING_BUFFER_END(Props)

            v2g vert (appdata v)
            {
                v2g o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2g, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float3 worldObjectPos = float3(unity_ObjectToWorld._m03, unity_ObjectToWorld._m13, unity_ObjectToWorld._m23);

                float distance_to_camera = distance(_WorldSpaceCameraPos, worldObjectPos);

                uint override_ID = UNITY_ACCESS_INSTANCED_PROP(Props, _OVERRIDE_USE_ID);
                if(_OPS_ID_TextureExists() && override_ID != 1){
                    uint Hash_seed = UNITY_ACCESS_INSTANCED_PROP(Props, _HASH_SEED);
                    o.OpsPenetrator_ID = getID(worldObjectPos, Hash_seed, distance_to_camera, ID_SPACE_PENETRATOR);
                }
                else{
                    o.OpsPenetrator_ID = UNITY_ACCESS_INSTANCED_PROP(Props, _ID);
                }

                o.VertexId = v.VertexId;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.vertex = v.vertex;

                return o;
            }

            [maxvertexcount(Total_written_penetrator_values_p1*4)] 
            void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream, uint triID : SV_PrimitiveID)
            {
                UNITY_SETUP_INSTANCE_ID(input[0]);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);

                if (_ScreenParams.x <= 1.0 || _ScreenParams.y <= 1.0 || !_OPS_ID_TextureExists()) {
                    return;
                }

                float4 values[Total_written_penetrator_values_p1];

                //The generic penetrator infomation is written here
                if(triID == 0){
                    //Technically speaking, these should be the right order.
                    float3 origin = input[0].worldPos.xyz;
                    float3 yPoint = input[1].worldPos.xyz;
                    float3 zPoint = input[2].worldPos.xyz;


                    float2 pixelSizeClip = 2.0 / _ScreenParams.xy;
                    float xStartOffset = -1.0; // Always -1.0!


                    // Calculate the exact Bottom and Top boundaries for this ID's row
                    float bottomEdge = -1.0 + (input[0].OpsPenetrator_ID * pixelSizeClip.y);
                    float topEdge    = -1.0 + ((input[0].OpsPenetrator_ID + 1.0) * pixelSizeClip.y);

                    // Array holding our X, Y, and Z data
                    values[offset_penetrator_is_active_p1] = PackToFloat4(1.0f);
                    values[offset_penetrator_world_start_point_x_p1] = PackToFloat4(origin.x);
                    values[offset_penetrator_world_start_point_y_p1] = PackToFloat4(origin.y);
                    values[offset_penetrator_world_start_point_z_p1] = PackToFloat4(origin.z);
                    values[offset_penetrator_world_end_point_x_p1] = PackToFloat4(zPoint.x);
                    values[offset_penetrator_world_end_point_y_p1] = PackToFloat4(zPoint.y);
                    values[offset_penetrator_world_end_point_z_p1] = PackToFloat4(zPoint.z);
                    values[offset_penetrator_world_radius_up_point_x_p1] = PackToFloat4(yPoint.x);
                    values[offset_penetrator_world_radius_up_point_y_p1] = PackToFloat4(yPoint.y);
                    values[offset_penetrator_world_radius_up_point_z_p1] = PackToFloat4(yPoint.z);
                    values[offset_penetrator_glow_color_rgb_p1] = UNITY_ACCESS_INSTANCED_PROP(Props, _OpsPenetrator_GLOW_COLOR);
                    values[offset_penetrator_emission_strength_p1] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OpsPenetrator_EMISSION_STRENGTH));
                    values[offset_penetrator_avoid_on_self_mask_p1] = PackToFloat4(float(UNITY_ACCESS_INSTANCED_PROP(Props, _OpsPenetrator_AVOID_ON_SELF_MASK)));
                    values[offset_penetrator_channel_id_p1] = PackToFloat4(float(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_ID_CHANNEL)));
                    values[offset_penetrator_bone_data_start_bone_index_p1] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_SKINNED_BONES_OFFSET));
                    values[offset_penetrator_bone_data_enabled_p1] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_SKINNED_BONES_ENABLED));
                    values[offset_penetrator_frot_mode_p1] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_FROT_MODE));

                    uint HalfAcrossScreen = _ScreenParams.x / 2;

                    // Loop x times to generate x quads
                    for(int i = Total_written_penetrator_values_p1_start; i < Total_written_penetrator_values_p1; i++)
                    {
                        //I want to cover the entire pixel, not just the center of it

                        // Calculate the exact Left and Right boundaries for this specific column
                        float leftEdge  = xStartOffset + ((HalfAcrossScreen + i) * pixelSizeClip.x);
                        float rightEdge = xStartOffset + ((HalfAcrossScreen + i + 1.0) * pixelSizeClip.x);

                        // Snap the 4 corners perfectly to the pixel's bounding box
                        float2 p0 = float2(leftEdge,  bottomEdge); // Bottom Left
                        float2 p1 = float2(leftEdge,  topEdge);    // Top Left
                        float2 p2 = float2(rightEdge, bottomEdge); // Bottom Right
                        float2 p3 = float2(rightEdge, topEdge);    // Top Right

                        g2f o;

                        UNITY_INITIALIZE_OUTPUT(g2f, o);
                        UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

                        o.dataValue = values[i]; // Assign X, Y, or Z to this quad

                        // Emit the 4 vertices to build a Triangle Strip
                        o.pos = float4(p0, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p1, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p2, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p3, 0.5, 1.0); triStream.Append(o);

                        // CRITICAL: Cut the strip so the next quad doesn't connect to this one
                        triStream.RestartStrip();
                    }
                }
                //The avatar center point is written here
                else if(triID == 1){
                    //Write avatar ID

                    uint Hash_seed = UNITY_ACCESS_INSTANCED_PROP(Props, _HASH_SEED_AVI_ID);

                    float3 origin = input[0].worldPos.xyz;

                    float distance_to_camera = distance(_WorldSpaceCameraPos, origin);
                    uint AVATAR_ID = getID(origin, Hash_seed, distance_to_camera, ID_SPACE_AVATAR);


                    float2 pixelSizeClip = 2.0 / _ScreenParams.xy;
                    float xStartOffset = -1.0; // Always -1.0!


                    // Calculate the exact Bottom and Top boundaries for this ID's row
                    float bottomEdge = -1.0 + (input[0].OpsPenetrator_ID * pixelSizeClip.y);
                    float topEdge    = -1.0 + ((input[0].OpsPenetrator_ID + 1.0) * pixelSizeClip.y);

                    // Array holding our X, Y, and Z data
                    values[offset_penetrator_avatar_id_p2] = PackToFloat4(AVATAR_ID);

                    uint HalfAcrossScreen = _ScreenParams.x / 2;

                    // Loop x times to generate x quads
                    for(int i = 0; i < Total_written_penetrator_values_p2; i++)
                    {
                        //I want to cover the entire pixel, not just the center of it

                        // Calculate the exact Left and Right boundaries for this specific column
                        float leftEdge  = xStartOffset + ((HalfAcrossScreen + Total_written_penetrator_values_p1 + i) * pixelSizeClip.x);
                        float rightEdge = xStartOffset + ((HalfAcrossScreen + Total_written_penetrator_values_p1 + i + 1.0) * pixelSizeClip.x);

                        // Snap the 4 corners perfectly to the pixel's bounding box
                        float2 p0 = float2(leftEdge,  bottomEdge); // Bottom Left
                        float2 p1 = float2(leftEdge,  topEdge);    // Top Left
                        float2 p2 = float2(rightEdge, bottomEdge); // Bottom Right
                        float2 p3 = float2(rightEdge, topEdge);    // Top Right

                        g2f o;

                        UNITY_INITIALIZE_OUTPUT(g2f, o);
                        UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

                        o.dataValue = values[i]; // Assign X, Y, or Z to this quad

                        // Emit the 4 vertices to build a Triangle Strip
                        o.pos = float4(p0, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p1, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p2, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p3, 0.5, 1.0); triStream.Append(o);

                        // CRITICAL: Cut the strip so the next quad doesn't connect to this one
                        triStream.RestartStrip();
                    }
                }
                //The scale of each bone - all other tri's are from bones the mesh is attached to, in order.
                //Might want to write a "starting bone index", as the root bone may be far from the pp bone.
                //We can presume that the bones used on the pp will be in order?
                else{
                    uint id = triID - 2;// + UNITY_ACCESS_INSTANCED_PROP(Props,_SKINNED_BONES_OFFSET);
                    //From this offset, we write the data from the bones that affect this section of the smr

                    //Should be able to use local space for this, but keep using known for now
                    float3 origin = input[0].worldPos.xyz;
                    float3 yPoint = input[1].worldPos.xyz;
                    float3 xPoint = input[2].worldPos.xyz;

                    float x_length = distance(origin, yPoint);//dist from 0,0,0 to what would be forward vert in above code;
                    float y_length = distance(origin, xPoint);//dist from 0,0,0 to what would be radius vert in above code;

                    values[dynamic_offset_penetrator_Bone_relative_radius_scale_x] = PackToFloat4(x_length);
                    values[dynamic_offset_penetrator_Bone_relative_radius_scale_y] = PackToFloat4(y_length);


                    float2 pixelSizeClip = 2.0 / _ScreenParams.xy;
                    float xStartOffset = -1.0; // Always -1.0!

                    // Calculate the exact Bottom and Top boundaries for this ID's row
                    float bottomEdge = -1.0 + (input[0].OpsPenetrator_ID * pixelSizeClip.y);
                    float topEdge    = -1.0 + ((input[0].OpsPenetrator_ID + 1.0) * pixelSizeClip.y);

                    uint HalfAcrossScreen = _ScreenParams.x / 2;

                    uint writingIndex = HalfAcrossScreen + (id * dynamic_offset_penetrator_Bone_data + Total_written_penetrator_values);

                    // Loop x times to generate x quads
                    for(int i = 0; i < dynamic_offset_penetrator_Bone_data; i++)
                    {
                        //I want to cover the entire pixel, not just the center of it

                        // Calculate the exact Left and Right boundaries for this specific column
                        float leftEdge  = xStartOffset + ((writingIndex + i) * pixelSizeClip.x);
                        float rightEdge = xStartOffset + ((writingIndex + i + 1.0) * pixelSizeClip.x);

                        // Snap the 4 corners perfectly to the pixel's bounding box
                        float2 p0 = float2(leftEdge,  bottomEdge); // Bottom Left
                        float2 p1 = float2(leftEdge,  topEdge);    // Top Left
                        float2 p2 = float2(rightEdge, bottomEdge); // Bottom Right
                        float2 p3 = float2(rightEdge, topEdge);    // Top Right

                        g2f o;

                        UNITY_INITIALIZE_OUTPUT(g2f, o);
                        UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

                        o.dataValue = values[i];

                        // Emit the 4 vertices to build a Triangle Strip
                        o.pos = float4(p0, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p1, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p2, 0.5, 1.0); triStream.Append(o);
                        o.pos = float4(p3, 0.5, 1.0); triStream.Append(o);

                        // CRITICAL: Cut the strip so the next quad doesn't connect to this one
                        triStream.RestartStrip();
                    }

                }



            }


            fixed4 frag (g2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                return i.dataValue;
            }
            ENDCG
        }
    }
}