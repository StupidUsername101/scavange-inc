shader_type spatial;
void vertex() {
    VERTEX.x += sin(TIME * 2.0 + VERTEX.y * 3.0) * 0.1;
}
void fragment() {
    vec3 n = NORMAL;

    n.x += sin(UV.y * 20.0 + TIME * 3.0) * 0.2;
    n.z += cos(UV.x * 20.0 + TIME * 3.0) * 0.2;

    NORMAL = normalize(n);
}