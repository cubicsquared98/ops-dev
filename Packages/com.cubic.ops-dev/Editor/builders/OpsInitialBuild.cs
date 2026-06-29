//#if UNITY_EDITOR
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using VRC.SDKBase.Editor.BuildPipeline;
using ops_dev.Components;
using UnityEditor;

namespace ops_dev.Editor.Builders {
    public class ops_initial_build : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -105;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {

            string folderPath = "Packages/com.cubic.ops-dev/Runtime/ops_generated";
            if (!AssetDatabase.IsValidFolder(folderPath)) AssetDatabase.CreateFolder("Packages/com.cubic.ops-dev/Runtime", "ops_generated");


            //Makes sure that the ops avatar base component exists / is created.
            //This component contains the materials for clearing the frame buffer, reading the ops grab passes and then clearing the frame buffer again.
            //in vrchat, it is essentially hidden unless the world has no backdrop / background being rendered over it in the render queue
            //Screen is overwriten as black again after so that ops data does not appear in cutout mirrors

            //Also contains the component that writes the ops avatar ID, and is used as the gameobject that the other ops components use to get the avatar ID.
            //basically holds stuff that is shared between ops components

            OpsPenetrator[] penetrators = avatarGameObject.GetComponentsInChildren<OpsPenetrator>(true);
            OpsOrifice[] orifices = avatarGameObject.GetComponentsInChildren<OpsOrifice>(true);

            //Check if ops is in use at all on this avatar
            if(penetrators.Length == 0 && orifices.Length == 0){
                return true;
            }

            OpsAvatarComponent[] ops_components = avatarGameObject.GetComponentsInChildren<OpsAvatarComponent>(true);
            OpsAvatarComponent ops_component;
            if(ops_components.Length > 1){
                Debug.LogError("[ops_initial_build] Build Failed: Found too many OpsAvatarComponents on the avatar. Must be 1 or none on the avatar. Will auto-build if there is not one");
                return false;
            }
            else if(ops_components.Length > 0){
                Debug.Log("[ops_initial_build] using already found OpsAvatarComponent");
                ops_component = ops_components[0];
            }
            else{
                GameObject component_object = new GameObject("ops_Avatar_Base_Component");
                component_object.transform.SetParent(avatarGameObject.transform, false);
                ops_component = component_object.AddComponent<OpsAvatarComponent>();
                ops_component.clear_screen_1 = AssetDatabase.LoadAssetAtPath<Material>("Packages/com.cubic.ops-dev/Runtime/materials/clear_1.mat");
                ops_component.clear_screen_2 = AssetDatabase.LoadAssetAtPath<Material>("Packages/com.cubic.ops-dev/Runtime/materials/clear_2.mat");
                ops_component.grab_ops_id_mat = AssetDatabase.LoadAssetAtPath<Material>("Packages/com.cubic.ops-dev/Runtime/materials/ops_grab_ID.mat");
                ops_component.grab_ops_data_mat = AssetDatabase.LoadAssetAtPath<Material>("Packages/com.cubic.ops-dev/Runtime/materials/ops_grab_data.mat");
                if (ops_component.clear_screen_1 == null || 
                    ops_component.clear_screen_2 == null || 
                    ops_component.grab_ops_id_mat == null || 
                    ops_component.grab_ops_data_mat == null)
                {
                    Debug.LogError("[ops_initial_build] Failed trying to load asset");
                    return false;
                }
            }


            OpsIDWriter[] writers = avatarGameObject.GetComponentsInChildren<OpsIDWriter>(true);
            OpsIDWriter avatar_ID_Base = null; // Holds transform and hashID to use for avi

            foreach (OpsIDWriter writer in writers)
            {
                if(writer.idSpace == OpsIDWriter.IDSpace.avatar) // Avatar ID space
                {
                    avatar_ID_Base = writer;
                    break;
                }
            }

            //Generate the base ID writer if it wasn't found
            if(avatar_ID_Base == null)
            {
                //Add the OpsIDWriter component to the ops_component's game object
                avatar_ID_Base = ops_component.gameObject.AddComponent<OpsIDWriter>();

                avatar_ID_Base.mesh = AssetDatabase.LoadAssetAtPath<Mesh>("Packages/com.cubic.ops-dev/Runtime/meshes/12Vert_OpsMesh_skinned.asset");
                avatar_ID_Base.material = AssetDatabase.LoadAssetAtPath<Material>("Packages/com.cubic.ops-dev/Runtime/materials/ops_id_writer.mat");

                if (avatar_ID_Base.mesh == null || 
                    avatar_ID_Base.material == null)
                {
                    Debug.LogError("[ops_initial_build] Failed trying to load asset");
                    return false;
                }
                
                //Set it to Avatar ID space
                avatar_ID_Base.idSpace = OpsIDWriter.IDSpace.avatar;
            }
            //Assign a random integer for the AviID hash
            avatar_ID_Base.hashSeed = Random.Range(0, int.MaxValue);

            ops_component.gameObject.SetActive(false);

            // Return true to allow the build process to continue
            return true; 
        }
    }
}
//#endif