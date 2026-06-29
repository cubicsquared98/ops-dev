#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_defines.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_reader_lib.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_id.cginc"

#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_orifice_search.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_penetrator_search.cginc"

uint _OPS_HASH_SEED;
uint _OPS_SKINNED_BONES_OFFSET;
uint _OPS_SKINNED_BONES_ENABLED;
uint _OPS_FROT_MODE;
int _OPS_PENETRATOR_AVOID_ON_SELF_MASK;
int _OPS_ID_CHANNEL;

//Maybe add a compile option for this in the shader options
#define SEARCH_FOR_LIGHTS 0

#define _OPS_MAX_RECURSIVE_OPS 10

bool IsBehind(float3 targetPos, float3 referencePos, float3 normalDir)
{
	// Vector from the reference point to the target point
	float3 toTarget = targetPos - referencePos;
	//dot product it
	float d = dot(toTarget, normalDir);
	
	return d < 0.0;
}

void SearchLightSourceLights(float3 searchFrom, float search_distance_sq,  inout float3 orificeRootLocal, inout float3 orificeRootNormal, inout float4 ops_orifice_type){
	int sps_orifice_type = SPS_TYPE_INVALID;
	sps_light_search(searchFrom, sps_orifice_type, orificeRootLocal, orificeRootNormal);
	
	const float3 delta = orificeRootLocal - searchFrom;
	const float distance_to_sq = dot(delta, delta);
	if(distance_to_sq > search_distance_sq){
		ops_orifice_type = float4(
			OPS_hole_type_INVALID,
			OPS_hole_entry_direction_INVALID,
			OPS_hole_alignment_INVALID,
			0
		); //Invalid
	}
	else if(sps_orifice_type == SPS_TYPE_HOLE){
		ops_orifice_type = float4(
			OPS_hole_type_HOLE,
			OPS_hole_entry_direction_ONE_WAY,
			OPS_hole_alignment_CENTER_ALIGNED,
			0
		);
	}
	else if(sps_orifice_type == SPS_TYPE_RING_TWOWAY){
		ops_orifice_type = float4(
			OPS_hole_type_RING,
			OPS_hole_entry_direction_TWO_WAY,
			OPS_hole_alignment_CENTER_ALIGNED,
			0
		);
	}
	else if(sps_orifice_type == SPS_TYPE_RING_ONEWAY){
		ops_orifice_type = float4(
			OPS_hole_type_RING,
			OPS_hole_entry_direction_ONE_WAY,
			OPS_hole_alignment_CENTER_ALIGNED,
			0
		);
	}
}

void ops_search_all_and_lights(inout float3 orificeRootLocal, inout float3 orificeRootNormal, inout float3 orificeRootUp,
		inout int found_orifice_id, inout uint4 orifice_types, inout bool allow_recursion, 
		inout uint path_count, inout int path_end,
		inout uint within_range_valueIDs[32], inout uint within_range_index, inout uint within_range_used_values,
		uint self_avatar_id, int avoid_on_self_mask, int channel_id,
		float3 searchFrom, float3 searchNormal, float search_to_distance,
		out bool allowLightSourcesInRecursion
){
	//Run ops search function
	ops_search_all(
		orificeRootLocal, orificeRootNormal, orificeRootUp,
		found_orifice_id, orifice_types, allow_recursion,
		path_count, path_end,
		within_range_valueIDs, within_range_index, within_range_used_values,
		self_avatar_id, avoid_on_self_mask, channel_id,
		searchFrom, searchNormal, search_to_distance,
		allowLightSourcesInRecursion
	);

	if(orifice_types.x == OPS_hole_type_INVALID){
		SearchLightSourceLights(searchFrom, search_to_distance*search_to_distance, orificeRootLocal, orificeRootNormal, orifice_types);
		found_orifice_id = -1; //-1 means no ID associated with this orifice
		path_count = 0;
		path_end = 0;
	}
}

void ops_search_within_found_range_with_lights(inout float3 orificeRootLocal, inout float3 orificeRootNormal, inout float3 orificeRootUp,
	inout int found_orifice_id, inout uint4 orifice_types, inout bool allow_recursion, 
	inout uint path_count, inout int path_end,
	uint within_range_valueIDs[32], uint within_range_index, inout uint within_range_used_values,
	float3 searchFrom, float3 searchNormal, float search_to_distance,
	inout bool allowLightSourcesInRecursion
){

	//Searches the up to 32 found orifices for the next closest orifice
	ops_search_within_found_range(
		orificeRootLocal, orificeRootNormal, orificeRootUp,
		found_orifice_id, orifice_types, allow_recursion,
		path_count, path_end,
		within_range_valueIDs, within_range_index, within_range_used_values,
		searchFrom, searchNormal, search_to_distance,
		allowLightSourcesInRecursion
	);
	
	//Small check to make sure that the previous orifice found has an ID meaning it is an ops orifice not a dps/sps only orifice
	//Checks if no ops component was found, that the previous found hole had an OPS ID, and that light sources are allowed in recursion
	[branch]
	if (orifice_types.x == OPS_hole_type_INVALID && found_orifice_id != -1 && allowLightSourcesInRecursion){
		SearchLightSourceLights(searchFrom, search_to_distance*search_to_distance, orificeRootLocal, orificeRootNormal, orifice_types);
		found_orifice_id = -1; //-1 means no ID associated with this orifice
		path_count = 0;
		path_end = 0;
	}
}


void calculate_lerps(inout float bezierLerp, inout float dumbLerp,
	float entranceAngle, float exitAngle, float active,
	float distance_to_orifice, float length_z,
	uint4 orifice_type, bool is_behind
){

	float applyLerp = 1; //This value represents how sps behaves.
	// VALUE: 
	//		1 - means fully curving - end is expected to be inside a hole
	//		0 - means no sps component within 1.6*penetrator length
	//		0.5 - means that there is a hole nearby but not touching, something like half a penetrator away roughly

	// Cancel if base angle is too sharp
	const float allowedExitAngle = 0.6; //107 degrees
	const float exitAngleTooSharp = exitAngle > SPS_PI*allowedExitAngle ? 1 : 0;
	applyLerp = min(applyLerp, 1-exitAngleTooSharp); //If too sharp, applyLerp is set to zero

	// Cancel if the entrance angle is too sharp (two-ways allows upto 180)
	const float allowedEntranceAngle = orifice_type.y != OPS_hole_entry_direction_TWO_WAY ? 0.8 : 1.0; //143 deg or 180 deg
	const float entranceAngleTooSharp = entranceAngle > SPS_PI*allowedEntranceAngle ? 1 : 0;
	applyLerp = min(applyLerp, 1-entranceAngleTooSharp); //If too sharp, applyLerp is set to zero
	
	//Ignore sharpness IF (aiming at hole OR is behind), AND within 50% of length 
	if (orifice_type.x == OPS_hole_type_HOLE || is_behind) {
		//UNCANCEL if within half of the length OR is hilted in a hole. count 50%/past in as hilted, will work fine if closest to this hole
		const float hiltedSphereRadius = 0.5;
		const float hilted = distance_to_orifice > length_z*hiltedSphereRadius ? 0 : 1; //If the distance is bigger than half the dick length set 0 otherwise set 1;
		
		applyLerp = max(applyLerp, hilted);
	}

	// Lowers the amount of applying after 1.2*penetrator length, and reaches 0 at 1.6*
	const float tooFar = sps_saturated_map(distance_to_orifice, length_z*1.2, length_z*1.6); // 0 if at to 1.2, 1 if closer to 1.6
	applyLerp = min(applyLerp, 1-tooFar);

	applyLerp = applyLerp * saturate(_SPS_Enabled);

	dumbLerp = sps_saturated_map(applyLerp, 0, 0.2) * active; //dumbLerp completely enables/disables
	bezierLerp = sps_saturated_map(applyLerp, 0, 1); //bezierLerp is how strongly we bend towards the bezier

}

void calculate_bezier_points(
	inout float3 bezierPos, inout float3 bezierForward, inout float3 bezierRight, inout float3 bezierUp, inout float curveLength,
	float start_end_distance, float line_length, float bezierLerp, float distance_along_line, float3 reference_up,
	float3 start_point, float3 start_direction,
	float3 end_point, float3 end_direction
	)
{
	//distance_to_orifice, length_z, bezierLerp, distance_along_line
	//searchFrom, search_normal
	//orificeRootLocal, orificeRootNormal
	
	//Forms 4 points for the bezier curve.
	//p0 and p4 are the start and end points.
	//p1 like strength of first curve / Direction of curve to bend towards
	//p2 is direction for the bend to curve towards on the hole side
	const float3 p0 = start_point;
	// largest of ( penetrator_length / 8 OR distance_to_hole / 4) THEN use distance_to_hole if smaller.
	//This gives a value, of length, between distance_to_hole and penetrator_length / 8
	//Set the max amount to 50% the length of the start_end distance to ensure smooth bezier
	const float p1Dist = min(start_end_distance*0.5f, max(line_length * 0.125f, start_end_distance *0.25f)); //Distance value that is less than distance to hole
	const float p1DistWithPullout = sps_map(bezierLerp, 0, 1, line_length * 5, p1Dist); //Changes the point so that bezier is essentially a straight line, so it eases in with distance
	const float3 p1 = start_point + p1DistWithPullout*start_direction;
	const float3 p2 = end_point + end_direction * p1Dist; //Mirrored point on hole end
	const float3 p3 = end_point;

	//Gets a point on the bezier at distance Z for the vertex.
	//Returns the length of the entire curve (start-end point), and the position of the bezier for this point
	sps_bezierSolve_ops(p0, p1, p2, p3, distance_along_line, reference_up, curveLength, bezierPos, bezierForward, bezierUp);


	//Force the upwards direction if passed the start, prevent rolling, set dist to 1 cm, might need to set it higher, prevents bad rolling that occurs due to the bezier
	float lerp_amount = sps_saturated_map(start_end_distance, 0, 0.01);//IsBehind(end_point, start_point, start_direction) ? 0 : 

	bezierUp = lerp(reference_up, bezierUp, lerp_amount);

	bezierRight = sps_normalize(cross(bezierUp, bezierForward));
}

void apply_deformations(inout float4 vertex, inout float3 normal, inout float4 tangent,
	float3 origVertex, float3 origNormal, float3 origTangent,
	float holeShrink, float dumbLerp,
	float3 bezierPos, float3 bezierRight, float3 bezierUp, float3 bezierForward,
	float3 bakedVertex, float3 bakedNormal, float3 bakedTangent
){
	//Place the vertex at its position offset from the bezier.
	float3 deformedVertex = bezierPos + bezierRight * bakedVertex.x * holeShrink + bezierUp * bakedVertex.y * holeShrink;

	//Lerp between bezier and normal position based on dumbLerp. (0.2 distance )
	vertex.xyz = lerp(origVertex, deformedVertex, dumbLerp);

	//Apply normal and tangent as well if they exist
	if (length(bakedNormal) != 0) {
		float3 deformedNormal = bezierRight * bakedNormal.x + bezierUp * bakedNormal.y + bezierForward * bakedNormal.z;
		normal.xyz = normalize(lerp(origNormal, deformedNormal, dumbLerp));
	}
	if (length(bakedTangent) != 0) {
		float3 deformedTangent = bezierRight * bakedTangent.x + bezierUp * bakedTangent.y + bezierForward * bakedTangent.z;
		tangent.xyz = normalize(lerp(origTangent, deformedTangent, dumbLerp));
	}
}

void apply_deformations(inout float4 vertex, inout float3 normal, inout float4 tangent,
	float holeShrink, float dumbLerp,
	float3 bezierPos, float3 bezierRight, float3 bezierUp, float3 bezierForward,
	float3 bakedVertex, float3 bakedNormal, float3 bakedTangent
){
	//Place the vertex at its position offset from the bezier.
	float3 deformedVertex = bezierPos + bezierRight * bakedVertex.x * holeShrink + bezierUp * bakedVertex.y * holeShrink;

	//Lerp between bezier and normal position based on dumbLerp. (0.2 distance )
	vertex.xyz = lerp(vertex.xyz, deformedVertex, dumbLerp);

	//Apply normal and tangent as well if they exist
	if (length(bakedNormal) != 0) {
		float3 deformedNormal = bezierRight * bakedNormal.x + bezierUp * bakedNormal.y + bezierForward * bakedNormal.z;
		normal.xyz = lerp(normal.xyz, deformedNormal, dumbLerp);
	}
	if (length(bakedTangent) != 0) {
		float3 deformedTangent = bezierRight * bakedTangent.x + bezierUp * bakedTangent.y + bezierForward * bakedTangent.z;
		tangent.xyz = lerp(tangent.xyz, deformedTangent, dumbLerp);
	}
}

void ops_get_transformed_position(int4 blendIndices, float4 blendWeights, inout float3 bakedVertex, float halfWidth, uint ID, float radius){
	uint bone_offset = _OPS_SKINNED_BONES_OFFSET;//readInlineUintData(halfWidth + offset_penetrator_bone_data_start_bone_index, ID);
	blendIndices = blendIndices - bone_offset; //correct the ID for reading

	float2 scaleSum = float2(0,0);
	float summed_blendweight = 0;

	for(int i = 0; i < 4; i ++){
		if(blendIndices[i] >= 0 && blendWeights[i] > 0){
			float radius_x = readInlineFloatData((blendIndices[i] * dynamic_offset_penetrator_Bone_data) + halfWidth + offset_penetrator_bone_data_start, ID);
			float radius_y = readInlineFloatData((blendIndices[i] * dynamic_offset_penetrator_Bone_data) + halfWidth + offset_penetrator_bone_data_start + 1, ID);

			scaleSum.x += (radius_x / radius) * blendWeights[i];
			scaleSum.y += (radius_y / radius) * blendWeights[i];
			summed_blendweight += blendWeights[i];
		}
	}
	scaleSum += (1.0f - summed_blendweight); //How much is weighted to no bones / at the origional position. would be 1f (current scale) * (summed_blendweight - 1)

	bakedVertex.xy *= scaleSum.xy;
}

void ops_apply(
	inout SPS_STRUCT_POSITION_TYPE vertex,
	inout SPS_STRUCT_NORMAL_TYPE normal,
	inout SPS_STRUCT_TANGENT_TYPE tangent,
	uint vertexId,
	inout SPS_STRUCT_COLOR_TYPE color,
	int4 blendIndices, //SPS_STRUCT_BLENDINDICES_TYPE
	float4 blendWeights //SPS_STRUCT_BLENDWEIGHT_TYPE
) {
	if(!(_SPS_Enabled > 0.0)){
		return;
	}
	// //Kill verts, just to prevent shadow from being rendered
	// This is commented out, because it doesnt line up perfectly with smooth toggle of actual shadow stuff on mesh renderer
	// #if defined(UNITY_PASS_SHADOWCASTER)
    //     // Collapse the vertex to the local origin to prevent shadow casting
    //     vertex.xyz = float3(0, 0, 0);
    //     return;
	// #endif

	float worldLength = _SPS_Length;//_SPS_Length;//length(unity_ObjectToWorld[0].xyz) * _SPS_BakedLength;//_SPS_Length;

	float3 bakedVertex;
	float3 bakedNormal;
	float3 bakedTangent;
	float active;
	SpsGetBakedPosition(vertexId, bakedVertex, bakedNormal, bakedTangent, active);

	float3 worldObjectPos = float3(unity_ObjectToWorld._m03, unity_ObjectToWorld._m13, unity_ObjectToWorld._m23);
	float distance_to_camera = distance(_WorldSpaceCameraPos, worldObjectPos);

	uint penetrator_ID = getID(worldObjectPos, _OPS_HASH_SEED, distance_to_camera, ID_SPACE_PENETRATOR);

	float ScreenWidth = _OPS_GRAB_TEXTURE_TexelSize.z;
	
	// If using Single Pass Stereo (Double-Wide), the logical width for ONE eye is half the texture width.
    #if UNITY_SINGLE_PASS_STEREO && !(defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED))
        ScreenWidth *= 0.5;
    #endif



	float HalfWidth = ScreenWidth * 0.5;
	uint self_avatar_id = 0;
	int avoid_on_self_mask = _OPS_PENETRATOR_AVOID_ON_SELF_MASK;
	int channel_id = _OPS_ID_CHANNEL;

	float ops_isActive = 1;

	//set default values if is just sps
	float worldRadius = 0;
	float distance_before_start = 0; //Is 0 under regular conditions
	float distance_past_start = worldLength; //Is the remaining length (worldLength)

	if(_OPS_TextureExists()){
		//Read from Penetrator ops data
		ops_isActive = readInlineFloatData(HalfWidth + offset_penetrator_is_active, penetrator_ID);

		float3 origin_point = readInlineFloat3Data(HalfWidth + offset_penetrator_world_start_point_x, penetrator_ID);
		float3 end_point = readInlineFloat3Data(HalfWidth + offset_penetrator_world_end_point_x, penetrator_ID);
		float3 radius_point = readInlineFloat3Data(HalfWidth + offset_penetrator_world_radius_up_point_x, penetrator_ID);
		self_avatar_id = readInlineUintData(HalfWidth + offset_penetrator_avatar_id, penetrator_ID);

		float3 local_mesh_origin = sps_toLocal(origin_point);
		float3 local_mesh_endpoint = sps_toLocal(end_point);

		worldLength = distance(origin_point, end_point);
		worldRadius = distance(origin_point, radius_point);

		distance_before_start = length(local_mesh_origin); //Is 0 under regular conditions
		distance_past_start = length(local_mesh_endpoint); //Is the remaining length
	}

	//scales baked vertex into world space scaling of the mesh.
	bakedVertex *= (worldLength / _SPS_BakedLength);
	//baked vertex's are now in the same scale space as the original vertex's

	if(_OPS_SKINNED_BONES_ENABLED == 1 && _OPS_TextureExists()){
		ops_get_transformed_position(blendIndices, blendWeights, bakedVertex, HalfWidth, penetrator_ID, worldRadius); //Adjusts radius based on scales of bones
	}

	//Consider dependant read chains. Make texture fetch's close to where they will be used,
	//as if a second texture fetch relies on a previous one, then the thread has to wait for the initial fetch to have completed


	float start_z = clamp(distance_before_start, 0, worldLength); 	//The transformation along the Z axis for the stating point. usually zero
	float length_z = clamp(distance_past_start, 0, worldLength);	//The remaining length for finding holes.

	//Using this info, we know to translate all the baked vertex's along the Z axis, so that the penetrator mesh is aligned with the actual mesh for deformation
	bakedVertex.z -= start_z;

	//If the bakedVertex is behind 0,0,0 (negative Z) we can now return the actual vertex position
	if(bakedVertex.z < 0){
		// values have not changed, so just return.
		return;
	}

	//The mesh is now transformed and scaled, we can search for ops holes and apply bezier.

	//We now have the starting point of this orifice, AND we know if it is a path or not.

	float bezierLerp;
	float dumbLerp;
	float holeShrink = 1; //Shrinks the radius down to nothing if zero

	//Get curve
	float3 bezierPos;
	float3 bezierForward;
	float3 bezierRight;
	float3 bezierUp = float3(0,1,0);
	float curveLength;

	//For optimisations sake, within_range_valueIDs can be packed and halved in size. also, static access would improve performance
	uint within_range_used_values = 0;
	uint within_range_valueIDs[32]; //This is the max amount of holes that are within range of the penetrator
	uint within_range_index = 0;

	int found_orifice_id = -1;
	uint4 orifice_type = uint4(OPS_hole_type_INVALID, OPS_hole_entry_direction_INVALID, OPS_hole_alignment_INVALID, 0);
	bool allow_recursion = true; //Set this to false if the shader itsself is saying false (read value from penetrator data)
	float3 orificeRootLocal;
	float3 orificeRootNormal;
	float3 orificeRootUp;
	uint path_count = 0;
	int path_end = 0;


	float3 searchFrom = float3(0,0,0); //Point to start searching for the closest
	float search_to_distance = length_z * 1.6; //Search for holes within this range
	float3 search_normal = float3(0,0,1); //Z-axis direction

	float Dist_After_Hole_of_vert = bakedVertex.z;		//length along of this vert
	float Remaining_Length_Of_Penetrator = length_z; 	//Whole length

	const float holeRecessDistance = length_z * 0.05; //These keep the

	bool allowLightSourcesInRecursion = true; //This is set to false if we find an orifice that has a backup light source

	uint4 searching_orifice_type = uint4(OPS_hole_type_INVALID, OPS_hole_entry_direction_INVALID, OPS_hole_alignment_INVALID, 0);

	//bool found_frot = false;

	uint frot_found_count = 0;
    float4 frot_found_data[5];
    float3 frot_group_normal, frot_max_proj_point;
    float frot_group_length;


	//get the frotting data
    [branch]
    if(_OPS_FROT_MODE == 1){
        ops_frot_gather(
            searchFrom, search_normal, worldRadius, search_to_distance, length_z,
            penetrator_ID, self_avatar_id, avoid_on_self_mask, channel_id, HalfWidth,
            frot_found_count, frot_found_data,
            frot_group_normal, frot_max_proj_point, frot_group_length
        );

        if (frot_found_count > 0) {
            //Overwrite search params with the frot group's "Virtual Penetrator" data
            searchFrom = frot_max_proj_point;
            search_normal = frot_group_normal;
            search_to_distance = frot_group_length * 1.6;
        }
    }

	//Perform orifice search
#ifdef SEARCH_FOR_LIGHTS
    ops_search_all_and_lights(orificeRootLocal, orificeRootNormal, orificeRootUp,
        found_orifice_id, searching_orifice_type, allow_recursion,
        path_count, path_end,
        within_range_valueIDs, within_range_index, within_range_used_values,
        self_avatar_id, avoid_on_self_mask, channel_id,
        searchFrom, search_normal, search_to_distance,
        allowLightSourcesInRecursion
    );
#else
    ops_search_all_and_lights(orificeRootLocal, orificeRootNormal, orificeRootUp,
        found_orifice_id, searching_orifice_type, allow_recursion,
        path_count, path_end,
        within_range_valueIDs, within_range_index, within_range_used_values,
        self_avatar_id, avoid_on_self_mask, channel_id,
        searchFrom, search_normal, search_to_distance,
        allowLightSourcesInRecursion
    );
#endif


	float3 frot_offset = float3(0,0,0);

	float frot_hole_lerp_factor = 1.0;

	//Apply Frot deforming and get offsets
    [branch]
    if(frot_found_count > 0){
		float new_radius;
        ops_frot_apply(
            frot_found_count, frot_found_data, frot_max_proj_point, frot_group_normal,
			frot_group_length, length_z, 0.05,
            found_orifice_id, orificeRootLocal, orificeRootNormal, searching_orifice_type.y,
            frot_offset, new_radius, frot_hole_lerp_factor
        );

        if (found_orifice_id == -1) {
            // Air Frot
            allow_recursion = false;
            searching_orifice_type = uint4(OPS_hole_type_RING, OPS_hole_entry_direction_ONE_WAY, OPS_hole_alignment_CENTER_ALIGNED, 0);
            path_count = 0;
            path_end = 0;
        }
		orificeRootLocal = frot_max_proj_point;
		orificeRootNormal = -frot_group_normal;
		worldRadius = new_radius; //assign new radius for radius penetrators
		//orificeRootLocal += frot_offset;
    }

	//Reset search origin back to the local zero for bezier deformations
    searchFrom = float3(0,0,0);
    search_normal = float3(0,0,1);
    search_to_distance = length_z * 1.6;

	[loop]
	for(int recursion_loop = 0; recursion_loop < _OPS_MAX_RECURSIVE_OPS; recursion_loop ++){
		//continue to find next hole
		//Search from location of last point and populate orifice data with new infomation

		[branch]
		if(recursion_loop != 0){
			searching_orifice_type = uint4(OPS_hole_type_INVALID, OPS_hole_entry_direction_INVALID, OPS_hole_alignment_INVALID, 0);
			//After the first loop, allow breaking out of the loop if recursion is disabled.
			if(!allow_recursion){
				break;
			}
#ifdef SEARCH_FOR_LIGHTS
			ops_search_within_found_range_with_lights(
				orificeRootLocal, orificeRootNormal, orificeRootUp,
				found_orifice_id, searching_orifice_type, allow_recursion,
				path_count, path_end,
				within_range_valueIDs, within_range_index, within_range_used_values,
				searchFrom, search_normal, search_to_distance,
				allowLightSourcesInRecursion
			);
#else
			ops_search_within_found_range(
				orificeRootLocal, orificeRootNormal, orificeRootUp,
				found_orifice_id, searching_orifice_type, allow_recursion,
				path_count, path_end,
				within_range_valueIDs, within_range_index, within_range_used_values,
				searchFrom, search_normal, search_to_distance,
				allowLightSourcesInRecursion
			);
#endif
		}

		if(searching_orifice_type.y == OPS_hole_type_INVALID){
			//No hole was found, run final logic
			break;
		}
		orifice_type = searching_orifice_type;

		//Move by radius amount
		orificeRootLocal += lerp(float3(0,0,0), orifice_type.z == OPS_hole_alignment_RADIUS_ALIGNED ? orificeRootUp * worldRadius : 0, frot_hole_lerp_factor);

		//Modify orifice root by frot_offset AFTER radius check
		orificeRootLocal += frot_offset;


		//SearchFrom is the current starting point, orifice root&normal is hole and hole directions

		float distance_to_orifice = distance(orificeRootLocal, searchFrom);

		float exitAngle = sps_angle_between(orificeRootLocal - searchFrom, search_normal);
	
		//Entrance angle is the difference betwen the direction the hole faces and the direction to the sps hole
		float entranceAngle = SPS_PI - sps_angle_between(orificeRootNormal, orificeRootLocal - searchFrom);

		// Flip bidirectional rings that are not pathed, if the entry angle is over 180
		if (path_count == 0 && orifice_type.y == OPS_hole_entry_direction_TWO_WAY && entranceAngle > SPS_PI/2) {
			orificeRootNormal *= -1;
			entranceAngle = SPS_PI - entranceAngle;
		}

		calculate_lerps(bezierLerp, dumbLerp,
			entranceAngle, exitAngle, active,
			distance_to_orifice, Remaining_Length_Of_Penetrator,
			orifice_type, IsBehind(orificeRootLocal, searchFrom, search_normal)
		);

		//Only dumblerp when on the first iteration, is just smoothing between bone-based position to our sps position, after first penetrator we are already at this point.
		//And check if in-front of the orifice, if this is the case then we are a path
		dumbLerp = recursion_loop > 0 ? 1 : dumbLerp;

		//returns early if Dist_After_Hole_of_vert is less than curveLength
		calculate_bezier_points(bezierPos, bezierForward, bezierRight, bezierUp, curveLength,
			distance_to_orifice, Remaining_Length_Of_Penetrator, bezierLerp, Dist_After_Hole_of_vert, bezierUp,
			searchFrom, search_normal,
			orificeRootLocal, orificeRootNormal
		);

		Dist_After_Hole_of_vert -= curveLength; //The remaining distance till we hit our vertex along z


		//This one works - This is going from start point to hole entry (before path)
		//At this point, the wavefront threads split, 
		//	verts after the first hole will have to wait for deformations to be applied,
		//	verts before the first hole will run this then wait on the other verts to be finished
		if(Dist_After_Hole_of_vert < 0){
			//If we are within the curve, accept as our new position
			holeShrink = 1;
			path_count = 0;
			allow_recursion = false;
			break;
		}
		
		
		//Now do pathing check yayayay

		Remaining_Length_Of_Penetrator -= curveLength;
		float3 Current_Path_Point = orificeRootLocal;
		float3 Current_Path_Point_Direction = -orificeRootNormal; //Flip direction of the point, for the next one

		//This is fine, entire wavefront either will or wont run this
		if(path_count > 0){
			bool break_out = false;
			//Same as above condition
			if(path_end == 0){
				
				for(uint path = 0; path < path_count; path++){
					uint reading_index = path * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values;
					float3 path_point = sps_toLocal(readInlineFloat3Data(reading_index, found_orifice_id));
					float3 path_normal = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(reading_index + dynamic_offset_Orafice_Path_forward_vec_x, found_orifice_id)));

					if(orifice_type.z == OPS_hole_alignment_RADIUS_ALIGNED){
						float3 path_up = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(reading_index + offset_Orafice_world_up_vec_x, found_orifice_id)));
						path_point += path_up * worldRadius;
					}

					//Apply frot offset after radius
					path_point += frot_offset;

					float Distance_To_Next_Path_Point = distance(Current_Path_Point, path_point);

					//From current to path point
					//returns early if Dist_After_Hole_of_vert is less than curveLength
					calculate_bezier_points(bezierPos, bezierForward, bezierRight, bezierUp, curveLength,
						Distance_To_Next_Path_Point, Remaining_Length_Of_Penetrator, 1, Dist_After_Hole_of_vert, bezierUp,//Bezier lerp is always '1' for paths as we know we are headed there next
						Current_Path_Point, Current_Path_Point_Direction,
						path_point, -path_normal
					);

					float hide_path = readInlineUintData(reading_index + dynamic_offset_Orafice_Path_hide_segment, found_orifice_id);

					bool no_shrink = (Dist_After_Hole_of_vert <= holeRecessDistance && path == 0) || path == (path_count - 1) && Dist_After_Hole_of_vert >= (curveLength - holeRecessDistance);

					Dist_After_Hole_of_vert -= curveLength;//abs();

					//Check if vert is within this curve (doesnt seem to be )
					//Suffers the same wavefront issue as initial one
					if(Dist_After_Hole_of_vert < 0){
						
						holeShrink -= no_shrink ? 0 : hide_path;
						dumbLerp = 1;
						allow_recursion = false;
						break_out = true;
						break;
						
					}
					

					
					Remaining_Length_Of_Penetrator -= curveLength;
					Current_Path_Point = path_point;
					Current_Path_Point_Direction = path_normal; //Path normals point in the direction of the path, this is correct.
				}
				if(break_out){
					break;
				}
			}
			else if (path_end == 1){
				//Going in reverse, so flip path normals and iterate back-to-front
				//The last hole is already in use, and we need to fetch the actual hole location and normal for the final path point
				//It will be more efficient in the future to merge the hole and normal into the pathing structure, but for now just gotta work around it

				//how stored in shader, when going in order iterates though like that
				//hole_base, [0,1,2]

				//We want
				//[2,1,0], hole_base
				// Essentially, start at 1, end at hole_base. path_count would be 3 in this scenario

				//path_count - 2 to get to 1.
				//If only 1 path point, and path_count is 2, then for loop will be avoided 

				//Ignore the fist iteration
				for(int path = ((int)path_count) - 2; path >= 0; path--){
					uint reading_index = path * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values;
					float3 path_point = sps_toLocal(readInlineFloat3Data(reading_index, found_orifice_id));
					float3 path_normal = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(reading_index + dynamic_offset_Orafice_Path_forward_vec_x, found_orifice_id)));
					float Distance_To_Next_Path_Point = distance(Current_Path_Point, path_point);

					if(orifice_type.z == OPS_hole_alignment_RADIUS_ALIGNED){
						float3 path_up = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(reading_index + offset_Orafice_world_up_vec_x, found_orifice_id)));
						path_point += path_up * worldRadius;
					}

					//Apply frot offset after radius
					path_point += frot_offset;
					
					//returns early if Dist_After_Hole_of_vert is less than curveLength
					calculate_bezier_points(bezierPos, bezierForward, bezierRight, bezierUp, curveLength,
						Distance_To_Next_Path_Point, Remaining_Length_Of_Penetrator, 1, Dist_After_Hole_of_vert, bezierUp,//Bezier lerp is always '1' for paths as we know we are headed there next
						Current_Path_Point, Current_Path_Point_Direction,
						path_point, path_normal //because opposite direction
					);

					//To make each segment correct
					uint prev_read_offset = (path + 1) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values;
					float hide_path = readInlineUintData(prev_read_offset + dynamic_offset_Orafice_Path_hide_segment, found_orifice_id);


					bool no_shrink = (Dist_After_Hole_of_vert <= holeRecessDistance && path == path_count - 2);


					Dist_After_Hole_of_vert -= curveLength;

					//Check if vert is within this curve
					//Suffers the same wavefront issue as initial one
					if(Dist_After_Hole_of_vert < 0){
						holeShrink -= no_shrink ? 0 : hide_path;
						dumbLerp = 1;
						allow_recursion = false;
						break_out = true;
						break;

					}

					
					Remaining_Length_Of_Penetrator -= curveLength;
					Current_Path_Point = path_point;
					Current_Path_Point_Direction = -path_normal;
				}
				if(break_out){
					break;
				}

				//After for loop we evaluate the base orifice pos and normal

				float3 path_point = sps_toLocal(readInlineFloat3Data(offset_Orafice_world_pos, found_orifice_id));
				float3 path_normal = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(offset_Orafice_world_forward_vec, found_orifice_id)));
				float Distance_To_Next_Path_Point = distance(Current_Path_Point, path_point);

				if(orifice_type.z == OPS_hole_alignment_RADIUS_ALIGNED){
					float3 path_up = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(offset_Orafice_world_up_vec, found_orifice_id)));
					path_point += path_up * worldRadius;
				}
				
				//returns early if Dist_After_Hole_of_vert is less than curveLength
				calculate_bezier_points(bezierPos, bezierForward, bezierRight, bezierUp, curveLength,
					Distance_To_Next_Path_Point, Remaining_Length_Of_Penetrator, 1, Dist_After_Hole_of_vert, bezierUp,//Bezier lerp is always '1' for paths as we know we are headed there next
					Current_Path_Point, Current_Path_Point_Direction,
					path_point, -path_normal //because opposite direction
				);

				//We read from the first segment
				uint prev_read_offset = (0) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values;
				float hide_path = readInlineUintData(prev_read_offset + dynamic_offset_Orafice_Path_hide_segment, found_orifice_id);

				bool no_shrink = Dist_After_Hole_of_vert >= (curveLength - holeRecessDistance);


				Dist_After_Hole_of_vert -= curveLength;

				//Check if vert is within this curve
				//Suffers the same wavefront issue as initial one
				if(Dist_After_Hole_of_vert < 0){
					holeShrink -= no_shrink ? 0 : hide_path;
					dumbLerp = 1;
					allow_recursion = false;
					break;
				}

				
				Remaining_Length_Of_Penetrator -= curveLength;
				Current_Path_Point = path_point;
				Current_Path_Point_Direction = path_normal;

			}

			//This has been added just to make sure the path stuff is working correctly.
			//return;
		}

		allow_recursion = allow_recursion && orifice_type.x == OPS_hole_type_RING;

		searchFrom = Current_Path_Point;
		search_normal = Current_Path_Point_Direction;
		search_to_distance = Remaining_Length_Of_Penetrator * 1.6;

	}





	//We have passed all holes / no hole found
	//The penetrator still has to be longer than the hole distance, otherwise it would have deformed at a previous point.

	
	//No wavefront issue with this
	if(orifice_type.x == OPS_hole_type_HOLE) {
		//const float holeRecessDistance = length_z * 0.05; //These keep the 
		const float holeRecessDistance2 = length_z * 0.1;

		//Dist_After_Hole_of_vert is the distance from orifice to current vert.
		//Negative for behind, positive for vert in front

		//map so that, holeshrink is 0-1 from 0.05 in front of hole and 0.1 in front of hole

		holeShrink = sps_saturated_map(
			Dist_After_Hole_of_vert,
			holeRecessDistance2,
			holeRecessDistance
		);

		//Just shoves the end point further in
		if(_SPS_Overrun > 0) {
			//Wavefront will have to wait while both sides calculate
			if (Dist_After_Hole_of_vert >= holeRecessDistance2) {
				// If way past socket, condense to point
				bezierPos += length_z*0.1 * bezierForward;
			} else if (Dist_After_Hole_of_vert >= 0) {
				// Straighten if past socket
				bezierPos += Dist_After_Hole_of_vert * bezierForward;
			}
		}
	}
	else{
		if(Dist_After_Hole_of_vert >= 0){

			bezierPos += Dist_After_Hole_of_vert * bezierForward;
		}
	}

	//IF vert is within 5% of penetrator length after base - change dumblerp to 0 -> 1; so that deformation is smooth across the boundry. This is to make a z-transformed penetrator smoother
	//Disabled until a better option is found / isnt really an issue if ops penetrator is set up right
	// dumbLerp = min(dumbLerp, sps_saturated_map(
	// 	bakedVertex.z,
	// 	0,
	// 	length_z *0.05
	// ));

	//Apply deformations
	apply_deformations(vertex, normal, tangent,
		holeShrink, dumbLerp,
		bezierPos, bezierRight, bezierUp, bezierForward,
		bakedVertex, bakedNormal, bakedTangent
	);
	return;



	/**
	runs apply_deformations once at the end. Instead of returning, just break / continue but set the holeShrink and dumbLerp values.
	This way, the gpu spends less time working.
	In the for loop, code is ran, any conditionals mean continued running across the entire wavefront, or breaks out of the for loop and waits for the other threads to finish
	The max time for computing is now on the vert with the highest z axis.


	*/
}
