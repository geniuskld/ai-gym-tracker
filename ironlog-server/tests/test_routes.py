"""Route-level tests for the FastAPI contracts.

These use the real routers plus dependency overrides and a tiny async fake DB.
That keeps the tests fast while still exercising request parsing, dependency
wiring, response shapes, and the route-side denormalization logic.
"""

from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.auth import get_current_user
from app.routes import analytics as analytics_route
from app.routes import agent_instructions as agent_instructions_route
from app.routes import log as log_route
from app.routes import plan as plan_route


class AsyncCursor:
    def __init__(self, docs):
        self.docs = list(docs)

    def __aiter__(self):
        self._iter = iter(self.docs)
        return self

    async def __anext__(self):
        try:
            return next(self._iter)
        except StopIteration:
            raise StopAsyncIteration

    def limit(self, n):
        self.docs = self.docs[:n]
        return self


class FakeCollection:
    def __init__(self, docs=None, aggregate_docs=None):
        self.docs = list(docs or [])
        self.aggregate_docs = list(aggregate_docs or [])
        self.upserts = []

    def aggregate(self, pipeline):
        self.last_pipeline = pipeline
        return AsyncCursor(self.aggregate_docs)

    def find(self, query=None, projection=None, sort=None):
        query = query or {}
        docs = [d for d in self.docs if self._matches(d, query)]
        return AsyncCursor([self._project(d, projection) for d in docs])

    async def find_one(self, query, sort=None, projection=None):
        for doc in self.docs:
            if self._matches(doc, query):
                return self._project(doc, projection)
        return None

    async def insert_one(self, doc):
        self.docs.append(dict(doc))
        return SimpleNamespace(inserted_id="inserted")

    async def update_one(self, query, update, upsert=False):
        doc = dict(update.get("$set", {}))
        self.upserts.append({"query": query, "doc": doc, "upsert": upsert})
        self.docs.append(doc)
        return SimpleNamespace(upserted_id=doc.get("id"), modified_count=1)

    async def count_documents(self, query):
        return len([d for d in self.docs if self._matches(d, query)])

    def _matches(self, doc, query):
        for key, expected in query.items():
            value = doc.get(key)
            if isinstance(expected, dict):
                if "$in" in expected and value not in expected["$in"]:
                    return False
                if "$gte" in expected and value < expected["$gte"]:
                    return False
                if "$ne" in expected and value == expected["$ne"]:
                    return False
                continue
            if value != expected:
                return False
        return True

    def _project(self, doc, projection):
        if not projection:
            return dict(doc)
        out = dict(doc)
        for key, include in projection.items():
            if include == 0:
                out.pop(key, None)
        return out


class FakeDB:
    def __init__(self):
        self.plans = FakeCollection()
        self.exercises = FakeCollection()
        self.workout_logs = FakeCollection()
        self.agent_instructions = FakeCollection()


def make_client(monkeypatch, db, *modules):
    app = FastAPI()
    app.include_router(plan_route.router)
    app.include_router(log_route.router)
    app.include_router(analytics_route.router)
    app.dependency_overrides[get_current_user] = lambda: {
        "_id": "user-1",
        "_token_payload": None,
    }
    for module in modules:
        monkeypatch.setattr(module, "get_db", lambda db=db: db)
    return TestClient(app)


def test_get_plans_returns_full_polymorphic_payload(monkeypatch):
    db = FakeDB()
    db.plans.aggregate_docs = [
        {
            "plan_type": "cycling",
            "plan_id": "c1",
            "plan_version": 2,
            "plan_name": "Bike",
            "templates": [{"id": "w1", "segments": []}],
        },
        {
            "plan_type": "strength",
            "plan_id": "s1",
            "plan_version": 3,
            "plan_name": "Lift",
            "templates": [{"id": "d1", "groups": []}],
        },
    ]
    client = make_client(monkeypatch, db, plan_route)

    response = client.get("/plans")

    assert response.status_code == 200
    body = response.json()
    assert [p["plan_type"] for p in body] == ["cycling", "strength"]
    assert body[0]["templates"][0]["id"] == "w1"
    assert body[1]["plan_version"] == 3


def test_agent_plan_import_instructions_available(monkeypatch):
    db = FakeDB()
    app = FastAPI()
    app.include_router(agent_instructions_route.router)
    monkeypatch.setattr(agent_instructions_route, "get_db", lambda: db)
    client = TestClient(app)

    response = client.get("/agent-instructions/plan-import")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/markdown")
    assert "GET /exercises/catalog?plan_type=strength" in response.text
    assert "Plan Version Rules" in response.text


def test_agent_plan_import_json_includes_live_links(monkeypatch):
    db = FakeDB()
    app = FastAPI()
    app.include_router(agent_instructions_route.router)
    monkeypatch.setattr(agent_instructions_route, "get_db", lambda: db)
    client = TestClient(app)

    response = client.get("/agent-instructions/plan-import.json")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == "plan-import"
    assert body["live_references"]["strength_schema"].endswith(
        "/schema?type=strength"
    )
    assert "Required Live References" in body["content"]


def test_agent_plan_import_prefers_database_content(monkeypatch):
    db = FakeDB()
    db.agent_instructions.docs = [{
        "_id": "plan-import",
        "title": "Custom Instructions",
        "content": "# Custom\n\nGET /schema?type=strength",
        "updated_at": "2026-05-03T00:00:00Z",
    }]
    app = FastAPI()
    app.include_router(agent_instructions_route.router)
    monkeypatch.setattr(agent_instructions_route, "get_db", lambda: db)
    client = TestClient(app)

    response = client.get("/agent-instructions/plan-import.json")

    assert response.status_code == 200
    body = response.json()
    assert body["source"] == "database"
    assert body["title"] == "Custom Instructions"
    assert body["content"].startswith("# Custom")


def test_agent_plan_import_can_be_updated(monkeypatch):
    db = FakeDB()
    app = FastAPI()
    app.include_router(agent_instructions_route.router)
    app.dependency_overrides[get_current_user] = lambda: {"_id": "user-1"}
    monkeypatch.setattr(agent_instructions_route, "get_db", lambda: db)
    client = TestClient(app)

    response = client.put(
        "/agent-instructions/plan-import",
        json={"content": "# Updated\n\nUse live references."},
    )

    assert response.status_code == 200
    assert response.json()["content_length"] > 0
    assert db.agent_instructions.upserts[0]["query"] == {"_id": "plan-import"}
    assert db.agent_instructions.upserts[0]["doc"]["content"].startswith("# Updated")


def test_post_log_denorms_body_part_from_catalog_id(monkeypatch):
    db = FakeDB()
    db.exercises.docs = [
        {"slug": "leg_press_machine", "body_part": "legs"},
    ]
    client = make_client(monkeypatch, db, log_route)

    response = client.post("/log", json={
        "workouts": [{
            "id": "w1",
            "plan_type": "strength",
            "plan_id": "p1",
            "plan_version": 1,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "exercises": [{
                "exercise_id": "e1",
                "catalog_id": "leg_press_machine",
                "exercise_name": "Leg press",
                "sets": [{"set_type": "working", "weight_kg": 100, "reps": 10}],
            }],
        }],
    })

    assert response.status_code == 200
    stored = db.workout_logs.upserts[0]["doc"]
    assert stored["exercises"][0]["body_part"] == "legs"


def test_post_log_denorms_body_part_from_plan_fallback(monkeypatch):
    db = FakeDB()
    db.plans.docs = [{
        "user_id": "user-1",
        "plan_id": "p1",
        "plan_version": 1,
        "templates": [{
            "groups": [{
                "exercises": [{"id": "e1", "body_part": "back"}],
            }],
        }],
    }]
    client = make_client(monkeypatch, db, log_route)

    response = client.post("/log", json={
        "workouts": [{
            "id": "w2",
            "plan_type": "strength",
            "plan_id": "p1",
            "plan_version": 1,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "exercises": [{
                "exercise_id": "e1",
                "exercise_name": "Pulldown",
                "sets": [{"set_type": "working", "weight_kg": 60, "reps": 12}],
            }],
        }],
    })

    assert response.status_code == 200
    stored = db.workout_logs.upserts[0]["doc"]
    assert stored["exercises"][0]["body_part"] == "back"


def test_exercise_progress_route_uses_catalog_group_key(monkeypatch):
    db = FakeDB()
    now = datetime.now(timezone.utc)
    db.workout_logs.aggregate_docs = [
        {
            "workout_id": "w1",
            "date": now.isoformat(),
            "plan_id": "p1",
            "exercise_id": "e1",
            "exercise_name": "Leg press",
            "catalog_id": "leg_press_machine",
            "body_part": "legs",
            "weight_kg": 100,
            "reps": 10,
        },
    ]
    db.exercises.docs = [{
        "slug": "leg_press_machine",
        "name": "Leg Press",
        "body_part": "legs",
        "primary_muscles": ["quadriceps", "glutes"],
    }]
    client = make_client(monkeypatch, db, analytics_route)

    response = client.get("/analytics/strength/exercise-progress")

    assert response.status_code == 200
    body = response.json()
    assert body[0]["key"] == "leg_press_machine"
    assert body[0]["key_type"] == "catalog_id"
    assert body[0]["display_name"] == "Leg Press"
    assert body[0]["points"][0]["volume"] == 1000
