using UnityEngine;
using UnityEditor;

namespace ops_dev.Editor.Tools {
    [CustomEditor(typeof(SkinnedMeshBoneEditor))]
    public class SkinnedMeshBoneEditorInspector : UnityEditor.Editor
    {
        public override void OnInspectorGUI()
        {
            //Draw the default targetRenderer and bonesList fields
            DrawDefaultInspector();

            SkinnedMeshBoneEditor myScript = (SkinnedMeshBoneEditor)target;

            EditorGUILayout.Space(10);
            
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Fetch Bones From SMR", GUILayout.Height(30)))
                {
                    Undo.RecordObject(myScript, "Fetch Bones");
                    myScript.FetchCurrentBones();
                }

                if (GUILayout.Button("Apply Changes To SMR", GUILayout.Height(30)))
                {
                    Undo.RecordObject(myScript.targetRenderer, "Apply Bone Changes");
                    myScript.ApplyChangesToRenderer();
                    EditorUtility.SetDirty(myScript.targetRenderer);
                }
            }
        }
    }
}