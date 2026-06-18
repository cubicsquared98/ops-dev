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
    public class OpsOrificeBuilder : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -101;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
            OpsOrifice[] orifii = avatarGameObject.GetComponentsInChildren<OpsOrifice>(true);
            //Check if any ops orifices exist
            if (orifii.Length == 0) return true;

            string folderPath = "Packages/com.cubic.ops-dev/Runtime/ops_generated";
            if (!AssetDatabase.IsValidFolder(folderPath)) AssetDatabase.CreateFolder("Packages/com.cubic.ops-dev/Runtime/ops_generated", "orifice");

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
                Debug.LogError("[OpsOrificeBuilder] Build Failed: Could not find an OpsIDWriter with Avatar ID space. This component must exist on the avatar to proceed.");
                return false;
            }

            // Dictionary to keep track of which mesh belongs to which orifice for animation retargeting
            Dictionary<OpsOrifice, GameObject> generatedMeshes = new Dictionary<OpsOrifice, GameObject>();

            foreach (OpsOrifice orifice in orifii)
            {
                if (orifice.opsOraficeWriter == null) continue;

                int hashSeed = Random.Range(0, int.MaxValue);
                int hashSeedAvi = avatar_ID_Base.hashSeed;

                //Puts together the gameobject for the ops orifice - also adding an ops ID writer to it
                GameObject generatedMesh = CreateSkinnedTriangle(orifice.ActiveTarget, folderPath, avatar_ID_Base.transform, orifice.opsOraficeWriter, hashSeed, hashSeedAvi, orifice);
                generatedMeshes.Add(orifice, generatedMesh);

                //Should be disabled by default
                orifice.gameObject.SetActive(false);
            }

            AssetDatabase.SaveAssets();

            OpsAnimationRetargeter.RetargetOrificeAnimations(avatarGameObject, generatedMeshes, folderPath);


            return true;
        }


        public static GameObject CreateSkinnedTriangle(Transform parent, string savePath, Transform avatar_base_target, Shader s1, int hash_seed, int hash_seed_avi, OpsOrifice settings)
        {
            string uniqueID = settings.name + "_" + System.DateTime.Now.Ticks.ToString();
            string folderName = "Orafice_" + uniqueID;
            string materialFolder = Path.Combine(savePath, folderName).Replace("\\", "/");

            if (!Directory.Exists(materialFolder))
            {
                Directory.CreateDirectory(materialFolder);
                UnityEditor.AssetDatabase.ImportAsset(materialFolder);
            }

            //Debug.LogError("Building orifice for: " + materialFolder);

            // Determine Mesh Asset Path
            bool hasPathPoints = settings.pathPoints != null && settings.pathPoints.Count > 0;
            string meshAssetPath = savePath;

            //If path points then we make a custom mesh
            if (hasPathPoints)
            {
                meshAssetPath = Path.Combine(materialFolder, "OrificePathMesh_" + uniqueID + ".asset").Replace("\\", "/");
            }
            //If no path points, re-use generic mesh
            else{
                meshAssetPath = Path.Combine(meshAssetPath, "_generic_orifice_mesh" + ".asset").Replace("\\", "/");
            }

            GameObject meshObj = new GameObject("GeoShader_OrificeMesh");
            if (parent != null) meshObj.transform.SetParent(parent, false);

            GameObject rootBone = new GameObject("RootBone");
            rootBone.transform.SetParent(meshObj.transform, false);

            // Load or Generate Mesh
            Mesh mesh = UnityEditor.AssetDatabase.LoadAssetAtPath<Mesh>(meshAssetPath);

            if (mesh == null || hasPathPoints) 
            {
                int pathCount = hasPathPoints ? settings.pathPoints.Count : 0;
                int totalVertices = 6 + (pathCount * 3);
                int totalTriIndices = 6 + (pathCount * 3);
                int totalBones = 2 + pathCount;

                mesh = new Mesh();
                mesh.name = hasPathPoints ? "OrificePathMesh_" + uniqueID : "OrificeMesh_tris";
                
                Vector3[] vertices = new Vector3[totalVertices];
                int[] triangles = new int[totalTriIndices];
                Vector2[] uvs = new Vector2[totalVertices];
                BoneWeight[] weights = new BoneWeight[totalVertices];

                //first triangle goes at avi center
                //second triangle goes at orifice

                //Further triangles are all for orifice path data

                vertices[0] = Vector3.zero; vertices[1] = new Vector3(0, 0, 0.1f); vertices[2] = new Vector3(0, 0.1f, 0);
                vertices[3] = Vector3.zero; vertices[4] = new Vector3(0, 0, 0.01f); vertices[5] = new Vector3(0, 0.01f, 0);
                
                triangles[0] = 0; triangles[1] = 2; triangles[2] = 1;
                triangles[3] = 3; triangles[4] = 5; triangles[5] = 4;

                for (int i = 0; i < 2; i++) {
                    uvs[i * 3] = Vector2.zero; uvs[i * 3 + 1] = Vector2.right; uvs[i * 3 + 2] = Vector2.up;
                }

                //bones go: root, avi

                for (int i = 0; i < 3; i++) { weights[i].boneIndex0 = 1; weights[i].weight0 = 1f; }
                for (int i = 3; i < 6; i++) { weights[i].boneIndex0 = 0; weights[i].weight0 = 1f; }

                for (int i = 0; i < pathCount; i++)
                {
                    int vIdx = 6 + (i * 3);
                    int tIdx = 6 + (i * 3);
                    int boneIdx = 2 + i;

                    vertices[vIdx] = Vector3.zero;
                    vertices[vIdx + 1] = new Vector3(0, 0, 0.1f);
                    vertices[vIdx + 2] = new Vector3(0, 0.1f, 0);

                    triangles[tIdx] = vIdx; triangles[tIdx + 1] = vIdx + 2; triangles[tIdx + 2] = vIdx + 1;

                    uvs[vIdx] = Vector2.zero; uvs[vIdx + 1] = Vector2.right; uvs[vIdx + 2] = Vector2.up;

                    weights[vIdx].boneIndex0 = boneIdx; weights[vIdx].weight0 = 1f;
                    weights[vIdx + 1].boneIndex0 = boneIdx; weights[vIdx + 1].weight0 = 1f;
                    weights[vIdx + 2].boneIndex0 = boneIdx; weights[vIdx + 2].weight0 = 1f;
                }

                mesh.vertices = vertices;
                mesh.triangles = triangles;
                mesh.uv = uvs;
                mesh.boneWeights = weights;
                mesh.RecalculateNormals();

                Vector3[] deltaVertices = new Vector3[totalVertices];
                deltaVertices[0] = new Vector3(2f, 2f, 2f);
                deltaVertices[1] = new Vector3(-2f, -2f, -2f) - vertices[1];
                deltaVertices[2] = new Vector3(2f, -2f, 2f) - vertices[2];
                deltaVertices[3] = new Vector3(-2f, 2f, -2f);
                deltaVertices[4] = new Vector3(2f, 2f, -2f) - vertices[4];
                deltaVertices[5] = new Vector3(-2f, -2f, 2f) - vertices[5];
                mesh.AddBlendShapeFrame("Big", 100f, deltaVertices, null, null);

                Matrix4x4[] bindPoses = new Matrix4x4[totalBones];
                for (int i = 0; i < totalBones; i++) bindPoses[i] = Matrix4x4.identity;
                mesh.bindposes = bindPoses;

                UnityEditor.AssetDatabase.CreateAsset(mesh, meshAssetPath);
            }

            // Material Setup
            Material[] mats = new Material[1];
            mats[0] = new Material(s1 != null ? s1 : Shader.Find("Standard"));
            mats[0].name = "opsOrificeWriter_" + uniqueID;
            mats[0].SetInt("_HoleType", (int)settings.holeType);
            mats[0].SetInt("_HoleEntryDirection", (int)settings.holeEntryDirection);
            mats[0].SetInt("_HoleCenterAlignment", (int)settings.holeCenter);
            mats[0].SetInt("_HASH_SEED", hash_seed);
            mats[0].SetInt("_HASH_SEED_AVI_ID", hash_seed_avi);
            mats[0].SetInt("_DISABLE_HOLE_RECURSION", settings.disableHoleRecursion ? 1 : 0);
            mats[0].SetInt("_OPS_AVOID_ON_SELF", settings.opsAvoidOnSelf ? 1 : 0);
            mats[0].SetInt("_OPS_AVOID_SELF_MASK", settings.opsAvoidSelfChannel);
            mats[0].SetInt("_OPS_PATH_COUNT", hasPathPoints ? settings.pathPoints.Count : 0);
            mats[0].SetInt("_OPS_PATH_HIDE_SEGMENTS", settings.opsShrinkPathSegments ? 1 : 0);

            UnityEditor.AssetDatabase.CreateAsset(mats[0], Path.Combine(materialFolder, mats[0].name + ".mat").Replace("\\", "/"));
            UnityEditor.AssetDatabase.SaveAssets();

            // SkinnedMeshRenderer Setup
            SkinnedMeshRenderer smr = meshObj.AddComponent<SkinnedMeshRenderer>();
            smr.sharedMesh = mesh;

            int pathCountFinal = hasPathPoints ? settings.pathPoints.Count : 0;
            Transform[] allBones = new Transform[2 + pathCountFinal];
            allBones[0] = rootBone.transform;
            allBones[1] = avatar_base_target;
            for (int i = 0; i < pathCountFinal; i++) allBones[2 + i] = settings.pathPoints[i];

            smr.bones = allBones;
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
            idWriterComp.idSpace = OpsIDWriter.IDSpace.orifice; // Setting it specifically for this generator
            idWriterComp.hashSeed = hash_seed;
            idWriterComp.mesh = settings.idWriterMesh;
            idWriterComp.material = settings.idWriterMaterial;

            return meshObj;
        }

    }
}
//#endif