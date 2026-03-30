import Foundation
import SwiftData

enum PlanImportError: LocalizedError {
    case invalidJSON(String)
    case unsupportedVersion(String)
    case emptyTemplates
    case duplicatePlan(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .unsupportedVersion(let v):
            return "Unsupported version: \(v). Expected 1.0"
        case .emptyTemplates:
            return "Plan must contain at least one template"
        case .duplicatePlan(let name):
            return "Plan '\(name)' already exists"
        }
    }
}

final class PlanImportService {

    // MARK: - Parse JSON string into Codable struct

    static func parse(_ jsonString: String) throws -> WorkoutPlanJSON {
        guard let data = jsonString.data(using: .utf8) else {
            throw PlanImportError.invalidJSON("Failed to read string as UTF-8")
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> WorkoutPlanJSON {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let plan: WorkoutPlanJSON
        do {
            plan = try decoder.decode(WorkoutPlanJSON.self, from: data)
        } catch let error as DecodingError {
            throw PlanImportError.invalidJSON(error.friendlyDescription)
        }

        guard plan.version == "1.0" else {
            throw PlanImportError.unsupportedVersion(plan.version)
        }
        guard !plan.templates.isEmpty else {
            throw PlanImportError.emptyTemplates
        }

        return plan
    }

    // MARK: - Import into SwiftData

    @MainActor
    static func importPlan(
        _ json: WorkoutPlanJSON,
        into context: ModelContext,
        replaceExisting: Bool = false
    ) throws -> SDPlan {
        let descriptor = FetchDescriptor<SDPlan>(
            predicate: #Predicate { $0.planName == json.planName }
        )
        let existing = try context.fetch(descriptor)

        if let old = existing.first {
            if replaceExisting {
                context.delete(old)
            } else {
                throw PlanImportError.duplicatePlan(json.planName)
            }
        }

        let plan = SDPlan(
            planName: json.planName,
            createdAt: json.createdAt,
            author: json.author,
            notes: json.notes
        )
        context.insert(plan)

        for (tIdx, tJSON) in json.templates.enumerated() {
            let template = SDTemplate(
                templateId: tJSON.id,
                name: tJSON.name,
                notes: tJSON.notes,
                sortOrder: tIdx
            )
            template.plan = plan

            for (gIdx, gJSON) in tJSON.groups.enumerated() {
                let group = SDExerciseGroup(
                    name: gJSON.name,
                    sortOrder: gIdx
                )
                group.template = template

                for (eIdx, eJSON) in gJSON.exercises.enumerated() {
                    let exercise = SDExercise(
                        exerciseId: eJSON.id,
                        name: eJSON.name,
                        bodyPart: eJSON.bodyPart.rawValue,
                        equipment: eJSON.equipment?.rawValue,
                        restSeconds: eJSON.restSeconds ?? 90,
                        technique: eJSON.technique?.rawValue ?? "straight",
                        supersetWith: eJSON.supersetWith,
                        tempo: eJSON.tempo,
                        notes: eJSON.notes,
                        stretchFocus: eJSON.stretchFocus ?? false,
                        sortOrder: eIdx,
                        maxMiniSets: eJSON.maxMiniSets
                    )
                    exercise.group = group

                    for (sIdx, sJSON) in eJSON.sets.enumerated() {
                        let set = SDPrescribedSet(
                            type: sJSON.type?.rawValue ?? "working",
                            reps: sJSON.reps,
                            weightKg: sJSON.weightKg,
                            rir: sJSON.rir,
                            weightPercentDrop: sJSON.weightPercentDrop,
                            sortOrder: sIdx
                        )
                        set.exercise = exercise
                    }
                }
            }
        }

        return plan
    }
}

// MARK: - DecodingError helper

extension DecodingError {
    var friendlyDescription: String {
        switch self {
        case .keyNotFound(let key, let ctx):
            return "Missing key '\(key.stringValue)' at \(ctx.codingPath.pathString)"
        case .typeMismatch(let type, let ctx):
            return "Type mismatch for \(type) at \(ctx.codingPath.pathString)"
        case .valueNotFound(let type, let ctx):
            return "Null value for \(type) at \(ctx.codingPath.pathString)"
        case .dataCorrupted(let ctx):
            return "Corrupted data at \(ctx.codingPath.pathString)"
        @unknown default:
            return localizedDescription
        }
    }
}

private extension [CodingKey] {
    var pathString: String {
        map(\.stringValue).joined(separator: ".")
    }
}
