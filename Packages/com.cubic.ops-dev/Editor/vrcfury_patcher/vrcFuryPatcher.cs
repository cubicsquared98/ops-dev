using UnityEditor;
using UnityEngine;
using System.IO;

namespace ops_dev.patchers
{
    public static class VRCFuryPatcher
    {
        [MenuItem("Tools/ops-dev/Apply VRCFury ops Patch")]
        public static void ApplyPatch()
        {
            // Default path when installed locally in the project
            string packagePath = Path.GetFullPath("Packages/com.vrcfury.vrcfury");
            
            if (!Directory.Exists(packagePath))
            {
                Debug.LogError($"[VRCFury Patcher] Package not found at {packagePath}. Ensure it is installed in the project's Packages folder.");
                return;
            }

            PatchFile(packagePath, 
                "Editor-Common/Builder/Haptics/SpsPatcher.cs",
                @"AddParamIfMissing(""COLOR"", ""spsColor"", ""float4"");",
                @"AddParamIfMissing(""COLOR"", ""spsColor"", ""float4""); //OPS patched
            AddParamIfMissing(""BLENDINDICES"", ""spsBlendIndices"", ""int4""); //OPS patched
            AddParamIfMissing(""BLENDWEIGHTS"", ""spsBlendWeights"", ""float4""); //OPS patched"
            );

            ReplaceEntireFile(packagePath,
            "SPS/sps_bezier.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_bezier.cginc");

            ReplaceEntireFile(packagePath,
            "SPS/sps_globals.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_globals.cginc");

            ReplaceEntireFile(packagePath,
            "SPS/sps_light.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_light.cginc");

            ReplaceEntireFile(packagePath,
            "SPS/sps_main.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_main.cginc");

            ReplaceEntireFile(packagePath,
            "SPS/sps_props.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_props.cginc");

            ReplaceEntireFile(packagePath,
            "SPS/sps_utils.cginc",
            "Packages/com.cubic.ops-dev/Editor/vrcfury_patcher/file_patches/sps_utils.cginc");


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
