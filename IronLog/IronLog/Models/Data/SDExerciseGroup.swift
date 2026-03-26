import Foundation
import SwiftData

@Model
final class SDExerciseGroup {
    var name: String
    var sortOrder: Int

    var template: SDTemplate?

    @Relationship(deleteRule: .cascade, inverse: \SDExercise.group)
    var exercises: [SDExercise]

    init(
        name: String,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.sortOrder = sortOrder
        self.exercises = []
    }
}
