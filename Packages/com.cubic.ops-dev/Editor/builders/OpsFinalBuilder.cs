//#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using VRC.SDKBase.Editor.BuildPipeline;
using VRC.SDK3.Avatars.Components;
using ops_dev.Components;

namespace ops_dev.Editor.Builders {
    public class OpsFinalBuilder : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -99;

        public bool OnPreprocessAvatar(GameObject avatarGameObject){
            return BuildFinalOps(avatarGameObject);
        }


        public static bool BuildFinalOps(GameObject avatarGameObject)
        {
            //Finds the base avatar ID component, and adds the ID and data grabs, and screen clear material / shaders to it.

            OpsIDWriter[] writers = avatarGameObject.GetComponentsInChildren<OpsIDWriter>(true);
            OpsIDWriter avatar_ID_Base = null; // Holds transform and hashID to use for avi

            //no point processing anything if there are no ID writers - means no ops exists
            if(writers.Length == 0){
                return true;
            }

            foreach (OpsIDWriter writer in writers)
            {
                if(writer.idSpace == OpsIDWriter.IDSpace.avatar) // Avatar ID space
                {
                    avatar_ID_Base = writer;
                    break;
                }
            }

            if(avatar_ID_Base == null){
                Debug.LogError("[OpsFinalBuilder] Build Failed: no avatar ID base component found");
                return false;
            }

            OpsAvatarComponent[] ops_components = avatarGameObject.GetComponentsInChildren<OpsAvatarComponent>(true);
            if(ops_components.Length < 1){
                Debug.LogError("[OpsFinalBuilder] Build Failed: no avatar ID base component found");
                return false;
            }
            OpsAvatarComponent ops_component = ops_components[0];
            if(ops_component == null){
                Debug.LogError("[OpsFinalBuilder] Build Failed: avatar ID base component is null");
                return false;
            }

            //Find the SMR that belongs to this 
            SkinnedMeshRenderer avatar_id_writer = avatar_ID_Base.GetComponentInChildren<SkinnedMeshRenderer>(true);
            if(avatar_id_writer == null){
                Debug.LogError("[OpsFinalBuilder] Build Failed: failed to find SMR on avi base component");
                return false;
            }

            List<Material> currentMaterials = new List<Material>();
            avatar_id_writer.GetSharedMaterials(currentMaterials);

            currentMaterials.Add(ops_component.clear_screen_1);
            currentMaterials.Add(ops_component.clear_screen_2);
            currentMaterials.Add(ops_component.grab_ops_id_mat);
            currentMaterials.Add(ops_component.grab_ops_data_mat);

            avatar_id_writer.SetSharedMaterials(currentMaterials);

            //Toggle the main ops component when the ops components are toggled
            //Has no fail condition atm
            BuildOpsToggles(avatarGameObject, ops_component);



            //Could make animations so that grab_ops_id_mat and grab_ops_data_mat are toggled individually, instead of at the same time.
            //This was initialy an idea to lesson the amount of game freezing that happens on initial loading of grabpasses, but isnt much an issue anymore. Was actually from having a large geom shader on a large object causing the issue.
            return true;
        }

        public static bool BuildOpsToggles(GameObject avatarGameObject, OpsAvatarComponent ops_component){

            string savePath = "Packages/com.cubic.ops-dev/Runtime/Ops_Generated";
            if (!AssetDatabase.IsValidFolder(savePath)) AssetDatabase.CreateFolder("Packages/com.cubic.ops-dev/Runtime", "Ops_Generated");

            string baseObjPath = AnimationUtility.CalculateTransformPath(ops_component.gameObject.transform, avatarGameObject.transform);

            //Target paths of ops components
            HashSet<string> targetOpsPaths = new HashSet<string>();

            // Map to store explicit target paths for Penetrators and Orifices (such as sps component toggles)
            Dictionary<string, List<string>> targetToExplicitPathsMap = new Dictionary<string, List<string>>();

            // Map to store the SMR path associated with a specific penetrator to manipulate shadows
            Dictionary<string, string> targetToSmrPathMap = new Dictionary<string, string>();

            foreach (var pen in avatarGameObject.GetComponentsInChildren<OpsPenetrator>(true))
            {
                string penPath = AnimationUtility.CalculateTransformPath(pen.gameObject.transform, avatarGameObject.transform);
                targetOpsPaths.Add(penPath);

                //Map the mesh SMR path to disable shadows further on
                if (pen.penetratorMeshObject != null && pen.AutoDisableMeshShadowsOnDeformation)
                {
                    targetToSmrPathMap[penPath] = AnimationUtility.CalculateTransformPath(pen.penetratorMeshObject, avatarGameObject.transform);
                }

                // If an SPS component is assigned, calculate its path and store it
                if (pen.sps_component_parent != null)
                {
                    Transform bakedSpsPlug = pen.sps_component_parent.Find("BakedSpsPlug");
                    if (bakedSpsPlug != null)
                    {
                        string spsPath = AnimationUtility.CalculateTransformPath(bakedSpsPlug, avatarGameObject.transform);
                        targetToExplicitPathsMap[penPath] = new List<string> { spsPath };
                    }
                    else
                    {
                        Debug.LogWarning($"[OpsFinalBuilder] Penetrator '{pen.gameObject.name}' has an SPS component parent assigned, but no child named 'BakedSpsPlug' was found.");
                    }
                }
            }


            foreach (var ori in avatarGameObject.GetComponentsInChildren<OpsOrifice>(true))
            {
                //The animations should act upon the ActiveTarget, since that's what the ops logic builds under.
                //This will add two anims in for this if they are the same, but oh well.
                string targetPath = AnimationUtility.CalculateTransformPath(ori.ActiveTarget, avatarGameObject.transform);
                string oriPath = AnimationUtility.CalculateTransformPath(ori.gameObject.transform, avatarGameObject.transform);

                targetOpsPaths.Add(targetPath);

                List<string> priorityPaths = new List<string>();

                //Check for BakedSpsSocket on active target
                Transform socketChild = ori.ActiveTarget.Find("BakedSpsSocket");
                //if (socketChild == null) socketChild = ori.gameObject.transform.Find("BakedSpsSocket");

                //Check for BakedSpsSocket on parent of active target
                if (socketChild == null && ori.ActiveTarget.parent != null) socketChild = ori.ActiveTarget.parent.Find("BakedSpsSocket");
                //if (socketChild == null && ori.gameObject.transform.parent != null) socketChild = ori.gameObject.transform.parent.Find("BakedSpsSocket");

                //If SPS Socket is found, it should take priority
                if (socketChild != null)
                {
                    priorityPaths.Add(AnimationUtility.CalculateTransformPath(socketChild, avatarGameObject.transform));
                }

                //Add the actual ops orifice game object if its not the same as the active target
                if (oriPath != targetPath)
                {
                    priorityPaths.Add(oriPath);
                }

                //And add the active target path itself
                priorityPaths.Add(targetPath);

                targetToExplicitPathsMap[targetPath] = priorityPaths;
            }
            
            
            // foreach (var ori in avatarGameObject.GetComponentsInChildren<OpsOrifice>(true))
            // {
            //     targetOpsPaths.Add(AnimationUtility.CalculateTransformPath(ori.gameObject.transform, avatarGameObject.transform));
            // }

            if(targetOpsPaths.Count < 1){
                return true;
            }

            VRCAvatarDescriptor descriptor = avatarGameObject.GetComponent<VRCAvatarDescriptor>();
            if(descriptor == null || !descriptor.customizeAnimationLayers){
                return true;
            }

            bool descriptorModified = false;

            for (int i = 0; i < descriptor.baseAnimationLayers.Length; i++)
            {
                if (!descriptor.baseAnimationLayers[i].isDefault && descriptor.baseAnimationLayers[i].animatorController != null)
                {
                    RuntimeAnimatorController newController = ProcessController(descriptor.baseAnimationLayers[i].animatorController, baseObjPath, targetOpsPaths, targetToExplicitPathsMap, targetToSmrPathMap, savePath, avatarGameObject);
                    if (newController != descriptor.baseAnimationLayers[i].animatorController)
                    {
                        descriptor.baseAnimationLayers[i].animatorController = newController;
                        descriptorModified = true;
                    }
                }
            }
            for (int i = 0; i < descriptor.specialAnimationLayers.Length; i++)
            {
                if (!descriptor.specialAnimationLayers[i].isDefault && descriptor.specialAnimationLayers[i].animatorController != null)
                {
                    RuntimeAnimatorController newController = ProcessController(descriptor.specialAnimationLayers[i].animatorController, baseObjPath, targetOpsPaths, targetToExplicitPathsMap, targetToSmrPathMap, savePath, avatarGameObject);
                    if (newController != descriptor.specialAnimationLayers[i].animatorController)
                    {
                        descriptor.specialAnimationLayers[i].animatorController = newController;
                        descriptorModified = true;
                    }
                }
            }

            if (descriptorModified)
            {
                EditorUtility.SetDirty(descriptor);
            }
            return true;
        }

        private static RuntimeAnimatorController ProcessController(RuntimeAnimatorController originalController, string baseObjPath, HashSet<string> targetOpsPaths, Dictionary<string, List<string>> targetToExplicitPathsMap, Dictionary<string, string> targetToSmrPathMap, string savePath, GameObject avatarRoot)
        {
            string oldAssetPath = AssetDatabase.GetAssetPath(originalController);
            if (string.IsNullOrEmpty(oldAssetPath)) return originalController;

            string newControllerPath = Path.Combine(savePath, originalController.name + "_OpsFinalDupe.controller").Replace("\\", "/");

            //If we have already altered this controller / its already a duplicate
            if(oldAssetPath.StartsWith("Packages/com.cubic.ops-dev/Runtime/Ops_Generated")){
                newControllerPath = oldAssetPath;
            }


            AnimatorController duplicatedController;

            //Set the "duplicatedController" that we will be working on
            if (oldAssetPath == newControllerPath)
            {
                duplicatedController = originalController as AnimatorController;
            }
            else
            {
                if (!AssetDatabase.CopyAsset(oldAssetPath, newControllerPath)) return originalController;
                duplicatedController = AssetDatabase.LoadAssetAtPath<AnimatorController>(newControllerPath);
            }

            if (duplicatedController == null) return originalController;


            //Scan all clips to find every single GameObject path that gets toggled in this controller
            HashSet<string> allAnimatedPaths = new HashSet<string>();
            foreach (AnimationClip clip in duplicatedController.animationClips)
            {
                if (clip == null) continue;
                foreach (var binding in AnimationUtility.GetCurveBindings(clip))
                {
                    if (binding.type == typeof(GameObject) && binding.propertyName == "m_IsActive")
                    {
                        allAnimatedPaths.Add(binding.path);
                    }
                }
            }


            //Find closest animated parent of each ops component OR sps component toggle
            Dictionary<string, string> targetToClosestParentMap = new Dictionary<string, string>();
            foreach (string targetPath in targetOpsPaths)
            {
                bool foundExplicit = false;
                // Check priority paths first (SPS toggle > Component Path > Active Target Path)
                if (targetToExplicitPathsMap.TryGetValue(targetPath, out List<string> explicitPaths))
                {
                    foreach (string expPath in explicitPaths)
                    {
                        if (allAnimatedPaths.Contains(expPath))
                        {
                            targetToClosestParentMap[targetPath] = expPath;
                            foundExplicit = true;
                            break;
                        }
                    }
                }

                if (foundExplicit) continue;
                //If no enable animation found, then we search for nearest parent that is enabled.
                //Penetrator components should always have an sps component assigned to them, so they should have been caught by the above check.

                string closestParent = null;
                int maxParentLength = -1;

                foreach (string animPath in allAnimatedPaths)
                {
                    // Exact match or closest parent string
                    if (animPath == targetPath)
                    {
                        closestParent = animPath;
                        break; 
                    }
                    else if (animPath == "" || targetPath.StartsWith(animPath + "/"))
                    {
                        if (animPath.Length > maxParentLength)
                        {
                            closestParent = animPath;
                            maxParentLength = animPath.Length;
                        }
                    }
                }

                if (closestParent != null)
                {
                    targetToClosestParentMap[targetPath] = closestParent;
                }
            }

            //Map the closest animated parents to their respective penetrator SMR paths 
            Dictionary<string, List<string>> parentToSmrPaths = new Dictionary<string, List<string>>();
            foreach (var kvp in targetToClosestParentMap)
            {
                string targetPath = kvp.Key;
                string closestParent = kvp.Value;

                if (targetToSmrPathMap.TryGetValue(targetPath, out string smrPath))
                {
                    if (!parentToSmrPaths.ContainsKey(closestParent))
                    {
                        parentToSmrPaths[closestParent] = new List<string>();
                    }
                    if (!parentToSmrPaths[closestParent].Contains(smrPath))
                    {
                        parentToSmrPaths[closestParent].Add(smrPath);
                    }
                }
            }


            Dictionary<AnimationClip, AnimationClip> clipReplacements = new Dictionary<AnimationClip, AnimationClip>();

            foreach (AnimationClip clip in duplicatedController.animationClips)
            {
                if (clip == null || clipReplacements.ContainsKey(clip)) continue;

                AnimationClip modifiedClip = ProcessClip(clip, baseObjPath, targetToClosestParentMap, parentToSmrPaths, savePath, avatarRoot);
                if (modifiedClip != null)
                {
                    clipReplacements.Add(clip, modifiedClip);
                }
            }

            //If nothing was modified and IF we created a NEW controller because the new and old paths are different, then we can remove the new controller and return the old one
            if (clipReplacements.Count == 0 && oldAssetPath != newControllerPath)
            {
                AssetDatabase.DeleteAsset(newControllerPath);
                return originalController;
            }
            //Else we process the controller, which will do nothing if no clip replacements

            foreach (AnimatorControllerLayer layer in duplicatedController.layers)
            {
                OpsAnimationRetargeter.ReplaceClipsInStateMachine(layer.stateMachine, clipReplacements);
            }

            EditorUtility.SetDirty(duplicatedController);
            AssetDatabase.SaveAssets();

            return duplicatedController;
        }

        private static AnimationClip ProcessClip(AnimationClip originalClip, string baseObjPath, Dictionary<string, string> targetToClosestParentMap, Dictionary<string, List<string>> parentToSmrPaths, string savePath, GameObject avatarRoot)
        {
            EditorCurveBinding[] bindings = AnimationUtility.GetCurveBindings(originalClip);


            //Check if any of our mapped parents are animated in THIS specific clip
            Dictionary<string, AnimationCurve> parentCurvesInClip = new Dictionary<string, AnimationCurve>();
            foreach (var binding in bindings)
            {
                if (binding.type == typeof(GameObject) && binding.propertyName == "m_IsActive")
                {
                    if (targetToClosestParentMap.ContainsValue(binding.path))
                    {
                        parentCurvesInClip[binding.path] = AnimationUtility.GetEditorCurve(originalClip, binding);
                    }
                }
            }

            //If none of our globally-mapped parents are in this clip, do nothing
            if (parentCurvesInClip.Count == 0) return null;


            AnimationClip newClip = new AnimationClip();
            EditorUtility.CopySerialized(originalClip, newClip);
            newClip.name = originalClip.name + "_AndOpsBaseToggle";

            //Assign the parent curves to the child components
            foreach (var kvp in targetToClosestParentMap)
            {
                string targetPath = kvp.Key;
                string parentPath = kvp.Value;

                if (parentCurvesInClip.TryGetValue(parentPath, out AnimationCurve parentCurve))
                {
                    // Only apply if it's not already an exact match to avoid doubling up
                    if (targetPath != parentPath)
                    {
                        EditorCurveBinding compBinding = EditorCurveBinding.FloatCurve(targetPath, typeof(GameObject), "m_IsActive");
                        AnimationUtility.SetEditorCurve(newClip, compBinding, parentCurve);
                    }
                }
            }

            //disabling shadows for penetrator SMRs
            foreach (var kvp in parentToSmrPaths)
            {
                string parentPath = kvp.Key;
                List<string> smrPaths = kvp.Value;

                if (parentCurvesInClip.TryGetValue(parentPath, out AnimationCurve parentCurve))
                {
                    foreach (string smrPath in smrPaths)
                    {
                        // Cache original SMR shadow states
                        float defaultCast = 1f;    // 1 = On
                        float defaultReceive = 1f; // 1 = True

                        if (avatarRoot != null)
                        {
                            Transform smrTransform = smrPath == "" ? avatarRoot.transform : avatarRoot.transform.Find(smrPath);
                            if (smrTransform != null)
                            {
                                SkinnedMeshRenderer smr = smrTransform.GetComponent<SkinnedMeshRenderer>();
                                if (smr != null)
                                {
                                    defaultCast = (float)smr.shadowCastingMode;
                                    defaultReceive = smr.receiveShadows ? 1f : 0f;
                                }
                            }
                        }

                        AnimationCurve castShadowsCurve = new AnimationCurve();
                        AnimationCurve receiveShadowsCurve = new AnimationCurve();

                        foreach (var key in parentCurve.keys)
                        {
                            bool isActive = key.value > 0.5f;

                            // Turn properties to 0 (off) when deformation is enabled, otherwise revert to default
                            float targetCast = isActive ? 0f : defaultCast;
                            float targetReceive = isActive ? 0f : defaultReceive;

                            Keyframe castKey = new Keyframe(key.time, targetCast);
                            castKey.inTangent = float.PositiveInfinity;
                            castKey.outTangent = float.PositiveInfinity;
                            castShadowsCurve.AddKey(castKey);

                            Keyframe receiveKey = new Keyframe(key.time, targetReceive);
                            receiveKey.inTangent = float.PositiveInfinity;
                            receiveKey.outTangent = float.PositiveInfinity;
                            receiveShadowsCurve.AddKey(receiveKey);
                        }

                        EditorCurveBinding castBinding = EditorCurveBinding.FloatCurve(smrPath, typeof(SkinnedMeshRenderer), "m_CastShadows");
                        EditorCurveBinding receiveBinding = EditorCurveBinding.FloatCurve(smrPath, typeof(SkinnedMeshRenderer), "m_ReceiveShadows");

                        AnimationUtility.SetEditorCurve(newClip, castBinding, castShadowsCurve);
                        AnimationUtility.SetEditorCurve(newClip, receiveBinding, receiveShadowsCurve);
                    }
                }
            }

            //If ANY mapped parent active in this clip evaluates > 0.5, turn on OpsAvatarComponent
            AnimationCurve baseCurve = new AnimationCurve();
            HashSet<float> keyframeTimes = new HashSet<float>();

            foreach (var curve in parentCurvesInClip.Values)
            {
                foreach (var key in curve.keys) keyframeTimes.Add(key.time);
            }

            foreach (float time in keyframeTimes)
            {
                float isActive = 0f;
                foreach (var curve in parentCurvesInClip.Values)
                {
                    if (curve.Evaluate(time) > 0.5f)
                    {
                        isActive = 1f;
                        break;
                    }
                }
                
                Keyframe stepKey = new Keyframe(time, isActive);
                stepKey.inTangent = float.PositiveInfinity;
                stepKey.outTangent = float.PositiveInfinity;
                baseCurve.AddKey(stepKey);
            }


            EditorCurveBinding baseBinding = EditorCurveBinding.FloatCurve(baseObjPath, typeof(GameObject), "m_IsActive");
            AnimationUtility.SetEditorCurve(newClip, baseBinding, baseCurve);

            newClip.name = newClip.name.Replace("/", "_");

            string clipPath = Path.Combine(savePath, newClip.name + "_" + System.DateTime.Now.Ticks.ToString() + ".anim").Replace("\\", "/");
            AssetDatabase.CreateAsset(newClip, clipPath);

            return newClip;
        }

    }
}

//#endif