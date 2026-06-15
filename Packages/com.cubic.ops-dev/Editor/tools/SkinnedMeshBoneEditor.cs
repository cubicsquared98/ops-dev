using UnityEngine;

namespace ops_dev.Editor.Tools {
    public class SkinnedMeshBoneEditor : MonoBehaviour
    {
        [Tooltip("The Skinned Mesh Renderer you want to view and edit.")]
        public SkinnedMeshRenderer targetRenderer;

        [Header("Exposed Bones")]
        [Tooltip("The actual GameObjects acting as bones. Modify this array, then click 'Apply Changes'.")]
        public Transform[] bonesList;

        //Automatically populate the list if a renderer is assigned or changed in the inspector
        private void OnValidate()
        {
            if (targetRenderer != null && (bonesList == null || bonesList.Length == 0))
            {
                FetchCurrentBones();
            }
        }

        [ContextMenu("Fetch Current Bones")]
        public void FetchCurrentBones()
        {
            if (targetRenderer == null)
            {
                Debug.LogWarning("Cannot fetch bones: No Target Renderer assigned.", this);
                return;
            }

            //Copy references from the SkinnedMeshRenderer to our exposed array
            bonesList = targetRenderer.bones;
            Debug.Log($"Fetched {bonesList.Length} bones from {targetRenderer.name}.", this);
        }

        [ContextMenu("Apply Changes to Renderer")]
        public void ApplyChangesToRenderer()
        {
            if (targetRenderer == null)
            {
                Debug.LogError("Cannot apply changes: No Target Renderer assigned.", this);
                return;
            }

            //Push our modified array back to the SkinnedMeshRenderer
            targetRenderer.bones = bonesList;
            Debug.Log($"Successfully updated bone references on {targetRenderer.name}.", this);
        }
    }
}
