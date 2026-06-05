# ESP32-C3 RGB Case Design

## Goal

Create one STL file for a printable enclosure that holds an ESP32-C3 SuperMini, one cased RGB LED module, and four jumper wires. The case exposes the ESP32-C3 Type-C port, the RGB LED bulb, and access holes for BOOT and RESET. It also includes ventilation slots.

## Dimensions

- ESP32-C3 SuperMini board: 18.0 x 22.52 mm, based on the supplied real product image.
- RGB LED module with red case: 26.0 x 34.0 mm, based on the supplied real product image.
- Internal cavity: 34.0 x 80.0 mm.
- Outer bottom shell: 38.0 x 84.0 x 12.0 mm.
- Wall thickness: 2.0 mm.
- Floor thickness: 1.6 mm.
- Lid thickness: 1.8 mm.

## Layout

The bottom shell uses a longitudinal layout that matches the real hardware orientation. The ESP32-C3 sits in the front bay with its Type-C connector facing the front wall. The RGB LED module sits in the rear bay, with a center cable channel between the two modules for the four jumper wires.

## Openings

- Type-C front opening: 12.5 x 6.5 mm with clearance.
- BOOT and RESET access holes: 6.0 mm diameter.
- RGB LED opening: 12.4 mm diameter, allowing the 10.0 mm LED bulb to protrude with print tolerance.
- Ventilation: side wall slots and lid slots.

## Output

The output STL contains two disconnected printable parts in one file: the bottom tray and the lid. They are laid out side-by-side for printing.
