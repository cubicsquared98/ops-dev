#if UNITY_EDITOR
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using VRC.SDKBase.Editor.BuildPipeline;
using ops_dev.Components;

namespace ops_dev.Editor.Builders {
    public class ops_initial_build : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -105;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
            OpsPenetrator[] penetrators = avatarGameObject.GetComponentsInChildren<OpsPenetrator>(true);
            OpsOrifice[] orifices = avatarGameObject.GetComponentsInChildren<OpsOrifice>(true);

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
                GameObject component_object = new GameObject("ops_Avatar_Base");
                component_object.transform.SetParent(avatarGameObject.transform, false);
                ops_component = component_object.AddComponent<OpsAvatarComponent>();
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

            //Generate the base if it wasn't found
            if(avatar_ID_Base == null)
            {
                //Add the OpsIDWriter component to the ops_component's game object
                avatar_ID_Base = ops_component.gameObject.AddComponent<OpsIDWriter>();
                
                //Set it to Avatar ID space
                avatar_ID_Base.idSpace = OpsIDWriter.IDSpace.avatar; 
            }
            //Assign a random integer for the AviID hash
            avatar_ID_Base.hashSeed = Random.Range(0, int.MaxValue);

            // Return true to allow the build process to continue
            return true; 
        }
    }
}
#endif