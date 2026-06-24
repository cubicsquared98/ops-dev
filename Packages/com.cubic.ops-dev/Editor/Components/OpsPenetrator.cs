using System.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using UnityEngine;
using VRC.SDKBase;

namespace ops_dev.Components {
    public class OpsPenetrator : MonoBehaviour, IEditorOnly
    {
        [Header("Penetrator mesh target")]
        [Tooltip("Set this to the penetrator mesh (smr), will setup the root component correctly")]
        public Transform penetratorMeshObject;

        [Header("Sps component target")]
        [Tooltip("This is the initial bending point / starting point of deformation. Set to the sps component")]
        public Transform sps_component_parent;
        [Tooltip("Only mess with this if you know what you are doing. Can be used if setting up sps to work with z-axis-transforms on the penetrator")]
        public Transform ops_advanced_reparent_penetrator_data_mesh;
        //public Transform avi_base_bone_target; Is found and set on build

        [Header("Penetrator properties")]
        public float length = 0;
        public float radius = 0;

        [Tooltip("Frot mode - currently not finished")]
        public bool frot_mode = false;


        [Header("Advanced Penetrator Properties")]
        [Tooltip("Auto disable shadows when deformation is enabled")]
        public bool AutoDisableMeshShadowsOnDeformation = false;
        public Color penetratorGlowColor = Color.black;
        [Range(0f, 1f)]
        public float emissionStrength = 0f;
        [Tooltip("-1 to disable, 0 or higher to use a channel. Penetrators and orifices sharing the same avoid channel on the same avi will avoid each other")]
        public int avoidOnSelfChannel = -1;
        [Tooltip("Will only deform with other ops components sharing the same channel ID (-1 means ignore)")]
        public int SelectedChannel = -1;

        [Header("Advanced Penetrator bone data (to allow bone scaling in the x/y axis(not length) within penetrator)")]
        [Header("This will be automated in the future")]
        [Tooltip("This is the index of the first bone in the Smr Bones list.")]
        public int starting_index = 0;
        [Tooltip("These bones should corrospond directly to the bones in the SMR containing the penetrator, starting with the bone at the starting index")]
        public List<Transform> smr_bones = new List<Transform>();


        [Header("Penetrator shader setup (Do not alter)")]
        public Shader opsPenetratorWriter;

        [Header("Ops ID Writer setup (do not alter)")]
        public Mesh idWriterMesh;
        public Material idWriterMaterial;
    }
}