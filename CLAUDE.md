# CLAUDE.md -- Project Context for Claude Code

## Project: IronLog (ai-gym-tracker)
iOS workout tracker + sync server. AI-assisted training: Claude generates plans, app executes, logs sync back for analysis.

## Repo Structure
- `IronLog/` -- iOS app (Swift, SwiftUI, SwiftData, XcodeGen)
- `ironlog-server/` -- sync server (Python, FastAPI, MongoDB, Docker)
- `schemas/` -- JSON schema docs + sample plan
- `docs/` -- ARCHITECTURE.md, SPEC.md

## Key Decisions
- **iOS 17+**, Swift, SwiftUI, SwiftData (NOT CoreData)
- **MVVM + Services** pattern
- **No manual plan creation** in UI -- JSON import only (from AI or server)
- **Two-layer models**: JSON Codable structs (parsing) + SwiftData @Model (persistence)
- SwiftData models prefixed with `SD` to avoid naming conflicts
- **String foreign keys** between workouts and templates (survives re-import)
- **XcodeGen**: project.yml generates xcodeproj
- **Shared base contract**: plan_type + plan_id + plan_version + plan_name + schema (timestamp) + created_at
- **PlanType enum**: server (Python Enum) and client (Swift enum) must stay in sync
- **Schema identification**: each plan carries `schema` field (timestamp, e.g. "2026-04-09T22:00:00Z") referencing the schema it was built against. App validates plan structure; on mismatch shows both timestamps for debugging

## Sync Architecture
- Server: FastAPI + MongoDB + Docker (`ironlog-server/`)
- Auth: email/password -> JWT (90-day sliding expiry, X-Refreshed-Token header)
- Client stores JWT in Keychain, email in Keychain
- Default server URL: `http://v170184.hosted-by-vdsina.com:8844`
- Plan sync: GET /plan -> compare version -> import if newer
- Log upload: fire-and-forget after workout finish
- Log delete: fire-and-forget on swipe-to-delete in history

## Plan Schema & Compatibility
- Each plan carries `schema` field -- timestamp identifier of the schema used to create it
- Server JSON schema has `x-schema-id` with the same timestamp; Claude copies it into the plan
- App has `PlanSchema.id` constant with its supported schema timestamp
- **Validation is structural**: app checks plan_type, body_part, technique enums, required fields
- If stored plan doesn't pass validation -> "not supported" with schema timestamps for debugging
- If server plan can't be decoded -> "Update app" banner
- Server rejects unknown plan_type (422)

## Server Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | no | Healthcheck |
| GET | /schema | no | Schema description per plan_type |
| POST | /register | no | Create account -> JWT |
| POST | /login | no | Login -> JWT |
| GET | /plans | JWT | List all plans (latest version per plan_id) |
| GET | /plan | JWT | Latest plan by type+id |
| GET | /plan/versions | JWT | Version history |
| PUT | /plan | JWT | Upload new version (validated) |
| POST | /log | JWT | Upsert workout logs |
| GET | /log | JWT | Query logs (since, template_id, type, limit) |
| DELETE | /log/{id} | JWT | Delete workout log |

## Technique Types
| Technique | Timer | Behavior |
|-----------|-------|----------|
| straight | After each set | Standard sequential |
| drop_set | After last drop only | Working + drops with weight % reduction |
| rest_pause | 15-20s between continuations | Main set + continuations at same weight |
| myo_reps | 5s between minis | Activation + dynamic mini rows (max_mini_sets) |
| superset | After both exercises | Paired A1 -> A2 alternating |

## Build
```bash
# iOS
cd IronLog && xcodegen generate && open IronLog.xcodeproj

# Server
cd ironlog-server && docker compose up --build -d
```

## User Context
- Based in Russia (Kaliningrad)
- Training at gym "Albatros South"
- Spinal curvature -- no axial loading
- 30 min bike before strength, 2x/week full body
- Communicate in Russian
