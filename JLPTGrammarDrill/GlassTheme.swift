import SwiftUI

/// Soft mesh-gradient content layer the Liquid Glass elements float above.
/// Shared by the hub, home, and exercise screens so the whole app sits on
/// one continuous backdrop.
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base: [Color] = colorScheme == .dark
            ? [Color(red: 0.10, green: 0.08, blue: 0.20), Color(red: 0.05, green: 0.12, blue: 0.22),
               Color(red: 0.14, green: 0.07, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.12)]
            : [Color(red: 0.78, green: 0.86, blue: 1.0), Color(red: 0.92, green: 0.82, blue: 0.98),
               Color(red: 0.80, green: 0.93, blue: 0.96), Color(red: 0.97, green: 0.90, blue: 0.86)]
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.4], [0.6, 0.5], [1.0, 0.6],
                [0.0, 1.0], [0.4, 1.0], [1.0, 1.0]
            ],
            colors: [
                base[0], base[1], base[0],
                base[2], base[3], base[1],
                base[1], base[0], base[2]
            ]
        )
    }
}
