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
            foreach (var pen in avatarGameObject.GetComponentsInChildren<OpsPenetrator>(true))
            {
                targetOpsPaths.Add(AnimationUtility.CalculateTransformPath(pen.gameObject.transform, avatarGameObject.transform));
            }
            foreach (var ori in avatarGameObject.GetComponentsInChildren<OpsOrifice>(true))
            {
                targetOpsPaths.Add(AnimationUtility.CalculateTransformPath(ori.gameObject.transform, avatarGameObject.transform));
            }

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
                    RuntimeAnimatorController newController = ProcessController(descriptor.baseAnimationLayers[i].animatorController, baseObjPath, targetOpsPaths, savePath);
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
                    RuntimeAnimatorController newController = ProcessController(descriptor.specialAnimationLayers[i].animatorController, baseObjPath, targetOpsPaths, savePath);
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

        private static RuntimeAnimatorController ProcessController(RuntimeAnimatorController originalController, string baseObjPath, HashSet<string> targetOpsPaths, string savePath)
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

            Dictionary<AnimationClip, AnimationClip> clipReplacements = new Dictionary<AnimationClip, AnimationClip>();

            foreach (AnimationClip clip in duplicatedController.animationClips)
            {
                if (clip == null || clipReplacements.ContainsKey(clip)) continue;

                AnimationClip modifiedClip = ProcessClip(clip, baseObjPath, targetOpsPaths, savePath);
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

        private static AnimationClip ProcessClip(AnimationClip originalClip, string baseObjPath, HashSet<string> targetOpsPaths, string savePath)
        {
            EditorCurveBinding[] bindings = AnimationUtility.GetCurveBindings(originalClip);
            List<AnimationCurve> relevantCurves = new List<AnimationCurve>();

            foreach (var binding in bindings)
            {
                if (binding.type == typeof(GameObject) && binding.propertyName == "m_IsActive")
                {
                    //Contains is running on an array, finding and exact match with the animation binding path
                    if (targetOpsPaths.Contains(binding.path))
                    {
                        relevantCurves.Add(AnimationUtility.GetEditorCurve(originalClip, binding));
                    }
                }
            }

            if (relevantCurves.Count == 0) return null;

            AnimationClip newClip = new AnimationClip();
            EditorUtility.CopySerialized(originalClip, newClip);
            
            newClip.name = originalClip.name + "_AndOpsBaseToggle";

            AnimationCurve baseCurve = new AnimationCurve();
            HashSet<float> keyframeTimes = new HashSet<float>();

            foreach (var curve in relevantCurves)
            {
                foreach (var key in curve.keys)
                {
                    keyframeTimes.Add(key.time);
                }
            }

            foreach (float time in keyframeTimes)
            {
                float isActive = 0f;
                foreach (var curve in relevantCurves)
                {
                    // If ANY ops component is active, activate the base
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

            string clipPath = Path.Combine(savePath, newClip.name + "_" + System.DateTime.Now.Ticks.ToString() + ".anim").Replace("\\", "/");
            AssetDatabase.CreateAsset(newClip, clipPath);

            return newClip;
        }

    }
}

//#endif