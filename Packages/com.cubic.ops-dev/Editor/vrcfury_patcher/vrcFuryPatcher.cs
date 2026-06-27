using UnityEditor;
using UnityEngine;
using System.IO;

namespace ops_dev.patchers
{
    public static class VRCFuryPatcher
    {
        [MenuItem("Tools/ops-dev/Patch vrcfury sps shader for ops compatibility")]
        public static void ApplyPatch()
        {
            string packagePath = Path.GetFullPath("Packages/com.vrcfury.vrcfury");
            
            if (!Directory.Exists(packagePath))
            {
                Debug.LogError($"[VRCFury Patcher] Package not found at {packagePath}. Ensure it is installed in the project's Packages folder.");
                return;
            }

            //The following modifications make the sps penetrator shader compatible with ops

            //Patch in blendicies and blend weights, so that bone scaling in x/y axis can be applied
            PatchFile(packagePath, 
                "Editor-Common/Builder/Haptics/SpsPatcher.cs",
                @"AddParamIfMissing(""COLOR"", ""spsColor"", ""float4"");",
                @"AddParamIfMissing(""COLOR"", ""spsColor"", ""float4""); //OPS patched
            AddParamIfMissing(""BLENDINDICES"", ""spsBlendIndices"", ""int4""); //OPS patched
            AddParamIfMissing(""BLENDWEIGHTS"", ""spsBlendWeights"", ""float4""); //OPS patched"
            );

            //Patch in local search position into light source search
            PatchFile(packagePath, 
                "SPS/sps_light.cginc",
                @"const float distance = length(lightLocalPos[i]);",
                @"const float distance = length(lightLocalPos[i] - local_search_pos); //OPS patched"
            );
            PatchFile(packagePath, 
                "SPS/sps_light.cginc",
                @"void sps_light_search(",
                @"void sps_light_search(
	float3 local_search_pos,");


            //Patch in the properties that ops requires
            PatchFile(packagePath,
                "SPS/sps_props.cginc",
                @"[Header(SPS)]",
                @"[Header(OPS)]

_OPS_HASH_SEED (""Hash seed INTEGER"", Int) = 0
_OPS_SKINNED_BONES_OFFSET (""Bones from index"", Int) = 0
_OPS_SKINNED_BONES_ENABLED (""enable skinned bone mode"", Int) = 0
_OPS_PENETRATOR_AVOID_ON_SELF_MASK (""Avoid on self channel (to select set higher than -1)"", Int) = -1
_OPS_ID_CHANNEL(""OPS Channel (to select set higher than -1)"", Int) = -1
_OPS_FROT_MODE(""enable frot mode"", Int) = 0

[Header(SPS)]");

            PatchFile(packagePath, 
                "SPS/sps_bezier.cginc",
                @"	up = sps_nearest_normal(forward, approximateUp);
}",
                @"	up = sps_nearest_normal(forward, approximateUp);
}

//modifications:
//	Reduce required gpu registers (removed large array that gets populated with bezier curve points as there is no need to store all that)
//  Pass in upwards vector direction
//
void sps_bezierSolve_ops(float3 p0, float3 p1, float3 p2, float3 p3, float lookingForLength, float3 initialUp, out float curveLength, out float3 position, out float3 forward, out float3 up)
{
	#define SPS_BEZIER_SAMPLES 50
	
	float totalLength = 0;
	float3 lastPoint = p0;
	float3 lastUp = initialUp;

	//Store our target values once we pass the requested length
    float adjustedT = 1.0;
    float3 approximateUp = initialUp;
    bool foundT = false;

	//Track the previous point for interpolation
    float prev_t = 0;
    float prev_length = 0;
    float3 prev_up = initialUp;

	for(int i = 1; i <= SPS_BEZIER_SAMPLES; i++)
    {
        const float t = float(i) / SPS_BEZIER_SAMPLES;
        const float3 currentPoint = sps_bezier(p0, p1, p2, p3, t);
        const float3 currentForward = sps_normalize(sps_bezierDerivative(p0, p1, p2, p3, t));
        const float3 currentUp = sps_nearest_normal(currentForward, lastUp);

        totalLength += distance(currentPoint, lastPoint);

        //If we haven't found the target length yet, check if we just crossed it
        if (!foundT && lookingForLength <= totalLength)
        {
            const float fraction = sps_map(lookingForLength, prev_length, totalLength, 0, 1);
            adjustedT = lerp(prev_t, t, fraction);
            approximateUp = lerp(prev_up, currentUp, fraction);
            foundT = true;

			//The rest of the length still needs calculating for correct distance calculations
		}

        lastPoint = currentPoint;
        lastUp = currentUp;

        prev_t = t;
        prev_length = totalLength;
        prev_up = currentUp;
    }

    if (!foundT) {
        approximateUp = lastUp;
    }


    const float finalT = saturate(adjustedT);
    curveLength = totalLength;
    position = sps_bezier(p0, p1, p2, p3, finalT);
    forward = sps_normalize(sps_bezierDerivative(p0, p1, p2, p3, finalT));
    up = sps_nearest_normal(forward, approximateUp);
}
");

            ReplaceEntireFile(packagePath,
            "SPS/sps_main.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_main.cginc");

            // Refresh the Asset Database to trigger a script recompile
            AssetDatabase.Refresh();
            Debug.Log("[VRCFury Patcher] Patching complete. Recompiling scripts...");
        }

        private static void PatchFile(string basePath, string relativeFilePath, string originalText, string newText)
        {
            string fullPath = Path.Combine(basePath, relativeFilePath);

            if (!File.Exists(fullPath))
            {
                Debug.LogWarning($"[VRCFury Patcher] File not found: {relativeFilePath}");
                return;
            }

            string content = File.ReadAllText(fullPath);

            if (content.Contains(newText))
            {
                Debug.Log($"[VRCFury Patcher] Already patched: {relativeFilePath}");
                return;
            }

            if (content.Contains(originalText))
            {
                content = content.Replace(originalText, newText);
                File.WriteAllText(fullPath, content);
                Debug.Log($"[VRCFury Patcher] Successfully patched: {relativeFilePath}");
            }
            else
            {
                Debug.LogError($"[VRCFury Patcher] Failed to find the target text in: {relativeFilePath}. Check for whitespace or line-ending mismatches.");
            }
        }

        private static void ReplaceEntireFile(string basePath, string relativeTargetFilePath, string sourceFilePath)
        {
            string fullTargetPath = Path.Combine(basePath, relativeTargetFilePath);

            //Check if the file we want to overwrite exists
            if (!File.Exists(fullTargetPath))
            {
                Debug.LogWarning($"[VRCFury Patcher] Target file to replace not found in package: {relativeTargetFilePath}");
                return;
            }

            //Check if the replacement file exists
            if (!File.Exists(sourceFilePath))
            {
                Debug.LogError($"[VRCFury Patcher] Source replacement file not found at: {sourceFilePath}");
                return;
            }

            // Copy the source file over, overwriting it
            File.Copy(sourceFilePath, fullTargetPath, true);
            Debug.Log($"[VRCFury Patcher] Successfully replaced entire file: {relativeTargetFilePath}");
        }
    }
}
