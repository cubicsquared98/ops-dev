using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;
using VRC.SDK3.Avatars.Components;
using ops_dev.Components;

namespace ops_dev.Editor.Builders
{
    public static class OpsAnimationRetargeter
    {
        /// <summary>
        /// Retargets Penetrator animations on the avatar.
        /// </summary>
        public static void RetargetPenetratorAnimations(GameObject avatar, Dictionary<OpsPenetrator, GameObject[]> generatedMeshes, string savePath)
        {
            ProcessAvatarDescriptor(avatar, savePath, clip => ProcessPenetratorClip(clip, avatar, generatedMeshes, savePath));
        }

        /// <summary>
        /// Retargets Orifice animations on the avatar.
        /// </summary>
        public static void RetargetOrificeAnimations(GameObject avatar, Dictionary<OpsOrifice, GameObject> generatedMeshes, string savePath)
        {
            ProcessAvatarDescriptor(avatar, savePath, clip => ProcessOrificeClip(clip, avatar, generatedMeshes, savePath));
        }

        private static void ProcessAvatarDescriptor(GameObject avatar, string savePath, Func<AnimationClip, AnimationClip> clipProcessor)
        {
            VRCAvatarDescriptor descriptor = avatar.GetComponent<VRCAvatarDescriptor>();
            if (descriptor == null) return;

            bool descriptorModified = false;

            if (descriptor.customizeAnimationLayers)
            {
                // Base Animation Layers
                for (int i = 0; i < descriptor.baseAnimationLayers.Length; i++)
                {
                    if (!descriptor.baseAnimationLayers[i].isDefault && descriptor.baseAnimationLayers[i].animatorController != null)
                    {
                        RuntimeAnimatorController newController = ProcessController(descriptor.baseAnimationLayers[i].animatorController, savePath, clipProcessor);
                        if (newController != descriptor.baseAnimationLayers[i].animatorController)
                        {
                            descriptor.baseAnimationLayers[i].animatorController = newController;
                            descriptorModified = true;
                        }
                    }
                }
                
                // Special Animation Layers
                for (int i = 0; i < descriptor.specialAnimationLayers.Length; i++)
                {
                    if (!descriptor.specialAnimationLayers[i].isDefault && descriptor.specialAnimationLayers[i].animatorController != null)
                    {
                        RuntimeAnimatorController newController = ProcessController(descriptor.specialAnimationLayers[i].animatorController, savePath, clipProcessor);
                        if (newController != descriptor.specialAnimationLayers[i].animatorController)
                        {
                            descriptor.specialAnimationLayers[i].animatorController = newController;
                            descriptorModified = true;
                        }
                    }
                }
            }

            if (descriptorModified)
            {
                EditorUtility.SetDirty(descriptor);
            }
        }

        private static RuntimeAnimatorController ProcessController(RuntimeAnimatorController originalController, string savePath, Func<AnimationClip, AnimationClip> clipProcessor)
        {
            string oldAssetPath = AssetDatabase.GetAssetPath(originalController);
            if (string.IsNullOrEmpty(oldAssetPath))
            {
                Debug.LogWarning($"[OpsAnimationRetargeter] Cannot duplicate controller {originalController.name} because it is not saved as an asset.");
                return originalController;
            }

            string newControllerPath = Path.Combine(savePath, originalController.name + "_OpsDuplicate_" + System.DateTime.Now.Ticks.ToString() + ".controller").Replace("\\", "/");
            if (!AssetDatabase.CopyAsset(oldAssetPath, newControllerPath))
            {
                Debug.LogError($"[OpsAnimationRetargeter] Failed to copy Animator Controller from {oldAssetPath} to {newControllerPath}");
                return originalController;
            }

            AnimatorController duplicatedController = AssetDatabase.LoadAssetAtPath<AnimatorController>(newControllerPath);
            if (duplicatedController == null)
            {
                Debug.LogWarning("[OpsAnimationRetargeter] Failed to get duplicated controller");
                return originalController;
            }

            Dictionary<AnimationClip, AnimationClip> clipReplacements = new Dictionary<AnimationClip, AnimationClip>();

            foreach (AnimationClip clip in duplicatedController.animationClips)
            {
                if (clip == null || clipReplacements.ContainsKey(clip)) continue;

                AnimationClip modifiedClip = clipProcessor(clip);
                if (modifiedClip != null)
                {
                    clipReplacements.Add(clip, modifiedClip);
                }
            }

            if (clipReplacements.Count == 0) return originalController;

            foreach (AnimatorControllerLayer layer in duplicatedController.layers)
            {
                ReplaceClipsInStateMachine(layer.stateMachine, clipReplacements);
            }

            EditorUtility.SetDirty(duplicatedController);
            AssetDatabase.SaveAssets();

            return duplicatedController;
        }

        private static AnimationClip ProcessPenetratorClip(AnimationClip originalClip, GameObject avatar, Dictionary<OpsPenetrator, GameObject[]> generatedMeshes, string savePath)
        {
            EditorCurveBinding[] bindings = AnimationUtility.GetCurveBindings(originalClip);
            bool clipNeedsModification = false;

            foreach (var binding in bindings)
            {
                if (binding.type == typeof(OpsPenetrator))
                {
                    clipNeedsModification = true;
                    break;
                }
            }

            if (!clipNeedsModification) return null;

            AnimationClip newClip = new AnimationClip();
            EditorUtility.CopySerialized(originalClip, newClip);
            newClip.name = originalClip.name + "_OpsRetargeted";

            bindings = AnimationUtility.GetCurveBindings(newClip);
            foreach (var binding in bindings)
            {
                if (binding.type == typeof(OpsPenetrator))
                {
                    Transform targetTransform = string.IsNullOrEmpty(binding.path) ? avatar.transform : avatar.transform.Find(binding.path);

                    if (targetTransform != null)
                    {
                        OpsPenetrator targetPenetrator = targetTransform.GetComponent<OpsPenetrator>();
                        if (targetPenetrator != null && generatedMeshes.ContainsKey(targetPenetrator))
                        {
                            GameObject[] generatedMeshs = generatedMeshes[targetPenetrator];
                            string newPropName = MapPenetratorPropertyToShader(binding.propertyName);

                            if (!string.IsNullOrEmpty(newPropName))
                            {
                                AnimationCurve curve = AnimationUtility.GetEditorCurve(newClip, binding);
                                AnimationUtility.SetEditorCurve(newClip, binding, null); // Remove old

                                foreach (GameObject generatedMesh in generatedMeshs)
                                {
                                    string targetPath = AnimationUtility.CalculateTransformPath(generatedMesh.transform, avatar.transform);
                                    EditorCurveBinding newBinding = EditorCurveBinding.FloatCurve(targetPath, typeof(SkinnedMeshRenderer), newPropName);
                                    AnimationUtility.SetEditorCurve(newClip, newBinding, curve); // Apply new
                                }
                            }
                        }
                    }
                }
            }

            string clipPath = Path.Combine(savePath, newClip.name + "_" + System.DateTime.Now.Ticks.ToString() + "_" + newClip.GetInstanceID() + ".anim").Replace("\\", "/");
            AssetDatabase.CreateAsset(newClip, clipPath);
            UnityEditor.AssetDatabase.SaveAssets();
            return newClip;
        }

        private static AnimationClip ProcessOrificeClip(AnimationClip originalClip, GameObject avatar, Dictionary<OpsOrifice, GameObject> generatedMeshes, string savePath)
        {
            EditorCurveBinding[] bindings = AnimationUtility.GetCurveBindings(originalClip);
            bool clipNeedsModification = false;

            foreach (var binding in bindings)
            {
                if (binding.type == typeof(OpsOrifice))
                {
                    clipNeedsModification = true;
                    break;
                }
            }

            if (!clipNeedsModification) return null;

            AnimationClip newClip = new AnimationClip();
            EditorUtility.CopySerialized(originalClip, newClip);
            newClip.name = originalClip.name + "_OpsRetargeted";

            bindings = AnimationUtility.GetCurveBindings(newClip);
            foreach (var binding in bindings)
            {
                if (binding.type == typeof(OpsOrifice))
                {
                    Transform targetTransform = string.IsNullOrEmpty(binding.path) ? avatar.transform : avatar.transform.Find(binding.path);

                    if (targetTransform != null)
                    {
                        OpsOrifice targetOrifice = targetTransform.GetComponent<OpsOrifice>();
                        if (targetOrifice != null && generatedMeshes.ContainsKey(targetOrifice))
                        {
                            GameObject generatedMesh = generatedMeshes[targetOrifice];
                            string newPropName = MapOrificePropertyToShader(binding.propertyName);

                            if (!string.IsNullOrEmpty(newPropName))
                            {
                                string targetPath = AnimationUtility.CalculateTransformPath(generatedMesh.transform, avatar.transform);
                                EditorCurveBinding newBinding = EditorCurveBinding.FloatCurve(targetPath, typeof(SkinnedMeshRenderer), newPropName);

                                AnimationCurve curve = AnimationUtility.GetEditorCurve(newClip, binding);
                                AnimationUtility.SetEditorCurve(newClip, binding, null); // Remove old
                                AnimationUtility.SetEditorCurve(newClip, newBinding, curve); // Apply new
                            }
                        }
                    }
                }
            }

            string clipPath = Path.Combine(savePath, newClip.name + "_" + System.DateTime.Now.Ticks.ToString() + "_" + newClip.GetInstanceID() + ".anim").Replace("\\", "/");
            AssetDatabase.CreateAsset(newClip, clipPath);
            return newClip;
        }

        private static string MapPenetratorPropertyToShader(string propertyName)
        {
            if (propertyName.StartsWith("penetratorGlowColor"))
            {
                if (propertyName.Contains("."))
                {
                    string suffix = propertyName.Substring(propertyName.IndexOf('.'));
                    return "material._OPS_PENETRATOR_GLOW_COLOR" + suffix;
                }
                return "material._OPS_PENETRATOR_GLOW_COLOR";
            }

            switch (propertyName)
            {
                case "emissionStrength": return "material._OPS_PENETRATOR_EMISSION_STRENGTH";
                case "avoidOnSelfChannel": return "material._OPS_PENETRATOR_AVOID_ON_SELF_MASK";
                case "SelectedChannel": return "material._OPS_ID_CHANNEL";
                case "frot_mode": return "material._OPS_FROT_MODE";
                default: return null;
            }
        }

        private static string MapOrificePropertyToShader(string propertyName)
        {
            switch (propertyName)
            {
                case "holeType": return "material._HoleType";
                case "holeEntryDirection": return "material._HoleEntryDirection";
                case "holeCenter": return "material._HoleCenterAlignment";
                case "hashSeed": return "material._HASH_SEED";
                case "hashSeedAviId": return "material._HASH_SEED_AVI_ID";
                case "disableHoleRecursion": return "material._DISABLE_HOLE_RECURSION";
                case "opsAvoidOnSelf": return "material._OPS_AVOID_ON_SELF";
                case "opsAvoidSelfMask": return "material._OPS_AVOID_SELF_MASK";
                case "opsShrinkPathSegments": return "material._OPS_PATH_HIDE_SEGMENTS";
                case "ops_channel": return "material._OPS_CHANNEL_ID";
                case "ops_sps_dps_lightsource_backup": return "material._OPS_LIGHTSOURCE_BACKUP_EXISTS";
                default: return null;
            }
        }

        public static void ReplaceClipsInStateMachine(AnimatorStateMachine sm, Dictionary<AnimationClip, AnimationClip> replacements)
        {
            if (sm == null) return;

            foreach (ChildAnimatorState childState in sm.states)
            {
                ReplaceClipInMotion(childState.state, replacements);
            }

            foreach (ChildAnimatorStateMachine childSm in sm.stateMachines)
            {
                ReplaceClipsInStateMachine(childSm.stateMachine, replacements);
            }
        }

        public static void ReplaceClipInMotion(AnimatorState state, Dictionary<AnimationClip, AnimationClip> replacements)
        {
            bool stateModified = false;
            if (state.motion == null) return;

            if (state.motion is AnimationClip clip)
            {
                if (replacements.TryGetValue(clip, out AnimationClip newClip))
                {
                    state.motion = newClip;
                    stateModified = true;
                }
            }
            else if (state.motion is BlendTree tree)
            {
                if (ReplaceClipsInBlendTree(tree, replacements))
                {
                    stateModified = true;
                }
            }

            if (stateModified)
            {
                EditorUtility.SetDirty(state);
            }
        }

        public static bool ReplaceClipsInBlendTree(BlendTree tree, Dictionary<AnimationClip, AnimationClip> replacements)
        {
            if (tree == null) return false;

            ChildMotion[] children = tree.children;
            bool modified = false;

            for (int i = 0; i < children.Length; i++)
            {
                if (children[i].motion is AnimationClip clip)
                {
                    if (replacements.TryGetValue(clip, out AnimationClip newClip))
                    {
                        children[i].motion = newClip;
                        modified = true;
                    }
                }
                else if (children[i].motion is BlendTree childTree)
                {
                    if (ReplaceClipsInBlendTree(childTree, replacements))
                    {
                        modified = true;
                    }
                }
            }

            if (modified)
            {
                tree.children = children;
                EditorUtility.SetDirty(tree);
            }
            return modified;
        }
    }
}