import os
import tempfile
import unittest

from models.generate_case_stl import (
    CASE,
    HARDWARE,
    circle_intersects_rect,
    generate_case,
)


class CaseGeneratorTest(unittest.TestCase):
    def test_case_dimensions_include_requested_hardware_clearance(self):
        self.assertEqual(HARDWARE["esp32_board"], (18.0, 22.52))
        self.assertEqual(HARDWARE["rgb_module"], (26.0, 34.0))
        self.assertGreaterEqual(CASE["inner_width"], 31.0)
        self.assertGreaterEqual(CASE["inner_length"], 72.0)
        self.assertGreaterEqual(CASE["led_hole_radius"], 5.8)
        self.assertGreaterEqual(CASE["button_hole_radius"], 2.5)
        self.assertGreaterEqual(CASE["wire_channel_width"], 10.0)

    def test_layout_follows_real_board_orientation(self):
        self.assertLess(CASE["esp32_origin_y"], CASE["rgb_origin_y"])
        self.assertAlmostEqual(CASE["type_c_center_x"], CASE["outer_width"] / 2, places=2)
        self.assertLess(CASE["type_c_center_y"], CASE["wall"] + 1.0)
        self.assertGreater(CASE["button_center_y"], CASE["type_c_center_y"])
        self.assertGreater(CASE["led_center_y"], CASE["rgb_origin_y"])

    def test_side_wall_vents_are_disabled(self):
        self.assertEqual(CASE["side_wall_vents"], ())

    def test_round_holes_use_fine_resolution(self):
        self.assertLessEqual(CASE["lid_grid_step"], 0.35)
        self.assertGreaterEqual(CASE["circular_hole_segments"], 128)

    def test_circle_rectangle_intersection_marks_hole_cells(self):
        self.assertTrue(circle_intersects_rect(10.0, 10.0, 3.0, 8.0, 8.0, 11.0, 11.0))
        self.assertFalse(circle_intersects_rect(10.0, 10.0, 3.0, 14.0, 14.0, 16.0, 16.0))

    def test_generate_case_writes_binary_stl(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_path = os.path.join(tmpdir, "case.stl")
            stats = generate_case(out_path)

            self.assertTrue(os.path.exists(out_path))
            self.assertGreater(os.path.getsize(out_path), 50_000)
            self.assertGreater(stats["triangles"], 2_000)
            self.assertEqual(stats["path"], out_path)


if __name__ == "__main__":
    unittest.main()
