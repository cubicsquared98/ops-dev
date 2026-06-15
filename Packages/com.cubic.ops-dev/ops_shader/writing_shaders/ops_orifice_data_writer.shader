Shader "cubic/ops/ops_orifice_writer"
{
    Properties
    {
        _ID ("Channel to writeto if auto-channel is disabled", Int) = 0
        [Enum(Hole,1, _Ring,2)] _HoleType("Hole Type", Int) = 1
        [Enum(One_Way,1, Two_Way,2)] _HoleEntryDirection("Entry Direction", Int) = 1
        [Enum(Center_Aligned,1, Radius_Aligned,2)] _HoleCenterAlignment("Hole Alignment", Int) = 1
        _OPS_LIGHTSOURCE_BACKUP_EXISTS("Legacy lightsource backup exists", Int) = 0
        _HASH_SEED ("Hash seed INTEGER", Int) = 0
        _HASH_SEED_AVI_ID ("Hash seed AVI ID INTEGER", Int) = 0
        _OVERRIDE_USE_ID ("OVERRIDE AUTO ID (1 = enable)", Int) = 0
        _DISABLE_HOLE_RECURSION ("Disable ring recursion", Int) = 0
        _OPS_CHANNEL_ID ("Selected channel (0 or higher)", Int) = -1
        _OPS_AVOID_ON_SELF ("Disable self interact (1 to enable)", Int) = 0
        _OPS_AVOID_SELF_MASK ("Enable self mask (Penetrator with corrosponding value on self will avoid (larger than -1))", Int) = -1
        _OPS_PATH_COUNT ("Amount of path components (keep this as short as you can, one or two is fine))", Int) = 0
        _OPS_PATH_HIDE_SEGMENTS ("Hide other path segments (Set to 1 to hide)", Int) = 0
        //_DataValue ("Value to Write (R Channel)", Range(0, 1)) = 1.0
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
                UNITY_VERTEX_INPUT_INSTANCE_ID // Required for VR
            };

            struct v2g
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 forwardDir : TEXCOORD1;
                float3 upDir : TEXCOORD2;
                uint OPS_ORIFICE_ID : TEXCOORD3;
                float3 worldPos_v : TEXCOORD4;
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
                UNITY_DEFINE_INSTANCED_PROP(uint, _HoleType)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HoleEntryDirection)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HoleCenterAlignment)
                UNITY_DEFINE_INSTANCED_PROP(uint, _DISABLE_HOLE_RECURSION)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HASH_SEED)
                UNITY_DEFINE_INSTANCED_PROP(uint, _HASH_SEED_AVI_ID)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OVERRIDE_USE_ID)
                UNITY_DEFINE_INSTANCED_PROP(int, _OPS_CHANNEL_ID)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OPS_AVOID_ON_SELF)
                UNITY_DEFINE_INSTANCED_PROP(int, _OPS_AVOID_SELF_MASK)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OPS_PATH_COUNT)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OPS_PATH_HIDE_SEGMENTS)
                UNITY_DEFINE_INSTANCED_PROP(uint, _OPS_LIGHTSOURCE_BACKUP_EXISTS)
            UNITY_INSTANCING_BUFFER_END(Props)


            v2g vert (appdata v)
            {
                v2g o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                //UNITY_INITIALIZE_OUTPUT(v2g, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.worldPos = float3(unity_ObjectToWorld._m03, unity_ObjectToWorld._m13, unity_ObjectToWorld._m23);

                float distance_to_camera = distance(_WorldSpaceCameraPos, o.worldPos);

                uint override_use_ID = UNITY_ACCESS_INSTANCED_PROP(Props, _OVERRIDE_USE_ID);
                if(_OPS_ID_TextureExists() && override_use_ID != 1){
                    uint hash_Seed = UNITY_ACCESS_INSTANCED_PROP(Props, _HASH_SEED);
                    o.OPS_ORIFICE_ID = getID(o.worldPos, hash_Seed, distance_to_camera, ID_SPACE_ORIFICE);
                }
                else{
                    o.OPS_ORIFICE_ID = UNITY_ACCESS_INSTANCED_PROP(Props, _ID);
                }
                o.worldPos_v = mul(unity_ObjectToWorld, v.vertex).xyz;


                //Forward Z axis
                o.forwardDir = normalize(float3(unity_ObjectToWorld._m02, unity_ObjectToWorld._m12, unity_ObjectToWorld._m22));
                //Up Y axis
                o.upDir = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));

                o.vertex = UnityObjectToClipPos(v.vertex);

                return o;
            }

            [maxvertexcount(Total_Orafice_Written_Values*4)] 
            void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream, uint triID : SV_PrimitiveID)
            {
                UNITY_SETUP_INSTANCE_ID(input[0]);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);

                if (_ScreenParams.x <= 1.0 || _ScreenParams.y <= 1.0 || !_OPS_ID_TextureExists()) {
                    return;
                }

                uint path_count = UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_PATH_COUNT);
                //triID 0 is offset at avi center
                //triID 1 is offset at hole / object location
                //triID > 1 is offset at path locations in order
                //max path locations count can be read from shader properties
                float4 values[Total_Orafice_Written_Values];
                if(triID == 1){
                    return;
                }
                else if(triID == 0){

                    uint Hash_seed = UNITY_ACCESS_INSTANCED_PROP(Props, _HASH_SEED_AVI_ID);
                    float3 avatar_center = input[0].worldPos_v;
                    float distance_to_camera = distance(_WorldSpaceCameraPos, avatar_center);
                    uint AVATAR_ID = getID(avatar_center, Hash_seed, distance_to_camera, ID_SPACE_AVATAR);

                    // uint4 ID_SPACE_SIZE = getIDSpace(ID_SPACE_AVATAR);
                    // uint2 pixelCoord = getIDPos(avatar_center, Hash_seed, ID_SPACE_SIZE);

                    // float4 read_value = readDataFrom_ID_TEX(pixelCoord);


                    // AVATAR_ID = AVATAR_ID;

                    // We only need to grab the position data once per triangle
                    float3 posToWrite = input[0].worldPos;
                    float3 dirToWrite = input[0].forwardDir;
                    float3 upDirToWrite = input[0].upDir;


                    float2 pixelSizeClip = 2.0f / _ScreenParams.xy;
                    float xStartOffset = -1.0; // Always -1.0!

                    // Calculate the exact Bottom and Top boundaries for this ID's row
                    float bottomEdge = -1.0 + (input[0].OPS_ORIFICE_ID * pixelSizeClip.y);
                    float topEdge    = -1.0 + ((input[0].OPS_ORIFICE_ID + 1.0) * pixelSizeClip.y);

                    uint4 ops_types = uint4(
                        UNITY_ACCESS_INSTANCED_PROP(Props, _HoleType),
                        UNITY_ACCESS_INSTANCED_PROP(Props, _HoleEntryDirection),
                        UNITY_ACCESS_INSTANCED_PROP(Props, _HoleCenterAlignment),
                        0
                    );

                    // Array holding our X, Y, and Z data
                    values[offset_Orafice_ID_BitWise_Booleans] = PackToFloat4(1.0);
                    values[offset_Orafice_world_pos_x] = PackToFloat4(posToWrite.x);
                    values[offset_Orafice_world_pos_y] = PackToFloat4(posToWrite.y);
                    values[offset_Orafice_world_pos_z] = PackToFloat4(posToWrite.z);
                    values[offset_Orafice_world_forward_vec_x] = PackToFloat4(dirToWrite.x);
                    values[offset_Orafice_world_forward_vec_y] = PackToFloat4(dirToWrite.y);
                    values[offset_Orafice_world_forward_vec_z] = PackToFloat4(dirToWrite.z);
                    values[offset_Orafice_world_up_vec_x] = PackToFloat4(upDirToWrite.x);
                    values[offset_Orafice_world_up_vec_y] = PackToFloat4(upDirToWrite.y);
                    values[offset_Orafice_world_up_vec_z] = PackToFloat4(upDirToWrite.z);
                    values[offset_Orafice_ops_type] = PackToFloat4(ops_types);
                    values[offset_Orafice_ops_disable_recursion] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _DISABLE_HOLE_RECURSION)); //UINT
                    values[offset_Orafice_channel_id] = PackToFloat4(float(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_CHANNEL_ID))); //INT -> converted to float for now
                    values[offset_Orafice_avatar_id] = PackToFloat4(AVATAR_ID); //UINT
                    values[offset_Orafice_avoid_on_self] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_AVOID_ON_SELF)); //UINT
                    values[offset_Orafice_avoid_on_self_mask] = PackToFloat4(float(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_AVOID_SELF_MASK))); //INT -> converted to float for now
                    values[offset_Orafice_dynamic_Path_Count] = PackToFloat4(path_count); //UINT

                    // Loop x times to generate x quads
                    for(int i = 0; i < Total_Orafice_Written_Values; i++)
                    {
                        //I want to cover the entire pixel, not just the center of it

                        // Calculate the exact Left and Right boundaries for this specific column
                        float leftEdge  = xStartOffset + (i * pixelSizeClip.x);
                        float rightEdge = xStartOffset + ((i + 1.0) * pixelSizeClip.x);

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
                else if(triID > 1 && triID < (path_count + 2)){
                    float2 pixelSizeClip = 2.0f / _ScreenParams.xy;
                    float xStartOffset = -1.0; // Always -1.0!

                    // Calculate the exact Bottom and Top boundaries for this ID's row
                    float bottomEdge = -1.0 + (input[0].OPS_ORIFICE_ID * pixelSizeClip.y);
                    float topEdge    = -1.0 + ((input[0].OPS_ORIFICE_ID + 1.0) * pixelSizeClip.y);


                    //Get index to write this path component at
                    uint writingIndex = (triID - 2) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values;

                    float3 CenterPoint =  input[0].worldPos_v;
                    float3 ForwardPoint = input[2].worldPos_v;
                    float3 UpwardPoint =  input[1].worldPos_v;


                    values[dynamic_offset_Orafice_Path_x] = PackToFloat4(CenterPoint.x);
                    values[dynamic_offset_Orafice_Path_y] = PackToFloat4(CenterPoint.y);
                    values[dynamic_offset_Orafice_Path_z] = PackToFloat4(CenterPoint.z);
                    values[dynamic_offset_Orafice_Path_forward_vec_x] = PackToFloat4(ForwardPoint.x - CenterPoint.x); //Size of direction vector is included
                    values[dynamic_offset_Orafice_Path_forward_vec_y] = PackToFloat4(ForwardPoint.y - CenterPoint.y);
                    values[dynamic_offset_Orafice_Path_forward_vec_z] = PackToFloat4(ForwardPoint.z - CenterPoint.z);
                    values[dynamic_offset_Orafice_Path_up_vec_x] = PackToFloat4(UpwardPoint.x - CenterPoint.x);
                    values[dynamic_offset_Orafice_Path_up_vec_y] = PackToFloat4(UpwardPoint.y - CenterPoint.y);
                    values[dynamic_offset_Orafice_Path_up_vec_z] = PackToFloat4(UpwardPoint.z - CenterPoint.z);
                    values[dynamic_offset_Orafice_Path_hide_segment] = PackToFloat4(UNITY_ACCESS_INSTANCED_PROP(Props, _OPS_PATH_HIDE_SEGMENTS)); //UINT
                
                    // Loop x times to generate x quads
                    for(int i = 0; i < dynamic_offset_Orafice_Per_Path; i++)
                    {
                        // Calculate the exact Left and Right boundaries for this specific column
                        float leftEdge  = xStartOffset + (float(writingIndex + i) * pixelSizeClip.x);
                        float rightEdge = xStartOffset + (float(writingIndex + i + 1.0) * pixelSizeClip.x);

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

                        //Cut the strip so the next quad doesn't connect to this one
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