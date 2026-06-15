#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;
using System.Collections;
using System.Collections.Generic;
using VRC.SDKBase.Editor.BuildPipeline;
using VRC.SDK3.Avatars.Components;
using ops_dev.Components;

namespace ops_dev.Editor.Builders {
    public class ops_final_builder : IVRCSDKPreprocessAvatarCallback
    {
        public int callbackOrder => -99;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
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
                Debug.LogError("[ops_final_builder] Build Failed: no avatar ID base component found");
                return false;
            }

            OpsAvatarComponent[] ops_components = avatarGameObject.GetComponentsInChildren<OpsAvatarComponent>(true);
            if(ops_components.Length < 1){
                Debug.LogError("[ops_final_builder] Build Failed: no avatar ID base component found");
                return false;
            }
            OpsAvatarComponent ops_component = ops_components[0];
            if(ops_component == null){
                Debug.LogError("[ops_final_builder] Build Failed: avatar ID base component is null");
                return false;
            }

            //Find the SMR that belongs to this 

            SkinnedMeshRenderer avatar_id_writer = avatar_ID_Base.GetComponentInChildren<SkinnedMeshRenderer>(true);
            if(avatar_id_writer == null){
                Debug.LogError("[ops_final_builder] Build Failed: failed to find SMR on avi base component");
                return false;
            }

            List<Material> currentMaterials = new List<Material>();
            avatar_id_writer.GetSharedMaterials(currentMaterials);

            currentMaterials.Add(ops_component.clear_screen_1);
            currentMaterials.Add(ops_component.clear_screen_2);
            currentMaterials.Add(ops_component.grab_ops_id_mat);
            currentMaterials.Add(ops_component.grab_ops_data_mat);

            avatar_id_writer.SetSharedMaterials(currentMaterials);

            //Need to make animations so that grab_ops_id_mat and grab_ops_data_mat are toggled individually, instead of at the same time
            return true;
        }
    }
}

#endif