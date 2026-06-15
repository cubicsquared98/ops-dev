#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;
using VRC.SDKBase.Editor.BuildPipeline;
using VRC.SDK3.Avatars.Components;
using ops_dev.Components;

namespace ops_dev.Editor.Builders {
    public class OpsIDWriterBuilder : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -100;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
            OpsIDWriter[] writers = avatarGameObject.GetComponentsInChildren<OpsIDWriter>(true);
            return BuildOpsIDWriters(avatarGameObject, writers);
        }

        public static bool BuildOpsIDWriters(GameObject avatarGameObject, OpsIDWriter[] writers){
            if (writers.Length == 0) return true;

            string folderPath = "Packages/com.cubic.ops-dev/Runtime/ops_generated";
            if (!AssetDatabase.IsValidFolder(folderPath)) AssetDatabase.CreateFolder("Packages/com.cubic.ops-dev/Runtime/ops_generated", "ops_ID");

            string clipName = $"OpsID_MasterAnim_{avatarGameObject.name}";
            AnimationClip masterClip = new AnimationClip { name = clipName };

            foreach (OpsIDWriter writer in writers)
            {
                if (writer.mesh == null || writer.material == null){
                    Debug.LogError("ID writer is missing material or mesh: " + writer.name + "ON avi: " + avatarGameObject.name);
                    continue;
                }
                if(writer.transform == null){
                    Debug.LogError("ID writer transform is nul");
                    continue;
                }

                GameObject child = new GameObject("OpsID_Render");
                child.transform.SetParent(writer.transform, false);
                child.transform.localPosition = Vector3.zero;
                child.transform.localRotation = Quaternion.identity;

                //Create a dedicated standalone Bone for the SMR
                GameObject boneObj = new GameObject("OpsID_Bone");
                boneObj.transform.SetParent(writer.transform, false);
                boneObj.transform.localPosition = Vector3.zero;
                boneObj.transform.localRotation = Quaternion.identity;

                SkinnedMeshRenderer idSmr = child.AddComponent<SkinnedMeshRenderer>();
                idSmr.sharedMesh = writer.mesh;
                idSmr.sharedMaterial = writer.material;
                
                idSmr.lightProbeUsage = UnityEngine.Rendering.LightProbeUsage.Off;
                idSmr.reflectionProbeUsage = UnityEngine.Rendering.ReflectionProbeUsage.Off;
                idSmr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                idSmr.receiveShadows = false;

                // Bind the SMR specifically to our newly generated bone
                idSmr.rootBone = boneObj.transform;
                idSmr.bones = new Transform[] { boneObj.transform };

                string path = AnimationUtility.CalculateTransformPath(child.transform, avatarGameObject.transform);
                AnimationUtility.SetEditorCurve(masterClip, EditorCurveBinding.FloatCurve(path, typeof(SkinnedMeshRenderer), "material._ID_SPACE"), AnimationCurve.Constant(0f, 1f/60f, (float)writer.idSpace));
                AnimationUtility.SetEditorCurve(masterClip, EditorCurveBinding.FloatCurve(path, typeof(SkinnedMeshRenderer), "material._HASH_SEED"), AnimationCurve.Constant(0f, 1f/60f, writer.hashSeed));

            // Object.DestroyImmediate(writer);
            }

            AssetDatabase.CreateAsset(masterClip, $"{folderPath}/{clipName}.anim");

            VRCAvatarDescriptor descriptor = avatarGameObject.GetComponent<VRCAvatarDescriptor>();
            if (descriptor == null) return true;

            AnimatorController fxController = null;
            int fxLayerIndex = -1;

            for (int i = 0; i < descriptor.baseAnimationLayers.Length; i++)
            {
                if (descriptor.baseAnimationLayers[i].type == VRCAvatarDescriptor.AnimLayerType.FX)
                {
                    fxLayerIndex = i;
                    fxController = descriptor.baseAnimationLayers[i].animatorController as AnimatorController;
                    break;
                }
            }

            string clonedFxPath = $"{folderPath}/OpsID_FX_Clone_{avatarGameObject.name}.controller";

            if (fxController != null)
            {
                string originalPath = AssetDatabase.GetAssetPath(fxController);
                if (AssetDatabase.LoadAssetAtPath<AnimatorController>(clonedFxPath) != null) AssetDatabase.DeleteAsset(clonedFxPath);
                AssetDatabase.CopyAsset(originalPath, clonedFxPath);
                fxController = AssetDatabase.LoadAssetAtPath<AnimatorController>(clonedFxPath);
            }
            else
            {
                fxController = AnimatorController.CreateAnimatorControllerAtPath(clonedFxPath);
            }

            fxController.AddLayer("OpsID_Material_Writer");
            AnimatorControllerLayer[] layers = fxController.layers;
            int newLayerIdx = layers.Length - 1;
            layers[newLayerIdx].defaultWeight = 1.0f;
            fxController.layers = layers;

            AnimatorStateMachine sm = layers[newLayerIdx].stateMachine;
            AnimatorState state = sm.AddState("Apply_All_IDs");
            state.motion = masterClip;

            if (fxLayerIndex != -1)
            {
                descriptor.baseAnimationLayers[fxLayerIndex].animatorController = fxController;
                descriptor.baseAnimationLayers[fxLayerIndex].isDefault = false;
            }

            AssetDatabase.SaveAssets();
            return true;
        }
    }
}
#endif