import Foundation
import SwiftData

@Model
final class SDExercise {
    var exerciseId: String
    var catalogId: String?
    var name: String
    var bodyPart: String
    var equipment: String?
    var restSeconds: Int
    var technique: String
    var supersetWith: String?
    var tempo: String?
    var notes: String?
    var stretchFocus: Bool
    var sortOrder: Int
    var maxMiniSets: Int?

    var group: SDExerciseGroup?

    @Relationship(deleteRule: .cascade, inverse: \SDPrescribedSet.exercise)
    var prescribedSets: [SDPrescribedSet]

    init(
        exerciseId: String,
        catalogId: String? = nil,
        name: String,
        bodyPart: String,
        equipment: String? = nil,
        restSeconds: Int = 90,
        technique: String = "straight",
        supersetWith: String? = nil,
        tempo: String? = nil,
        notes: String? = nil,
        stretchFocus: Bool = false,
        sortOrder: Int = 0,
        maxMiniSets: Int? = nil
    ) {
        self.exerciseId = exerciseId
        self.catalogId = catalogId
        self.name = name
        self.bodyPart = bodyPart
        self.equipment = equipment
        self.restSeconds = restSeconds
        self.technique = technique
        self.supersetWith = supersetWith
        self.tempo = tempo
        self.notes = notes
        self.stretchFocus = stretchFocus
        self.sortOrder = sortOrder
        self.maxMiniSets = maxMiniSets
        self.prescribedSets = []
    }
}
