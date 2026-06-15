using UnityEngine;
using VRC.SDKBase;

namespace ops_dev.Components {
    // IEditorOnly ensures VRChat strips this component out during build 
    public class OpsIDWriter : MonoBehaviour, IEditorOnly
    {
        public enum IDSpace { orifice = 0, penetrator = 1, avatar = 2, animator = 3 }
        
        [Header("ID Settings")]
        public IDSpace idSpace;
        public int hashSeed;

        [Header("Render Data")]
        public Mesh mesh;
        public Material material;
    }
}