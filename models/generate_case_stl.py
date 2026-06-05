import math
import os
import struct


HARDWARE = {
    "esp32_board": (18.0, 22.52),
    "rgb_module": (26.0, 34.0),
    "rgb_led_diameter": 10.0,
    "rgb_led_visible_height": 15.0,
    "type_c_opening": (12.5, 6.5),
}


CASE = {
    "outer_width": 38.0,
    "outer_length": 84.0,
    "bottom_height": 12.0,
    "lid_thickness": 1.8,
    "lid_lip_height": 2.2,
    "wall": 2.0,
    "floor": 1.8,
    "inner_width": 34.0,
    "inner_length": 80.0,
    "lid_offset_x": 50.0,
    "esp32_origin_x": 10.0,
    "esp32_origin_y": 5.0,
    "rgb_origin_x": 6.0,
    "rgb_origin_y": 39.0,
    "type_c_center_x": 19.0,
    "type_c_center_y": 0.4,
    "type_c_center_z": 5.6,
    "button_center_y": 17.0,
    "boot_button_center_x": 15.4,
    "reset_button_center_x": 22.6,
    "led_center_x": 19.0,
    "led_center_y": 57.0,
    "led_hole_radius": 6.2,
    "button_hole_radius": 3.0,
    "wire_channel_width": 10.0,
    "side_wall_vents": (),
    "lid_grid_step": 0.35,
    "circular_hole_segments": 128,
}


def circle_intersects_rect(cx, cy, radius, x0, y0, x1, y1):
    closest_x = min(max(cx, x0), x1)
    closest_y = min(max(cy, y0), y1)
    return (closest_x - cx) ** 2 + (closest_y - cy) ** 2 <= radius**2


def rects_intersect(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    return ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0


def normal_for(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length == 0:
        return (0.0, 0.0, 0.0)
    return (nx / length, ny / length, nz / length)


def add_triangle(triangles, a, b, c):
    triangles.append((normal_for(a, b, c), a, b, c))


def add_box(triangles, x0, y0, z0, x1, y1, z1):
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        raise ValueError("Box dimensions must be positive")

    p000 = (x0, y0, z0)
    p001 = (x0, y0, z1)
    p010 = (x0, y1, z0)
    p011 = (x0, y1, z1)
    p100 = (x1, y0, z0)
    p101 = (x1, y0, z1)
    p110 = (x1, y1, z0)
    p111 = (x1, y1, z1)

    faces = [
        (p000, p010, p011, p001),
        (p100, p101, p111, p110),
        (p000, p001, p101, p100),
        (p010, p110, p111, p011),
        (p000, p100, p110, p010),
        (p001, p011, p111, p101),
    ]

    for a, b, c, d in faces:
        add_triangle(triangles, a, b, c)
        add_triangle(triangles, a, c, d)


def add_cylinder(triangles, cx, cy, z0, z1, radius, segments=48):
    for index in range(segments):
        a0 = 2 * math.pi * index / segments
        a1 = 2 * math.pi * (index + 1) / segments
        p0 = (cx + math.cos(a0) * radius, cy + math.sin(a0) * radius, z0)
        p1 = (cx + math.cos(a1) * radius, cy + math.sin(a1) * radius, z0)
        p2 = (cx + math.cos(a1) * radius, cy + math.sin(a1) * radius, z1)
        p3 = (cx + math.cos(a0) * radius, cy + math.sin(a0) * radius, z1)
        add_triangle(triangles, p0, p1, p2)
        add_triangle(triangles, p0, p2, p3)


def add_front_wall_with_type_c_opening(triangles):
    width = CASE["outer_width"]
    wall = CASE["wall"]
    height = CASE["bottom_height"]
    port_w, port_h = HARDWARE["type_c_opening"]
    cx = CASE["type_c_center_x"]
    cz = CASE["type_c_center_z"]
    x0 = cx - port_w / 2
    x1 = cx + port_w / 2
    z0 = cz - port_h / 2
    z1 = cz + port_h / 2

    add_box(triangles, 0.0, 0.0, 0.0, width, wall, z0)
    add_box(triangles, 0.0, 0.0, z1, width, wall, height)
    add_box(triangles, 0.0, 0.0, z0, x0, wall, z1)
    add_box(triangles, x1, 0.0, z0, width, wall, z1)


def add_bottom_shell(triangles):
    width = CASE["outer_width"]
    length = CASE["outer_length"]
    wall = CASE["wall"]
    floor = CASE["floor"]
    height = CASE["bottom_height"]

    add_box(triangles, 0.0, 0.0, 0.0, width, length, floor)
    add_front_wall_with_type_c_opening(triangles)
    add_box(triangles, 0.0, length - wall, 0.0, width, length, height)
    add_box(triangles, 0.0, 0.0, 0.0, wall, length, height)
    add_box(triangles, width - wall, 0.0, 0.0, width, length, height)

    board_z = floor
    rail_h = 1.2
    esp_x = CASE["esp32_origin_x"]
    esp_y = CASE["esp32_origin_y"]
    esp_w, esp_l = HARDWARE["esp32_board"]
    rgb_x = CASE["rgb_origin_x"]
    rgb_y = CASE["rgb_origin_y"]
    rgb_w, rgb_l = HARDWARE["rgb_module"]

    add_box(triangles, esp_x - 0.7, esp_y, board_z, esp_x + 0.8, esp_y + esp_l, board_z + rail_h)
    add_box(triangles, esp_x + esp_w - 0.8, esp_y, board_z, esp_x + esp_w + 0.7, esp_y + esp_l, board_z + rail_h)
    add_box(triangles, esp_x, esp_y + esp_l - 1.0, board_z, esp_x + esp_w, esp_y + esp_l + 0.6, board_z + rail_h)

    add_box(triangles, rgb_x - 0.8, rgb_y, board_z, rgb_x + 0.9, rgb_y + rgb_l, board_z + rail_h)
    add_box(triangles, rgb_x + rgb_w - 0.9, rgb_y, board_z, rgb_x + rgb_w + 0.8, rgb_y + rgb_l, board_z + rail_h)
    add_box(triangles, rgb_x, rgb_y + rgb_l - 1.0, board_z, rgb_x + rgb_w, rgb_y + rgb_l + 0.7, board_z + rail_h)

    channel_x0 = CASE["type_c_center_x"] - CASE["wire_channel_width"] / 2
    channel_x1 = CASE["type_c_center_x"] + CASE["wire_channel_width"] / 2
    add_box(triangles, channel_x0, 29.0, board_z, channel_x0 + 1.0, 38.0, board_z + 0.9)
    add_box(triangles, channel_x1 - 1.0, 29.0, board_z, channel_x1, 38.0, board_z + 0.9)

    for x, y in ((4.5, 4.5), (33.5, 4.5), (4.5, 79.5), (33.5, 79.5)):
        add_cylinder(triangles, x, y, floor, height - 1.0, 1.8, 24)


def is_lid_hole_cell(x0, y0, x1, y1):
    led = circle_intersects_rect(
        CASE["led_center_x"], CASE["led_center_y"], CASE["led_hole_radius"], x0, y0, x1, y1
    )
    boot = circle_intersects_rect(
        CASE["boot_button_center_x"], CASE["button_center_y"], CASE["button_hole_radius"], x0, y0, x1, y1
    )
    reset = circle_intersects_rect(
        CASE["reset_button_center_x"], CASE["button_center_y"], CASE["button_hole_radius"], x0, y0, x1, y1
    )
    vents = [
        (7.0, 29.0, 31.0, 31.5),
        (7.0, 34.0, 31.0, 36.5),
        (7.0, 75.0, 31.0, 77.5),
    ]
    cell = (x0, y0, x1, y1)
    return led or boot or reset or any(rects_intersect(cell, vent) for vent in vents)


def add_lid_top(triangles):
    offset = CASE["lid_offset_x"]
    width = CASE["outer_width"]
    length = CASE["outer_length"]
    thickness = CASE["lid_thickness"]
    step = CASE["lid_grid_step"]

    x = 0.0
    while x < width:
        x_next = min(width, x + step)
        y = 0.0
        while y < length:
            y_next = min(length, y + step)
            if not is_lid_hole_cell(x, y, x_next, y_next):
                add_box(triangles, offset + x, y, 0.0, offset + x_next, y_next, thickness)
            y = y_next
        x = x_next


def add_lid_lip_and_hole_bezels(triangles):
    offset = CASE["lid_offset_x"]
    width = CASE["outer_width"]
    length = CASE["outer_length"]
    thickness = CASE["lid_thickness"]
    lip_h = CASE["lid_lip_height"]
    inset = 2.35
    lip_wall = 1.2

    add_box(triangles, offset + inset, inset, thickness, offset + width - inset, inset + lip_wall, thickness + lip_h)
    add_box(
        triangles,
        offset + inset,
        length - inset - lip_wall,
        thickness,
        offset + width - inset,
        length - inset,
        thickness + lip_h,
    )
    add_box(triangles, offset + inset, inset, thickness, offset + inset + lip_wall, length - inset, thickness + lip_h)
    add_box(
        triangles,
        offset + width - inset - lip_wall,
        inset,
        thickness,
        offset + width - inset,
        length - inset,
        thickness + lip_h,
    )

    add_cylinder(
        triangles,
        offset + CASE["led_center_x"],
        CASE["led_center_y"],
        thickness,
        thickness + 1.0,
        CASE["led_hole_radius"] + 1.0,
        CASE["circular_hole_segments"],
    )
    for x in (CASE["boot_button_center_x"], CASE["reset_button_center_x"]):
        add_cylinder(
            triangles,
            offset + x,
            CASE["button_center_y"],
            thickness,
            thickness + 0.8,
            4.0,
            CASE["circular_hole_segments"],
        )


def write_binary_stl(path, triangles):
    header = b"ESP32-C3 SuperMini RGB real-layout enclosure".ljust(80, b" ")
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(struct.pack("<I", len(triangles)))
        for normal, a, b, c in triangles:
            handle.write(struct.pack("<12fH", *(normal + a + b + c), 0))


def generate_case(path):
    triangles = []
    add_bottom_shell(triangles)
    add_lid_top(triangles)
    add_lid_lip_and_hole_bezels(triangles)
    write_binary_stl(path, triangles)
    return {"path": path, "triangles": len(triangles)}


def main():
    out_path = os.path.join(os.path.dirname(__file__), "esp32c3_rgb_case.stl")
    stats = generate_case(out_path)
    print(f"Wrote {stats['path']}")
    print(f"Triangles: {stats['triangles']}")
    print(f"Tray outer: {CASE['outer_width']} x {CASE['outer_length']} x {CASE['bottom_height']} mm")
    print("Layout: Type-C front, ESP32 front bay, wire channel, RGB module rear bay")


if __name__ == "__main__":
    main()
