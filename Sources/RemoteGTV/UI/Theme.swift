import SwiftUI

struct Theme {
    struct Colors {
        static let darkBase = Color(red: 0.15, green: 0.15, blue: 0.17)
        static let lightShadow = Color(red: 0.2, green: 0.2, blue: 0.22)
        static let darkShadow = Color(red: 0.1, green: 0.1, blue: 0.12)
        
        static let statusConnected = Color.green
        static let statusConnecting = Color.yellow
        static let statusError = Color.red
        static let statusDisconnected = Color.gray
        
        static let textPrimary = Color.white.opacity(0.9)
        static let textSecondary = Color.gray
    }
    
    struct Layout {
        static let cornerRadius: CGFloat = 10
        static let buttonSize: CGFloat = 60
        static let smallButtonSize: CGFloat = 50
    }
}
