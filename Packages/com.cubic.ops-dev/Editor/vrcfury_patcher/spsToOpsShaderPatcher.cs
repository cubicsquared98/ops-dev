using System.IO;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEngine;

namespace ops_dev.Patchers
{
    public static class SpsToOpsShaderPatcher
    {

        private static bool PatchLightSourceSearch(ref string shaderText){
            //Find and patch the sps light search function inputs
            string callPattern = @"(?<!void\s+)sps_light_search\s*\(";
            int callMatches = Regex.Matches(shaderText, callPattern).Count;
            if (callMatches > 0)
            {
                shaderText = Regex.Replace(shaderText, callPattern, "sps_light_search(float3(0, 0, 0), ");
                Debug.Log($"[OpsShaderPatcher] Updated {callMatches} existing call(s) to sps_light_search.");
            }
            else{
                Debug.LogError("[OpsShaderPatcher] Failed to find sps_light_search function calls.");
                return false;
            }

            //Update the function definition to accept the new parameter
            string defPattern = @"void\s+sps_light_search\s*\(";
            if (Regex.IsMatch(shaderText, defPattern))
            {
                shaderText = Regex.Replace(shaderText, defPattern, "void sps_light_search(\n    float3 local_search_pos,");
            }
            else
            {
                Debug.LogError("[OpsShaderPatcher] Failed to find sps_light_search definition.");
                return false;
            }

            //Update the distance calculation
            string distPattern = @"const\s+float\s+distance\s*=\s*length\s*\(\s*lightLocalPos\[i\]\s*\)\s*;";
            if (Regex.IsMatch(shaderText, distPattern))
            {
                shaderText = Regex.Replace(shaderText, distPattern, "const float distance = length(lightLocalPos[i] - local_search_pos);");
            }
            else
            {
                Debug.LogError("[OpsShaderPatcher] Failed to find lightLocalPos distance calculation.");
                return false;
            }
            return true;
        }

        private static bool PatchShaderProps(ref string shaderText){

        string opsProperties = @"
        [Header(OPS)]
        _OPS_HASH_SEED (""Hash seed INTEGER"", Int) = 0
        _OPS_SKINNED_BONES_OFFSET (""Bones from index"", Int) = 0
        _OPS_SKINNED_BONES_ENABLED (""enable skinned bone mode"", Int) = 0
        _OPS_PENETRATOR_AVOID_ON_SELF_MASK (""Avoid on self channel (to select set higher than -1)"", Int) = -1
        _OPS_ID_CHANNEL(""OPS Channel (to select set higher than -1)"", Int) = -1
        _OPS_FROT_MODE(""enable frot mode"", Int) = 0
";
            //Find the Properties block and inject ops properties
            shaderText = Regex.Replace(shaderText, @"Properties\s*\{", $"Properties {{{opsProperties}");
            return true;
        }

        private static bool PatchBezierSolver(ref string shaderText){

            string bezierPattern = @"(up\s*=\s*sps_nearest_normal\s*\(\s*forward\s*,\s*approximateUp\s*\)\s*;\s*\})";
            
            string bezierReplacement = @"$1

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
}";

            int bezierMatches = Regex.Matches(shaderText, bezierPattern).Count;
            if (bezierMatches > 0)
            {
                //Replace the match with itself and the new bezier function
                shaderText = Regex.Replace(shaderText, bezierPattern, bezierReplacement);
                Debug.Log($"[OpsShaderPatcher] Injected sps_bezierSolve_ops in {bezierMatches} pass(es).");
            }
            else
            {
                Debug.LogError("[OpsShaderPatcher] Failed to find the end of the original bezier function. The regex pattern probably need updating.");
                return false;
            }
            return true;
        }

        private static bool PatchBoneWeightStructs(ref string shaderText){
            //Find a specific pass
            string passPattern = @"((?:CG|HLSL)PROGRAM)(.*?)(END(?:CG|HLSL))";
            int passesPatched = 0;

            shaderText = Regex.Replace(shaderText, passPattern, passMatch =>
            {
                string prefix = passMatch.Groups[1].Value;   //CGPROGRAM or HLSLPROGRAM
                string passBody = passMatch.Groups[2].Value; //The code inside the pass
                string suffix = passMatch.Groups[3].Value;   //ENDCG or ENDHLSL

                //Check if THIS SPECIFIC PASS has BLENDINDICES/BLENDWEIGHTS within it
                Match localIndicesMatch = Regex.Match(passBody, @"(\w+)\s*:\s*BLENDINDICES", RegexOptions.IgnoreCase);
                string indicesName = localIndicesMatch.Success ? localIndicesMatch.Groups[1].Value : "opsBlendIndices";

                Match localWeightsMatch = Regex.Match(passBody, @"(\w+)\s*:\s*BLENDWEIGHTS", RegexOptions.IgnoreCase);
                string weightsName = localWeightsMatch.Success ? localWeightsMatch.Groups[1].Value : "opsBlendWeights";

                //Locate SpsInputs
                string structPattern = @"(struct\s+SpsInputs[^\{]*)\{([^}]+)\}";
                
                passBody = Regex.Replace(passBody, structPattern, structMatch =>
                {
                    string structDeclaration = structMatch.Groups[1].Value;
                    string structBody = structMatch.Groups[2].Value;

                    // If the semantics were NOT found in THIS pass, inject them here
                    if (!localIndicesMatch.Success)
                    {
                        structBody += "\n            uint4 opsBlendIndices : BLENDINDICES;";
                    }
                    
                    if (!localWeightsMatch.Success)
                    {
                        structBody += "\n            float4 opsBlendWeights : BLENDWEIGHTS;";
                    }
                    structBody += $"\n#define OPS_STRUCT_BLENDINDICES_NAME {indicesName}";
                    structBody += $"\n#define OPS_STRUCT_BLENDWEIGHTS_NAME {weightsName}\n";

                    passesPatched++;
                    return $"{structDeclaration}{{{structBody}}}";
                });

                // Reconstruct the pass block with the modifications
                return $"{prefix}{passBody}{suffix}";
            }, RegexOptions.Singleline);

            if (passesPatched > 0)
            {
                Debug.Log($"[OpsShaderPatcher] Successfully patched SpsInputs structs in {passesPatched} pass(es).");
                return true;
            }
            else
            {
                Debug.LogError("[OpsShaderPatcher] Failed to find SpsInputs in any shader pass.");
                return false;
            }


        }

        private static bool ReplaceSpsApplyFunction(ref string shaderText, bool AddBoneWeights){
            //Replace sps_apply_real with ops_apply
            string applyPattern = @"sps_apply_real\s*\(\s*o\.SPS_STRUCT_POSITION_NAME\s*,\s*o\.SPS_STRUCT_NORMAL_NAME\s*,\s*o\.SPS_STRUCT_TANGENT_NAME\s*,\s*o\.SPS_STRUCT_SV_VertexID_NAME\s*,\s*o\.SPS_STRUCT_COLOR_NAME\s*\)\s*;";
            
            string opsApplyReplacement = @"ops_apply(
        o.SPS_STRUCT_POSITION_NAME,
        o.SPS_STRUCT_NORMAL_NAME,
        o.SPS_STRUCT_TANGENT_NAME,
        o.SPS_STRUCT_SV_VertexID_NAME,
        o.SPS_STRUCT_COLOR_NAME
    );";
            
        string opsApplyReplacementBoneWeights = @"ops_apply(
        o.SPS_STRUCT_POSITION_NAME,
        o.SPS_STRUCT_NORMAL_NAME,
        o.SPS_STRUCT_TANGENT_NAME,
        o.SPS_STRUCT_SV_VertexID_NAME,
        o.SPS_STRUCT_COLOR_NAME,
        o.OPS_STRUCT_BLENDINDICES_NAME,
        o.OPS_STRUCT_BLENDWEIGHTS_NAME
    );";
            
            int matchCount = Regex.Matches(shaderText, applyPattern).Count;
            if (matchCount > 0)
            {
                if(AddBoneWeights){
                    shaderText = Regex.Replace(shaderText, applyPattern, opsApplyReplacementBoneWeights);
                }
                else{
                    shaderText = Regex.Replace(shaderText, applyPattern, opsApplyReplacement);
                }
                Debug.Log($"[OpsShaderPatcher] Successfully patched {matchCount} instance(s) of sps.");
            }
            else
            {
                Debug.LogError("[OpsShaderPatcher] Failed to find sps_apply_real in the shader text. There is either no sps, or the regex pattern needs updating.");
                return false;
            }
            return true;
        }

        private static bool InjectOpsMain(ref string shaderText, string opsMainFilePath){
            //Inject ops code
            if (!File.Exists(opsMainFilePath))
            {
                Debug.LogError($"[OpsShaderPatcher] Ops include file not found at: {opsMainFilePath}");
                return false;
            }

            string opsIncludeCode = File.ReadAllText(opsMainFilePath);
            //Inject ops logic above the sps_apply_real function 
            string injectionAnchor = "void sps_apply_real(";

            if (shaderText.Contains(injectionAnchor))
            {
                // Injects the contents of the file directly above every instance of 'void sps_apply('
                shaderText = shaderText.Replace(injectionAnchor, $"{opsIncludeCode}\n\n{injectionAnchor}");
                Debug.Log("[OpsShaderPatcher] Successfully injected ops_apply.");
            }
            else
            {
                Debug.LogError($"[OpsShaderPatcher] Failed to find '{injectionAnchor}' in the shader text.");
                return false;
            }
            return true;
        }

        //Copies the material's current shader, applies OPS patches, and saves it, 
        //New shader is applied to the material
        public static bool PatchAndAssignOpsShader(Material material, string opsVersion, bool AddBoneWeightStructs)
        {
            string saveFolderPath = Path.Combine("Packages/com.cubic.ops-dev/Runtime/ops_generated", "PatchedShaders").Replace("\\", "/");
            const string opsMainFilePath = "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/ops_main_patch.cginc";

            if (material == null || material.shader == null){
                Debug.LogError("[OpsShaderPatcher] No material or shader found. Cannot patch in ops");
                return false;
            }

            Shader originalShader = material.shader;
            string originalPath = AssetDatabase.GetAssetPath(originalShader);

            if (string.IsNullOrEmpty(originalPath) || !originalPath.EndsWith(".shader"))
            {
                Debug.LogError($"[OpsShaderPatcher] Cannot patch shader '{originalShader.name}' on material '{material.name}'. Valid .shader file not found.");
                return false;
            }

            if (originalShader.name.EndsWith("_ops_patched"))
            {
                Debug.LogError($"[OpsShaderPatcher] Shader '{originalShader.name}' on material '{material.name}' is already patched.");
                return false;
            }

            string originalFileName = Path.GetFileNameWithoutExtension(originalPath);
            string newInternalShaderName = $"Hidden/ops/patched/{originalFileName}_ops_patched";

            //Prevent poi complaints
            if(originalShader.name.StartsWith("Hidden/Locked/")){
                newInternalShaderName = $"Hidden/Locked/ops/patched/{originalFileName}_ops_patched";
            }
            
            string shaderText = File.ReadAllText(originalPath);

            //Overwrite anyways
            // if (shaderText.Contains("#define OPS_VERSION"))
            // {
            //     Debug.LogError($"[OpsShaderPatcher] Shader already contains OPS_VERSION. Skipping patch.");
            //     return false;
            // }
            //WE just overwrite this
            // else if(Shader.Find(newInternalShaderName)){
            //     Debug.LogError($"[OpsShaderPatcher] Shader name already Exists but no ops version found. Skipping patch.");
            //     return;
            // }


            //TODO: https://regex101.com/
            //Helps with regex matching stuff


            //______________PATCHING START__________________
            //Matches Shader "Any/Path/Name" -> Shader "Hidden/ops/patched/{prev_shader_file_name}_ops_patched"
            shaderText = Regex.Replace(shaderText, @"Shader\s+""([^""]+)""", $"Shader \"{newInternalShaderName}\"");

            //Adds the version define at the top of every CGPROGRAM / HLSLPROGRAM block
            shaderText = shaderText.Replace("CGPROGRAM", $"CGPROGRAM\n              #define OPS_VERSION \"{opsVersion}\"");
            shaderText = shaderText.Replace("HLSLPROGRAM", $"HLSLPROGRAM\n              #define OPS_VERSION \"{opsVersion}\"");

            if(!PatchShaderProps(ref shaderText)) return false;

            if(!PatchLightSourceSearch(ref shaderText)) return false;

            if(!PatchBezierSolver(ref shaderText)) return false;

            if(AddBoneWeightStructs){
                if(!PatchBoneWeightStructs(ref shaderText)) return false;
            }


            if(!ReplaceSpsApplyFunction(ref shaderText, AddBoneWeightStructs)) return false;

            if(!InjectOpsMain(ref shaderText, opsMainFilePath)) return false;

            //_________PATCHING END_____________

            //Save new shader
            if (!Directory.Exists(saveFolderPath))
            {
                Directory.CreateDirectory(saveFolderPath);
            }
            string fileName = $"{originalFileName}_ops_patched.shader";
            string fullPath = Path.Combine(saveFolderPath, fileName).Replace("\\", "/");

            File.WriteAllText(fullPath, shaderText);
            AssetDatabase.ImportAsset(fullPath);


            //Assign patched shader to material
            Shader patchedShader = AssetDatabase.LoadAssetAtPath<Shader>(fullPath);
            if (patchedShader != null)
            {
                material.shader = patchedShader;
                EditorUtility.SetDirty(material);
                Debug.Log($"[OpsShaderPatcher] Shader patched and assigned to material '{material.name}'. Saved to: {fullPath}");
            }
            else
            {
                Debug.LogError($"[OpsShaderPatcher] Failed to load the newly patched shader at path: {fullPath}");
                return false;
            }

            return true;
        }
    }
}