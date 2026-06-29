#ifndef OPS_PENETRATOR_SEARCH
#define OPS_PENETRATOR_SEARCH

#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_defines.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_shader_reader_lib.cginc"
#include "Packages/com.cubic.ops-dev/ops_shader/lib/ops_id.cginc"

//Function finds first __max_frot_count_find penetrators within the search_to_max_distance, and checks if they have frot mode enabled
//Does not think about distances
void ops_pen_search(
	float3 search_from_point, float3 search_normal, float search_radius, float search_to_max_distance, float search_penetrator_length,
	uint self_ID, uint self_avatar_ID, int avoid_on_self_mask, int channel_id,
	float half_screen, float overlap_percent,
	out float3 use_position, out float3 use_normal, out bool frot_found
){
	#define __max_frot_count 5
	#define __max_frot_count_find (__max_frot_count - 1)
	#define TWO_PI 6.28318530718f
	// 1.0/TWO_PI
    #define INV_TWO_PI 0.159154943f


	//read from bottom screen for Max ID overlaps of penetrators
	uint4 ID_space = getIDSpace(ID_SPACE_PENETRATOR);

	float3 read_data = readDataFrom_ID_TEX(ID_space.zw);

	int Total_Ids = min(_OPS_TextureExists() ? round(read_data.r * getMultiplierDecode()): 0, 2000); //If no ops texture, will instantly fallback to sps search


	//If the only penetrator
	//if (Total_Ids <= 1) return;

	float search_to_distance_sq = search_to_max_distance*search_to_max_distance;
	
	float4 found_other_data[__max_frot_count];
	float3 averageDirection = search_normal;//found_other_normals[0];
	float3 sum_positions = search_from_point;

	
	uint found_count = 0;
	//Simply check the first 5. Ignore any extras

	[loop]
	for(int i = 1; i <= Total_Ids; i++){ //0 cannot be an ID
		if(((uint)i) == self_ID) continue;

		const float isActive = round(readInlineFloatData(half_screen + offset_penetrator_is_active, i));
		if(isActive < 1) continue;

		const uint isFrotMode = readInlineUintData(half_screen + offset_penetrator_frot_mode, i);
		if(isFrotMode == 0) continue;

		const float channel_ID = round(readInlineFloatData(half_screen + offset_penetrator_channel_id, i));
		if(channel_id != -1 && channel_id != int(channel_ID)) continue;

		//Check if is on the same avatar and set to avoid on self
		const uint avatar_ID = uint(readInlineUintData(half_screen + offset_penetrator_avatar_id, i));
		const int avoid_on_self_mask_other = int(round(readInlineFloatData(half_screen + offset_penetrator_avoid_on_self_mask, i)));

		if(self_avatar_ID != 0 && avatar_ID == self_avatar_ID && (avoid_on_self_mask == avoid_on_self_mask_other && avoid_on_self_mask != -1)) continue;

		float3 other_deform_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_deform_start_point_x, i));
		float3 end_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_end_point_x, i));

		// Check distance from center, because we are allowing entry from both sides (not any more but keep logic like this)
        float3 self_center = search_from_point + (search_normal * (search_penetrator_length * 0.5));
        float3 other_center = (other_deform_point + end_point) * 0.5;

		
		const float3 delta = other_center - self_center;
		const float distance_to_sq = dot(delta, delta);

		const float3 delta_other = (other_deform_point - end_point)*1.6;
		const float other_search_length_square = dot(delta_other, delta_other);

		//We search to make sure we are within the distance for *both* penetrators.
		if(distance_to_sq > min(search_to_distance_sq, other_search_length_square)) continue;


		float3 radius_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_radius_up_point_x, i));
		float3 other_start_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_start_point_x, i));

		float3 normal = sps_normalize(end_point - other_deform_point);
		float radius = distance(other_start_point, radius_point);


		//If within the search range, we will count it
		found_other_data[found_count].xyz = other_deform_point;
		averageDirection += normal;
		found_other_data[found_count].w = radius;
		sum_positions += other_deform_point;

		found_count++;
		if(found_count >= __max_frot_count_find) break;
	}
	[branch]
	if(found_count == 0){
		// Initialize outputs to defaults
		frot_found = false;
		use_position = float3(0, 0, 0);
		use_normal = float3(0, 0, 0);
		return;
	}

	averageDirection = normalize(averageDirection);

	found_other_data[found_count].xyz = search_from_point;
	found_other_data[found_count].w = search_radius;
	found_count ++;

	float3 averageCenter = sum_positions / (float)found_count;

	// Determine the furthest ahead position along the new normal
	float maxProj = dot(found_other_data[0].xyz, averageDirection);
	[unroll]
	for (uint m_idx = 1; m_idx < __max_frot_count; m_idx++) {
		if (m_idx < found_count) {
			float proj = dot(found_other_data[m_idx].xyz, averageDirection);
			maxProj = max(maxProj, proj);
		}
	}

	//Shift the penetration point
	float centerProj = dot(averageCenter, averageDirection);
	float3 forwardShift = ((maxProj - centerProj) * averageDirection) + (search_penetrator_length * 0.25 * averageDirection);
	averageCenter += forwardShift;

	//Define 2D Plane Basis (Right / Forward)
	float3 upVec = abs(averageDirection.y) > 0.99f ? float3(1, 0, 0) : float3(0, 1, 0);
	float3 right = normalize(cross(upVec, averageDirection));
	float3 forward = normalize(cross(averageDirection, right));


	// Project to 2D Plane & Calculate Angles
	float angles[__max_frot_count];

	[unroll]
    for (uint j = 0; j < __max_frot_count; j++) {
        if(j < found_count) {
            float3 delta = found_other_data[j].xyz - averageCenter;
            angles[j] = atan2(dot(delta, forward), dot(delta, right)); //Y and X 
        } else {
            angles[j] = 999.0f; //End up sorted into the last place, over the angle limit for a full circle so will always be sorted into last
        }
    }

    

	//Track which index is our penetrator
	uint my_index = found_count - 1;

	#define SORT_SWAP(i, j) \
    if(angles[i] > angles[j]) { \
        if (my_index == i) my_index = j; \
        else if (my_index == j) my_index = i; \
        /* Swap Angles */ \
        float temp_ang = angles[i]; \
        angles[i] = angles[j]; \
        angles[j] = temp_ang; \
        /* Swap other penetrator data */ \
        float4 temp_data = found_other_data[i]; \
        found_other_data[i] = found_other_data[j]; \
        found_other_data[j] = temp_data; \
    }
	//static swaps to sort the 5 items instead of looping
	SORT_SWAP(0, 1); SORT_SWAP(3, 4);
    SORT_SWAP(2, 4); SORT_SWAP(2, 3);
    SORT_SWAP(0, 3); SORT_SWAP(0, 2);
    SORT_SWAP(1, 4); SORT_SWAP(1, 3); SORT_SWAP(1, 2);
    #undef SORT_SWAP

	//sums up the radius's, with the overlap
	float d[__max_frot_count];
	float sumD = 0;

	[unroll]
    for (uint m = 0; m < __max_frot_count; m++) {
        if(m < found_count) {
            float r1 = found_other_data[m].w;
            uint next_idx = (m + 1 == found_count) ? 0 : m + 1; 
            float r2 = found_other_data[next_idx].w;
            d[m] = r1 + r2 - (overlap_percent * min(r1, r2));
            sumD += d[m];
        }
    }

	//Calculate Radius and Target Angles
	float R = sumD * INV_TWO_PI;
	float thetas[__max_frot_count];
	thetas[0] = 0;
	
	[unroll]
	for (uint n = 0; n < __max_frot_count - 1; n++) {
		if(n < found_count - 1) {
            thetas[n + 1] = thetas[n] + (d[n] / sumD) * TWO_PI;
        }
	}


	// Calculate Optimal Rotation, average difference from re-calculated angles
	float sumCos = 0;
	float sumSin = 0;
	[unroll]
	for (uint p = 0; p < __max_frot_count; p++) {
		if(p < found_count) {
            float diff = angles[p] - thetas[p];
            sumCos += cos(diff);
            sumSin += sin(diff);
        }
	}
	float optRot = atan2(sumSin, sumCos);


	//Find this specific vertex's penetrator in the sorted data
	float finalAngle = thetas[my_index] + optRot;

	float localX = R * cos(finalAngle);
	float localY = R * sin(finalAngle);
	use_position = averageCenter + (localX * right) + (localY * forward);
	use_normal = averageDirection;
	frot_found = true;
}

//Gathers info for frotting mode, on ops penetrator locations. Returns data on the first 5 penetrators that are within range, assuming the current searching item is a penetrator
void ops_frot_gather(
    float3 search_from_point, float3 search_normal, float search_radius, float search_to_max_distance, float search_penetrator_length,
    uint self_ID, uint self_avatar_ID, int avoid_on_self_mask, int channel_id, float half_screen,
    out uint found_count, out float4 found_other_data[5], 
    out float3 group_average_normal, out float3 group_max_proj_point, out float group_length
) {

	found_count = 0;
    float3 sum_positions = search_from_point;
	float3 sum_end_positions = search_from_point + (search_normal * search_penetrator_length);
    float3 averageDirection = search_normal;
    group_length = search_penetrator_length;

	float sum_weights = 1.0;

	
	uint4 ID_space = getIDSpace(ID_SPACE_PENETRATOR);
    float3 read_data = readDataFrom_ID_TEX(ID_space.zw);
    int Total_Ids = min(_OPS_TextureExists() ? round(read_data.r * getMultiplierDecode()) : 0, 2000);

    float search_to_distance_sq = search_to_max_distance * search_to_max_distance;

	//end pos xyz, weighting w
	float4 found_end_points[5];

	[loop]
    for(int i = 1; i <= Total_Ids; i++){
        if(((uint)i) == self_ID) continue;

        const float isActive = round(readInlineFloatData(half_screen + offset_penetrator_is_active, i));
        if(isActive < 1) continue;

        const uint isFrotMode = readInlineUintData(half_screen + offset_penetrator_frot_mode, i);
        if(isFrotMode == 0) continue;

        const float channel_ID = round(readInlineFloatData(half_screen + offset_penetrator_channel_id, i));
        if(channel_id != -1 && channel_id != int(channel_ID)) continue;

        const uint avatar_ID = uint(readInlineUintData(half_screen + offset_penetrator_avatar_id, i));
        const int avoid_on_self_mask_other = int(round(readInlineFloatData(half_screen + offset_penetrator_avoid_on_self_mask, i)));

        if(self_avatar_ID != 0 && avatar_ID == self_avatar_ID && (avoid_on_self_mask == avoid_on_self_mask_other && avoid_on_self_mask != -1)) continue;

        float3 other_deform_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_deform_start_point_x, i));
        float3 end_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_end_point_x, i));

        float3 self_center = search_from_point + (search_normal * (search_penetrator_length * 0.5));
        float3 other_center = (other_deform_point + end_point) * 0.5;

        const float3 delta = other_center - self_center;
        const float distance_to_sq = dot(delta, delta);

        const float3 delta_other = (other_deform_point - end_point) * 1.6;
        const float other_search_length_square = dot(delta_other, delta_other);
		float actual_cutoff_sq = min(search_to_distance_sq, other_search_length_square);

        if(distance_to_sq > actual_cutoff_sq) continue;

		//distance fading
        float actual_cutoff = sqrt(actual_cutoff_sq);
        float fade_start = actual_cutoff * 0.6; //Starts fading at 60% of max range
        float fade_end = actual_cutoff;
        float dist_to_other = sqrt(distance_to_sq);

		float weight = 1.0 - sps_saturated_map(dist_to_other, fade_start, fade_end);
        if (weight <= 0.0) continue; //Skip if weight evaluates to 0
		
		
		float3 radius_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_radius_up_point_x, i));
        float3 other_start_point = sps_toLocal(readInlineFloat3Data(half_screen + offset_penetrator_world_start_point_x, i));
        float radius = distance(other_start_point, radius_point);

        float3 normal = sps_normalize(end_point - other_deform_point);

        found_other_data[found_count].xyz = other_deform_point;
        found_other_data[found_count].w = radius * weight;
		found_end_points[found_count].xyz = end_point;
		found_end_points[found_count].w = weight;

        averageDirection += normal * weight;
        sum_positions += other_deform_point * weight;
		sum_end_positions += end_point * weight;
		sum_weights += weight;

        found_count++;
        if(found_count >= 4) break;
    }

	[branch]
    if(found_count > 0) {
        averageDirection = normalize(averageDirection);
		//Add our penetrator to the found data
        found_other_data[found_count].xyz = search_from_point;
        found_other_data[found_count].w = search_radius;
		found_end_points[found_count].xyz = search_from_point + (search_normal * search_penetrator_length);
        found_end_points[found_count].w = 1.0;
		found_count++;

        float3 group_average_center = sum_positions / sum_weights;
		float3 group_average_end_center = sum_end_positions / sum_weights;
        group_average_normal = averageDirection;

        // Find the furthest projected point along the new normal (NO forward shift yet)
		
		float centerProj = dot(group_average_center, averageDirection);
		float centerEndProj = dot(group_average_end_center, averageDirection);

        float maxProj = centerProj;
		float maxEndProj = centerEndProj;

        [unroll]
        for (uint m_idx = 0; m_idx < 5; m_idx++) {
            if (m_idx < found_count) {
				float weight = found_end_points[m_idx].w;

				float rawProj = dot(found_other_data[m_idx].xyz, averageDirection);
                float rawEndProj = dot(found_end_points[m_idx].xyz, averageDirection);

				//Lerp each check, so that is all smooth

				float effectiveProj = lerp(centerProj, rawProj, weight);
                float effectiveEndProj = lerp(centerEndProj, rawEndProj, weight);
                
                maxProj = max(maxProj, effectiveProj);
                maxEndProj = max(maxEndProj, effectiveEndProj);
            }
        }
		group_max_proj_point = group_average_center + ((maxProj - centerProj) * averageDirection);
        group_length = max(0.0, maxEndProj - maxProj);
    } else {
        //Default to penetrator search values
        group_average_normal = search_normal;
        group_max_proj_point = search_from_point;
    }
}

//Applies info from frotting mode gather function
void ops_frot_apply(
    uint found_count, in float4 found_other_data[5], inout float3 group_average_projected_center, inout float3 group_average_normal, 
    float group_length, float search_penetrator_length, float overlap_percent,
    int found_orifice_id, float3 orifice_pos, float3 orifice_normal, uint orifice_direction,
	out float3 frot_offset, out float new_radius, out float lerp_factor
) {
    #ifndef TWO_PI
        #define TWO_PI 6.28318530718f
    #endif
    #ifndef INV_TWO_PI
        #define INV_TWO_PI 0.159154943f
    #endif

	lerp_factor = 0.0;

	float3 forwardShift = (search_penetrator_length * 0.25 * group_average_normal);
	group_average_projected_center + forwardShift;
    if (found_orifice_id != -1) {
        float dist_to_hole = distance(group_average_projected_center, orifice_pos);
        // Blend boundaries based on the longest penetrator in the group
		//Uhh idk what went wrong with the maths here, but this works. needs looking into some more
        float blend_start = group_length * 1.6;
        float blend_end = group_length * 1.35; //Really this should just be 1.0, but thats like 50% down the frot group
        lerp_factor = 1.0 - sps_saturated_map(dist_to_hole, blend_end, blend_start);

        group_average_projected_center = lerp(group_average_projected_center, orifice_pos, lerp_factor);
        
		//for reverse holes
		float3 target_normal = -orifice_normal;
        if (dot(group_average_normal, target_normal) < 0.0 && orifice_direction == OPS_hole_entry_direction_TWO_WAY) {
            target_normal = -target_normal; 
        }
		group_average_normal = normalize(lerp(group_average_normal, target_normal, lerp_factor));
    } else {
		//group_average_projected_center += forwardShift;
    }

	//2D Plane Projection at the orifice for organising where penetrators go
    float3 upVec = abs(group_average_normal.y) > 0.99f ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 right = normalize(cross(upVec, group_average_normal));
    float3 forward = normalize(cross(group_average_normal, right));

    float angles[5];
    [unroll]
    for (uint j = 0; j < 5; j++) {
        if(j < found_count) {
            float3 delta = found_other_data[j].xyz - group_average_projected_center;
            angles[j] = atan2(dot(delta, forward), dot(delta, right));
        } else {
            angles[j] = 999.0f;
        }
    }

	uint my_index = found_count - 1;

	//Sort the orifices by angle
    #define SORT_SWAP(i, j) \
    if(angles[i] > angles[j]) { \
        if (my_index == i) my_index = j; \
        else if (my_index == j) my_index = i; \
        float temp_ang = angles[i]; \
		angles[i] = angles[j]; \
		angles[j] = temp_ang; \
        float4 temp_data = found_other_data[i]; \
		found_other_data[i] = found_other_data[j]; \
		found_other_data[j] = temp_data; \
    }
    SORT_SWAP(0, 1); SORT_SWAP(3, 4);
    SORT_SWAP(2, 4); SORT_SWAP(2, 3);
    SORT_SWAP(0, 3); SORT_SWAP(0, 2);
    SORT_SWAP(1, 4); SORT_SWAP(1, 3); SORT_SWAP(1, 2);
    #undef SORT_SWAP

	// 3. Spacing Math
    float d[5];
    float sumD = 0;

    [unroll]
    for (uint m = 0; m < 5; m++) {
        if(m < found_count) {
            float r1 = found_other_data[m].w;
            uint next_idx = (m + 1 == found_count) ? 0 : m + 1; 
            float r2 = found_other_data[next_idx].w;
            d[m] = r1 + r2 - (overlap_percent * min(r1, r2));
            sumD += d[m];
        }
    }

    new_radius = sumD * INV_TWO_PI;
    float thetas[5];
    thetas[0] = 0;
    [unroll]
    for (uint n = 0; n < 4; n++) {
        if(n < found_count - 1) {
            thetas[n + 1] = thetas[n] + (d[n] / sumD) * TWO_PI;
        }
    }

    float sumCos = 0; float sumSin = 0;
    [unroll]
    for (uint p = 0; p < 5; p++) {
        if(p < found_count) {
            float diff = angles[p] - thetas[p];
            sumCos += cos(diff);
			sumSin += sin(diff);
        }
    }
    float optRot = atan2(sumSin, sumCos);

    float finalAngle = thetas[my_index] + optRot;
    float localX = new_radius * cos(finalAngle);
    float localY = new_radius * sin(finalAngle);

	//The 3D offset from the group_average_projected_center to this penetrator
	frot_offset = (localX * right) + (localY * forward);
}

//Functions that will be usefull for deformation shaders, when they want to deform based on the location of a penetrator

//Searchest for the closest penetrator to the input point
void ops_search_closest_penetrator(){
    /*
    //Return the following:
        -Radius of the penetrator
        -Depth of the penetrator
        -ID of the penetrator - So that other data can be fetched after
    //TODO

    */
}
//Searches for the first 5 penetrators that are within range of the point
void ops_search_closest_penetrators(){
    //TODO. This should essentially return the IDs and depths of the 5 closest
}

#endif