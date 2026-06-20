using System.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using UnityEngine;
using VRC.SDKBase;

namespace ops_dev.Components {
    public class OpsOrifice : MonoBehaviour, IEditorOnly
    {
        //Types
        public enum HoleTypeEnum { Hole = 1, Ring = 2}
        public enum HoleEntryDirectionEnum { One_Way = 1, Two_Way = 2 }
        public enum HoleCenterEnum { Center_Aligned = 1, Radius_Aligned = 2 }

        //Orifice setup
        [Header("Orifice target")]
        [Tooltip("If not set, presume this object is the target")]
        public Transform? OraficeTarget;

        public Transform ActiveTarget => OraficeTarget != null ? OraficeTarget : transform;

        [Header("Orifice Properties")]

        //Allow animating these values

        public HoleTypeEnum holeType = HoleTypeEnum.Hole;
        public HoleEntryDirectionEnum holeEntryDirection = HoleEntryDirectionEnum.One_Way;
        public HoleCenterEnum holeCenter = HoleCenterEnum.Center_Aligned;
        public bool disableHoleRecursion = false;
        public bool opsAvoidOnSelf = false;
        public int opsAvoidSelfChannel = -1;
        public bool opsShrinkPathSegments = false;
        public int ops_channel = -1;
        [Tooltip("This must be enabled if you are using an sps socket with deformation enabled. opsAvoidSelfChannel may not work properly if using backup light sources, as the ops orifice will be ignored, but the light source wont")]
        public bool ops_sps_dps_lightsource_backup = false;

        [Header("USING lightsource backup means the avoid on self channels will not work as intended")]

        [Header("Orifice path")]
        [Tooltip("Orifice will follow this path")]
        public List<Transform> pathPoints = new List<Transform>();

        [Header("Orifice Shader setup (do not alter)")]
        public Shader opsOraficeWriter;

        [Header("Ops ID Writer setup (do not alter)")]
        public Mesh idWriterMesh;
        public Material idWriterMaterial;

        [Header("Others")]
        public bool AlwaysDrawGizmo = false;
        
        #if UNITY_EDITOR
        //other functions
        private void OnDrawGizmosSelected(){
            if(!AlwaysDrawGizmo){
                InternalDrawGizmos();
            }
        }

        private void OnDrawGizmos()
        {
            if(AlwaysDrawGizmo){
                InternalDrawGizmos();
            }
        }

        private void InternalDrawGizmos()
        {
            // 1. Draw Target Visualizer
            if (ActiveTarget != null)
            {
                Gizmos.color = Color.magenta;
                Gizmos.DrawWireSphere(ActiveTarget.position, 0.04f);
                
                UnityEditor.Handles.Label(ActiveTarget.position + Vector3.up * 0.1f, "Orifice Target: " + ActiveTarget.name);
                // Optional: Draw an arrow for the target's orientation too
                UnityEditor.Handles.color = Color.magenta;

                Quaternion backwardRotation = Quaternion.LookRotation(-ActiveTarget.forward, ActiveTarget.up);

                UnityEditor.Handles.ArrowHandleCap(
                    0, 
                    ActiveTarget.position + ActiveTarget.forward*0.0912f, 
                    backwardRotation,
                    0.08f, 
                    EventType.Repaint
                );

            }

            // if (avatarBaseTarget != null)
            // {
            //     Gizmos.color = Color.yellow;
            //     Gizmos.DrawWireSphere(avatarBaseTarget.position, 0.3f);
            // }

            if(pathPoints == null || pathPoints.Count == 0){

                UnityEditor.Handles.color = new Color(1f, 0.6470588f, 0f);

                if(holeEntryDirection == HoleEntryDirectionEnum.Two_Way && holeType == HoleTypeEnum.Ring){
                    UnityEditor.Handles.ArrowHandleCap(
                        0, 
                        ActiveTarget.position - ActiveTarget.forward*0.0912f/2, 
                        ActiveTarget.rotation,
                        0.04f, 
                        EventType.Repaint
                    );
                }
                else if(holeEntryDirection == HoleEntryDirectionEnum.One_Way && holeType == HoleTypeEnum.Ring){
                    Quaternion backwardRotation = Quaternion.LookRotation(-ActiveTarget.forward, ActiveTarget.up);
                    UnityEditor.Handles.ArrowHandleCap(
                        0,
                        ActiveTarget.position,// + ActiveTarget.forward*0.0912f/2,
                        backwardRotation,
                        0.04f,
                        EventType.Repaint
                    );
                }
            }

            // 2. Draw Connected Path Points Line
            if (pathPoints != null && pathPoints.Count > 0)
            {
                Vector3[] points = new Vector3[pathPoints.Count];
                int validPointCount = 0;

                for (int i = 0; i < pathPoints.Count; i++)
                {
                    if (pathPoints[i] != null)
                    {
                        points[validPointCount] = pathPoints[i].position;
                        
                        Gizmos.color = Color.cyan;
                        Gizmos.DrawWireCube(points[validPointCount], new Vector3(0.01f, 0.01f, 0.01f));
                        
                        UnityEditor.Handles.Label(points[validPointCount] + Vector3.up * 0.05f, $"P{i}");

                        UnityEditor.Handles.color = (i != pathPoints.Count - 1) ? Color.cyan : new Color(1f, 0.6470588f, 0f);

                        if(holeEntryDirection == HoleEntryDirectionEnum.Two_Way && i == pathPoints.Count - 1){ //two way ring
                            Quaternion backwardRotation = Quaternion.LookRotation(-pathPoints[i].forward, pathPoints[i].up);
                            UnityEditor.Handles.ArrowHandleCap(
                                0,
                                pathPoints[i].position + pathPoints[i].forward*0.0912f/2,
                                backwardRotation,
                                0.04f,
                                EventType.Repaint
                            );
                        }
                        else if(holeEntryDirection == HoleEntryDirectionEnum.One_Way && holeType == HoleTypeEnum.Hole && i == pathPoints.Count - 1){ //One way and ring
                            UnityEditor.Handles.ArrowHandleCap(
                                0,
                                pathPoints[i].position - pathPoints[i].forward*0.0912f/2,
                                pathPoints[i].rotation,
                                0.04f,
                                EventType.Repaint
                            );
                        }
                        else{ //One way ring
                            UnityEditor.Handles.ArrowHandleCap(
                                0,
                                pathPoints[i].position,
                                pathPoints[i].rotation,
                                0.04f,
                                EventType.Repaint
                            );
                        }


                        validPointCount++;
                    }
                }

                // Draw lines connecting the sequential paths
                if (validPointCount > 0)
                {
                    Gizmos.color = Color.cyan;
                    UnityEditor.Handles.color = Color.cyan;
                    UnityEditor.Handles.DrawDottedLine(ActiveTarget.position, points[0], 4f);

                    for (int i = 0; i < validPointCount - 1; i++)
                    {
                        UnityEditor.Handles.color = Color.cyan;
                        UnityEditor.Handles.DrawDottedLine(points[i], points[i + 1], 4f);

                    }
                }
            }
        }

        #endif

    }

}