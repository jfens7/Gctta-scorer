import Foundation

struct VenueMapper {
    enum ScreenSide { case left, right }
    
    static func wallSide(for tableNumber: String) -> ScreenSide {
        let table = Int(tableNumber) ?? 0
        // Group A: Wall is on the LEFT
        if table == 1 || table == 8 { return .left }
        // Group B & Default: Wall is on the RIGHT
        return .right
    }
}
