//#if UNITY_EDITOR
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine.Rendering;
using VRC.SDKBase.Editor.BuildPipeline;
using VRC.SDK3.Avatars.Components;
using ops_dev.Components;

namespace ops_dev.Editor.Builders {
    public class OpsPenetratorBuilder : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -102;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
            OpsPenetrator[] penetrators = avatarGameObject.GetComponentsInChildren<OpsPenetrator>(true);
            //Check if any ops penetrators exist
            if (penetrators.Length == 0) return true;

            string folderPath = "Packages/com.cubic.ops-dev/Runtime/ops_generated/penetrator";
            if (!AssetDatabase.IsValidFolder(folderPath)) AssetDatabase.CreateFolder("Packages/com.cubic.ops-dev/Runtime/ops_generated", "penetrator");

            List<OpsIDWriter> writers = new List<OpsIDWriter>(avatarGameObject.GetComponentsInChildren<OpsIDWriter>(true));
            OpsIDWriter avatar_ID_Base = null; //Holds transform and hashID to use for avi
            foreach (OpsIDWriter writer in writers)
            {
                if(writer.idSpace == OpsIDWriter.IDSpace.avatar) //Avatar ID space
                {
                    avatar_ID_Base = writer;
                }
            }
            if(avatar_ID_Base == null){
                Debug.LogError("[OpsPenetratorBuilder] Build Failed: Could not find an OpsIDWriter with Avatar ID space. This component must exist on the avatar to proceed.");
                return false;
            }

            // Dictionary to keep track of which mesh belongs to which penetrator for animation retargeting
            Dictionary<OpsPenetrator, GameObject[]> generatedMeshes = new Dictionary<OpsPenetrator, GameObject[]>();

            foreach(OpsPenetrator penetrator in penetrators){
                if (penetrator.opsPenetratorWriter == null) continue;

                int hashSeed = Random.Range(0, int.MaxValue);
                int hashSeedAvi = avatar_ID_Base.hashSeed;

                //Puts together the gameobject for the ops penetrator - also adding an ops ID writer to it
                GameObject generatedMesh = CreateSkinnedTriangle(folderPath, avatar_ID_Base.transform, hashSeed, hashSeedAvi, penetrator);
                generatedMeshes.Add(penetrator, new GameObject[] {generatedMesh, penetrator.penetratorMeshObject.gameObject});

                //Should be disabled by default
                penetrator.gameObject.SetActive(false);

            }

            AssetDatabase.SaveAssets();

            OpsAnimationRetargeter.RetargetPenetratorAnimations(avatarGameObject, generatedMeshes, folderPath);

            return true;
        }

        public static GameObject CreateSkinnedTriangle(string savePath, Transform avatar_base_target, int hash_seed, int hash_seed_avi, OpsPenetrator settings)
        {
            Transform parent = settings.gameObject.transform;
            float length = settings.length;
            float radius = settings.radius;
            // Bounds bounds = settings.customBounds;
            // string savePath = settings.baseSavePath;
            Transform sps_Plug_Component_Transform = settings.sps_component_parent;
            Shader s1 = settings.opsPenetratorWriter;
            // Shader s2 = settings.opsIdWriter;

            // Setup Unique Folder
            string uniqueID = settings.name + "_" + System.DateTime.Now.Ticks.ToString();
            string rootDir = Path.GetDirectoryName(savePath);
            string folderName = "Penetrator_" + uniqueID;
            string finalFolderPath = Path.Combine(rootDir, folderName).Replace("\\", "/");

            if (!Directory.Exists(finalFolderPath))
            {
                Directory.CreateDirectory(finalFolderPath);
                UnityEditor.AssetDatabase.ImportAsset(finalFolderPath);
            }

            // Create the base GameObject
            GameObject meshObj = new GameObject("OpsPenetratorMesh");
            if (parent != null) meshObj.transform.SetParent(parent, false);

            // Inverse Scaling Logic - using mesh object as scale reference
            float scaledLength = length;
            float scaledRadius = radius;
            if (settings.penetratorMeshObject != null)
            {
                Vector3 worldScale = settings.penetratorMeshObject.lossyScale;
                if (Mathf.Abs(worldScale.z) > 0.0001f) scaledLength /= worldScale.z;
                if (Mathf.Abs(worldScale.y) > 0.0001f) scaledRadius /= worldScale.y;
            }

            // Create the Bone Hierarchy
            SkinnedMeshRenderer sps_plug_smrenderer = settings.penetratorMeshObject.GetComponent<SkinnedMeshRenderer>();
            Material[] sps_mats = sps_plug_smrenderer.sharedMaterials;

            //Apply the new HashID to the penetrator sps material
            foreach(Material sps_mat in sps_mats){
                sps_mat.SetInt("_OPS_HASH_SEED", hash_seed);
                sps_mat.SetInt("_OPS_SKINNED_BONES_OFFSET", settings.starting_index);
                sps_mat.SetInt("_OPS_SKINNED_BONES_ENABLED", settings.smr_bones.Count > 0 ? 1 : 0);
                sps_mat.SetInt("_OPS_PENETRATOR_AVOID_ON_SELF_MASK", settings.avoidOnSelfChannel);
                sps_mat.SetInt("_OPS_ID_CHANNEL", settings.SelectedChannel);
                sps_mat.SetInt("_OPS_FROT_MODE", settings.frot_mode ? 1 : 0);
            }

            GameObject rootBone = sps_plug_smrenderer.rootBone.gameObject;
            // GameObject rootBone = new GameObject("RootBone");
            // rootBone.transform.SetParent(meshObj.transform, false);

            //This places the data sending mesh into the correct position, it should be lined up from the plug to the penetrator tip
            GameObject penetrator_base_bone = new GameObject("OpsPenetrator_base");
            
            if (settings.ops_advanced_reparent_penetrator_data_mesh != null) penetrator_base_bone.transform.SetParent(settings.ops_advanced_reparent_penetrator_data_mesh, false);
            else if (sps_Plug_Component_Transform != null) penetrator_base_bone.transform.SetParent(sps_Plug_Component_Transform, false);


            List<Transform> allBones = new List<Transform> { rootBone.transform, penetrator_base_bone.transform, avatar_base_target };
            int smrBoneStartIndex = allBones.Count; //Starting point for x/y data triangles
            allBones.AddRange(settings.smr_bones); //Adds in the remaining bones

            int boneCount = allBones.Count - 1; //Triangle is made for every bone but the root bone
            int vertCount = boneCount * 3;      //vertex count from bone count

            Vector3[] vertices = new Vector3[vertCount];
            int[] triangles = new int[vertCount];
            Vector2[] uvs = new Vector2[vertCount];
            BoneWeight[] weights = new BoneWeight[vertCount];
            Vector3[] deltaVertices = new Vector3[vertCount];

            //first triangle shares penetrator data
            //second triangle shares avi center point

            //Further triangles represent penetrator bones for x/y scaling

            //Length and radius of penetrator
            vertices[0] = Vector3.zero;
            vertices[1] = new Vector3(0, 0, scaledLength);
            vertices[2] = new Vector3(0, scaledRadius, 0);

            //Triangle placed at avatar base (for same-avi-stuff)
            vertices[3] = Vector3.zero;
            vertices[4] = new Vector3(0, 0, 0.1f);
            vertices[5] = new Vector3(0, 0.1f, 0);

            triangles[0] = 0; triangles[1] = 2; triangles[2] = 1;
            triangles[3] = 3; triangles[4] = 5; triangles[5] = 4;

            for (int i = 0; i < 2; i++) {
                uvs[i * 3] = Vector2.zero; uvs[i * 3 + 1] = Vector2.right; uvs[i * 3 + 2] = Vector2.up;
            }

            //bones go: root, penetrator, avi
            //          0   , 1         , 2
            //
            //We do not want to weight any bones to the root bone
            for (int i = 0; i < 3; i++) { weights[i].boneIndex0 = 1; weights[i].weight0 = 1f; }
            for (int i = 3; i < 6; i++) { weights[i].boneIndex0 = 2; weights[i].weight0 = 1f; }

            //This is just kind work-aroundy --Can instead just animate the smr to disable runtime bounding box re-calcuation, and use the set bounding box in the smr.
            //Biig triangle to enlarge bounding box and ensure that vrchat does not break the bounding box at runtime.
            deltaVertices[0] = new Vector3(2f, 2f, 2f);
            deltaVertices[1] = new Vector3(-2f, -2f, -2f) - vertices[1];
            deltaVertices[2] = new Vector3(2f, -2f, 2f) - vertices[2];

            // Push Root Triangle vertices to define other extremes
            deltaVertices[3] = new Vector3(-2f, 2f, -2f);
            deltaVertices[4] = new Vector3(2f, 2f, -2f) - vertices[4];
            deltaVertices[5] = new Vector3(-2f, -2f, 2f) - vertices[5];


            //TODO: need to add a check to see if Y is forward or if Z is forward on the penetrator
            //Now add in all the stuff for the extra bones
            for(int i = smrBoneStartIndex - 1; i < boneCount; i++){
                int targetBoneIndex = i + 1; //Actual bone is bones + 1 cos of root bone
                //Transform currentBone = allBones[targetBoneIndex]; 
                int vIndex = i * 3;

                //Triangle shape depends on which axis is in the forward direction. Currently set up for the Y direction
                vertices[vIndex + 0] = Vector3.zero;
                vertices[vIndex + 1] = new Vector3(scaledRadius, 0, 0);
                vertices[vIndex + 2] = new Vector3(0, 0, scaledRadius);

                uvs[vIndex] = Vector2.zero;
                uvs[vIndex + 1] = Vector2.right;
                uvs[vIndex + 2] = Vector2.up;

                triangles[vIndex] = vIndex;
                triangles[vIndex + 1] = vIndex + 2;
                triangles[vIndex + 2] = vIndex + 1;

                weights[vIndex] = new BoneWeight { boneIndex0 = targetBoneIndex, weight0 = 1f };
                weights[vIndex + 1] = new BoneWeight { boneIndex0 = targetBoneIndex, weight0 = 1f };
                weights[vIndex + 2] = new BoneWeight { boneIndex0 = targetBoneIndex, weight0 = 1f };

                //doesnt need to do anything for blendshape
                deltaVertices[vIndex] = new Vector3(0, 0, 0);
                deltaVertices[vIndex + 1] = new Vector3(0, 0, 0);
                deltaVertices[vIndex + 2] = new Vector3(0, 0, 0);

            }


            Mesh mesh = new Mesh();
            mesh.name = "PenetratorMesh_" + uniqueID;
            mesh.vertices = vertices;
            mesh.triangles = triangles;
            mesh.uv = uvs;
            mesh.boneWeights = weights;
            mesh.RecalculateNormals();

            mesh.AddBlendShapeFrame("Big", 100f, deltaVertices, null, null);

            // Bind Poses
            Matrix4x4[] bindPoses = new Matrix4x4[allBones.Count];
            for (int i = 0; i < allBones.Count; i++)
            {
                bindPoses[i] = Matrix4x4.identity;
                // if (allBones[i] != null)
                //     bindPoses[i] = allBones[i].worldToLocalMatrix * meshObj.transform.localToWorldMatrix;
                // else
                //     bindPoses[i] = Matrix4x4.identity;
            }
            mesh.bindposes = bindPoses;
            
            // Save Mesh and Materials
            string meshPath = Path.Combine(finalFolderPath, mesh.name + ".asset").Replace("\\", "/");
            UnityEditor.AssetDatabase.CreateAsset(mesh, meshPath);

            Material[] mats = new Material[1];
            
            // Material 1: Penetrator Writer
            mats[0] = new Material(s1 != null ? s1 : Shader.Find("Standard"));
            mats[0].name = "Penetrator_Mat1_" + uniqueID;
            mats[0].SetInt("_HASH_SEED", hash_seed);
            mats[0].SetInt("_HASH_SEED_AVI_ID", hash_seed_avi);
            mats[0].SetInt("_ID", 0);
            mats[0].SetInt("_OVERRIDE_USE_ID", 0);
            mats[0].SetColor("_OPS_PENETRATOR_GLOW_COLOR", settings.penetratorGlowColor);
            mats[0].SetFloat("_OPS_PENETRATOR_EMISSION_STRENGTH", settings.emissionStrength);
            mats[0].SetInt("_OPS_PENETRATOR_AVOID_ON_SELF_MASK", settings.avoidOnSelfChannel);
            mats[0].SetInt("_OPS_ID_CHANNEL", settings.avoidOnSelfChannel);
            mats[0].SetInt("_OPS_SKINNED_BONES_OFFSET", settings.SelectedChannel);
            mats[0].SetInt("_OPS_SKINNED_BONES_ENABLED", settings.smr_bones.Count > 0 ? 1 : 0);
            mats[0].SetInt("_OPS_FROT_MODE", settings.frot_mode ? 1 : 0);
            
            UnityEditor.AssetDatabase.CreateAsset(mats[0], Path.Combine(finalFolderPath, mats[0].name + ".mat").Replace("\\", "/"));
            UnityEditor.AssetDatabase.SaveAssets();


            // Configure Renderer
            SkinnedMeshRenderer smr = meshObj.AddComponent<SkinnedMeshRenderer>();
            smr.sharedMesh = mesh;
            smr.bones = allBones.ToArray();
            smr.rootBone = rootBone.transform;
            smr.updateWhenOffscreen = true;
            smr.materials = mats;
            

            smr.shadowCastingMode = ShadowCastingMode.Off;
            smr.receiveShadows = false;
            smr.lightProbeUsage = LightProbeUsage.Off;
            smr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            smr.skinnedMotionVectors = false;
            smr.allowOcclusionWhenDynamic = false;

            //Attach ID writer to root bone
            OpsIDWriter idWriterComp = rootBone.AddComponent<OpsIDWriter>();
            idWriterComp.idSpace = OpsIDWriter.IDSpace.penetrator; // Setting it specifically for this generator
            idWriterComp.hashSeed = hash_seed;
            idWriterComp.mesh = settings.idWriterMesh;
            idWriterComp.material = settings.idWriterMaterial;

            return meshObj;
        }
    }
}

//#endif