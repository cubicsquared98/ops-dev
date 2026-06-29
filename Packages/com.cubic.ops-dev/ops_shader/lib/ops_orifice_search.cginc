#ifndef OPS_ORIFICE_SEARCH
#define OPS_ORIFICE_SEARCH

#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_defines.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_reader_lib.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_id.cginc"

/**
*   This function searches the entire ops texture for orifices, and returns the closest orifice + the IDs of the first 32 orifices within range
**/
void ops_search_all(inout float3 orificeRootLocal, inout float3 orificeRootNormal, inout float3 orificeRootUp,
	inout int found_orifice_id, inout uint4 orifice_types, inout bool allow_recursion, 
	inout uint path_count, inout int path_end,
	inout uint within_range_valueIDs[32], inout uint within_range_index, inout uint within_range_used_values,
	uint self_avatar_id, int avoid_on_self_mask, int channel_id,
	float3 searchFrom, float3 searchNormal, float search_to_distance,
	out bool allowLightSourcesInRecursion
){
	float3 read_data = readDataFrom_ID_TEX(uint2(0,0)); //Read from the bottom left of the screen. Max ID overlaps occur here, gives the amount of orifices.

	int Total_Ids = min(_OPS_TextureExists() ? round(read_data.r * getMultiplierDecode()): 0, 2000); //If no ops texture, will instantly fallback to sps search

	const uint MaxIndex_31 = 31;

	float Closest_Distance = 1e30;
	int closest = -1;
	bool closest_is_behind = false;

	float search_to_distance_sq = search_to_distance*search_to_distance;
	float overrun_distance_sq = search_to_distance_sq * 0.03125;

	bool Closest_allow_recursion = true;
	allowLightSourcesInRecursion = false;

	[loop]
	for(int i = 1; i <= Total_Ids; i++){ //0 cannot be an ID
		const uint4 Actives = UnpackFloat4ToUint4(readDataFrom(float2(offset_Orafice_ID_BitWise_Booleans, i)));
		//const float isActive = round(readInlineFloatData(offset_Orafice_ID_BitWise_Booleans, i));
		//Check if is on the same avatar and set to avoid on self
		const uint avoid_on_self = Actives.w;// uint(round(readInlineUintData(offset_Orafice_avoid_on_self, i)));
		const uint avatar_ID = uint(round(readInlineUintData(offset_Orafice_avatar_id, i)));
		const int avoid_on_self_mask_other = int(round(readInlineFloatData(offset_Orafice_avoid_on_self_mask, i)));
		const float channel_ID = round(readInlineFloatData(offset_Orafice_channel_id, i));

		if	((Actives.x < 1)
			|| (channel_id != -1 && channel_id != int(channel_ID))
			|| (self_avatar_id != 0 && avatar_ID == self_avatar_id && (avoid_on_self == 1 || avoid_on_self_mask == avoid_on_self_mask_other && avoid_on_self_mask != -1)))
		{
			continue;
		}

		//Now check the distance, limiting the max path count
		const uint PathCount = min(20, uint(readInlineUintData(offset_Orafice_dynamic_Path_Count, i)));
		const uint4 local_orifice_types = UnpackFloat4ToUint4(readDataFrom(float2(offset_Orafice_ops_type, i)));
		const int ends = PathCount > 0 && local_orifice_types.y == OPS_hole_entry_direction_TWO_WAY ? 2 : 1;
		float3 local_pos[2] = {
			sps_toLocal(readInlineFloat3Data(offset_Orafice_world_pos, i)),
			float3(0,0,0)
		};
		if(ends == 2){
			local_pos[1] = sps_toLocal(readInlineFloat3Data((PathCount-1) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values, i));
		}
		


		bool added_to_array = false;
		for(int p = 0; p < ends; p++){
			// const float distance_to = distance(local_pos[p],searchFrom);

			const float3 delta = local_pos[p] - searchFrom;
			const float distance_to_sq = dot(delta, delta);

			if(distance_to_sq > search_to_distance_sq) continue;

			
			const bool is_behind = dot(delta, searchNormal) < 0.0;
			
			//Check if behind, and check for hole overrun distance (counts as in front if within th hole overrun distance)
			const float behind = distance_to_sq > overrun_distance_sq && is_behind;

			const bool replace_closest = ((distance_to_sq < Closest_Distance && (!behind || closest_is_behind && behind)) || closest_is_behind && !behind || Closest_Distance > search_to_distance_sq);

			//Final distance checks. If the value is behind, then a value in front takes priority always
			if(replace_closest){
				Closest_Distance = distance_to_sq;
				closest = added_to_array ? within_range_index - 1 : within_range_index;
				closest_is_behind = behind;
				orificeRootLocal = local_pos[p];
				orifice_types = local_orifice_types;
				path_count = PathCount;
				path_end = p;
				Closest_allow_recursion = !bool(Actives.z); //Needs buffering till the actual closest is found, as its an && process for the output
				allowLightSourcesInRecursion = !bool(Actives.y); //If there is a lightsource backup inside of this ops component, dont allow searching for light sources in the next iterations
			}

			within_range_valueIDs[within_range_index] = within_range_index == MaxIndex_31 ? i : within_range_valueIDs[within_range_index];

			if(!added_to_array && within_range_index < MaxIndex_31){
				within_range_valueIDs[within_range_index] = i;
				within_range_index ++;
				added_to_array = true;
			}

		}
		
	}
	[branch]
	if(closest >= 0){
		//We now have our selected first orifice. Sets it to used.
		within_range_used_values |= (1u << closest);

		found_orifice_id = within_range_valueIDs[closest];
		const uint read_location = (path_count > 0 && path_end == 1) ? (path_count - 1) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values + dynamic_offset_Orafice_Path_forward_vec_x : offset_Orafice_world_forward_vec;
		orificeRootNormal = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(read_location, found_orifice_id)));
		orificeRootUp = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(read_location + 3, found_orifice_id))); //Just add 3
		allow_recursion = allow_recursion && Closest_allow_recursion;
		
	}
}

//Requires the first search function to have located close by values already
void ops_search_within_found_range(inout float3 orificeRootLocal, inout float3 orificeRootNormal, inout float3 orificeRootUp,
	inout int found_orifice_id, inout uint4 orifice_types, inout bool allow_recursion, 
	inout uint path_count, inout int path_end,
	uint within_range_valueIDs[32], uint within_range_index, inout uint within_range_used_values,
	float3 searchFrom, float3 searchNormal, float search_to_distance,
	inout bool allowLightSourcesInRecursion
){
	//within_range_index has a max value of 31
	int Total_Ids = _OPS_TextureExists() ? within_range_index : 0; //If no ops, fallback to sps

	const uint MaxIndex_31 = 31;

	float Closest_Distance = 1e30;
	int closest = -1;
	bool closest_is_behind = false;

	float search_to_distance_sq = search_to_distance*search_to_distance;
	float overrun_distance_sq = search_to_distance_sq * 0.03125;

	for(int i = 0; i < Total_Ids; i++){

		//Check if this orifice has already been penetrated
		if ((within_range_used_values & (1u << i)) != 0) continue;

		const int Search_Orafice_ID = within_range_valueIDs[i];

		//Now check the distance (incl paths data)
		const uint PathCount = uint(readInlineUintData(offset_Orafice_dynamic_Path_Count, Search_Orafice_ID));
		const uint4 local_orifice_types = UnpackFloat4ToUint4(readDataFrom(float2(offset_Orafice_ops_type, Search_Orafice_ID)));
		const int ends = PathCount > 0 && local_orifice_types.y == OPS_hole_entry_direction_TWO_WAY ? 2 : 1;
		float3 local_pos[2] = {
			sps_toLocal(readInlineFloat3Data(offset_Orafice_world_pos, Search_Orafice_ID)),
			float3(0,0,0)
		};
		if(ends == 2){
			local_pos[1] = sps_toLocal(readInlineFloat3Data((PathCount-1) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values, Search_Orafice_ID));
		}

		for(int p = 0; p < ends; p++){
			// const float distance_to = distance(local_pos[p],searchFrom);

			const float3 delta = local_pos[p] - searchFrom;
			const float distance_to_sq = dot(delta, delta);

			if(distance_to_sq > search_to_distance_sq) continue;

			const bool is_behind = dot(delta, searchNormal) < 0.0;

			//Distance may have changed now that we are searching from a new position

			//Check if behind, and check for hole overrun distance (counts as in front if within th hole overrun distance)
			const float behind = distance_to_sq > overrun_distance_sq && is_behind; //search_to_distance*0.03125 is search_to_distance/1.6*0.05
			const bool replace_closest = ((distance_to_sq < Closest_Distance && (!behind || closest_is_behind && behind)) || closest_is_behind && !behind || Closest_Distance > search_to_distance_sq);
			//Final distance checks. If the value is behind, then a value in front takes priority always
			if(replace_closest){
				Closest_Distance = distance_to_sq;
				closest = i;
				closest_is_behind = behind;
				orificeRootLocal = local_pos[p];
				orifice_types = local_orifice_types;
				path_count = PathCount;
				path_end = p;
			}
		}
	}
	[branch]
	if(closest >= 0){
		//We now have our selected orifice. Sets it as used.
		within_range_used_values |= (1u << closest);

		found_orifice_id = within_range_valueIDs[closest];
		const uint read_location = (path_count > 0 && path_end == 1) ? (path_count - 1) * dynamic_offset_Orafice_Per_Path + Total_Orafice_Written_Values + dynamic_offset_Orafice_Path_forward_vec_x : offset_Orafice_world_forward_vec;
		orificeRootNormal = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(read_location, found_orifice_id)));
		orificeRootUp = UnityWorldToObjectDir(sps_normalize(readInlineFloat3Data(read_location + 3, found_orifice_id))); //Just add 3
		uint4 actives = UnpackFloat4ToUint4(readDataFrom(float2(offset_Orafice_ID_BitWise_Booleans, i)));
		allow_recursion = allow_recursion && !bool(actives.z);
		allowLightSourcesInRecursion = allowLightSourcesInRecursion && !bool(actives.x);

		//allow_recursion = allow_recursion && (readInlineUintData(offset_Orafice_ops_disable_recursion, found_orifice_id) < 0.5);
		
	}
}


#endif