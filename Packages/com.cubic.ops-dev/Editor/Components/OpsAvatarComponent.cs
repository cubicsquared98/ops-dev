using System.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using UnityEngine;
using VRC.SDKBase;

namespace ops_dev.Components {
    public class OpsAvatarComponent : MonoBehaviour, IEditorOnly
    {
        [Header("place this somewhere high up in the avi hierarchy (or will auto-build)")]

        [Header("ops material values (Do not alter)")]
        public Material clear_screen_1;
        public Material clear_screen_2;

        public Material grab_ops_id_mat;
        public Material grab_ops_data_mat;
    }   
}


