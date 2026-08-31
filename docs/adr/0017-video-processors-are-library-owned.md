# Video processors are library-owned and selectable

Person isolation is part of the package, not a host GPU experiment. The selectable family is none, blur with intensity 0–100, and replace with a still image (bytes or asset). v1 implements only none (pass-through). Blur and replace are a later plan; host UIs will map None/Some/Lots to 0/50/100 when blur exists. The type defines the behavior. Processors run on the Production video path so Camera preview matches the call. Hosts do not inject a processor object.
