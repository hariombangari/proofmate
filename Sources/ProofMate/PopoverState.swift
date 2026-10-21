import Foundation
import ProofMateCore

struct ErrorAction {
    let title: String
    let run: () -> Void
}

enum PopoverState {
    case checking
    case result(original: String, corrected: String, segments: [DiffSegment])
    case unchanged
    case error(message: String, action: ErrorAction?)
}
