import SwiftUI

/// Design tokens and constants for WhisprFlow
enum Design {
    // MARK: - Colors
    
    enum Colors {
        /// Very light grey background - never pure white
        static let background = Color(hex: "F5F5F7")
        
        /// Pure white for surfaces (pill, cards)
        static let surface = Color.white
        
        /// Near-black charcoal for primary text
        static let textPrimary = Color(hex: "111827")
        
        /// Neutral grey for secondary/metadata text
        static let textSecondary = Color(hex: "6B7280")
        
        /// Light grey for placeholder text
        static let textTertiary = Color(hex: "9CA3AF")
        
        /// Soft lavender accent - use sparingly
        static let accent = Color(hex: "8B5CF6")
        
        /// Success/active state (iOS green)
        static let success = Color(hex: "34C759")
        
        /// Recording indicator color
        static let recording = Color(hex: "34C759")
        
        /// Error state color
        static let error = Color(hex: "EF4444")

        /// Subtle border color for cards, dividers
        static let border = Color(hex: "E5E5E5")

        /// Very light background for input fields, sections
        static let surfaceSecondary = Color(hex: "F9FAFB")

        /// Subtle background for badges, icon buttons
        static let fill = Color(hex: "F3F4F6")

        /// Disabled icon/text color
        static let disabled = Color(hex: "D1D5DB")
    }
    
    // MARK: - Dimensions
    
    enum Pill {
        static let width: CGFloat = 120
        static let height: CGFloat = 44
        static let cornerRadius: CGFloat = 22 // Full capsule
        static let iconSize: CGFloat = 20
        static let padding: CGFloat = 12
        
        /// Distance from bottom of screen
        static let bottomOffset: CGFloat = 40
        
        /// Shadow properties
        static let shadowColor = Color.black.opacity(0.08)
        static let shadowRadius: CGFloat = 12
        static let shadowY: CGFloat = 4
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let stateTransition: SwiftUI.Animation = .easeInOut(duration: 0.2)
        static let pulse: SwiftUI.Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }
    
    // MARK: - Timing
    
    enum Timing {
        /// API request timeout in seconds
        static let transcriptionTimeout: TimeInterval = 30
        
        /// Debounce interval for paste operations
        static let pasteDebounce: TimeInterval = 0.5
        
        /// Audio file retention period
        static let audioRetentionHours: Int = 24
    }
}

// MARK: - Color Extension

// MARK: - Notification Names

extension Notification.Name {
    static let whisprModelChanged = Notification.Name("whisprModelChanged")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
