from datetime import datetime, timedelta, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings
from app.database import get_db

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_token(user_id: str, email: str) -> str:
    exp = datetime.now(timezone.utc) + timedelta(days=settings.jwt_expire_days)
    payload = {"user_id": user_id, "email": email, "exp": exp}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        )


def maybe_refresh_token(payload: dict) -> str | None:
    """Return a fresh token if the current one expires within the threshold."""
    exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
    remaining = exp - datetime.now(timezone.utc)
    if remaining < timedelta(days=settings.jwt_refresh_threshold_days):
        return create_token(payload["user_id"], payload["email"])
    return None


async def get_current_user(
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    ) -> dict:
    payload = decode_token(creds.credentials)
    try:
        user_id = ObjectId(payload["user_id"])
    except (KeyError, TypeError, InvalidId):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )
    user = await get_db().users.find_one({"_id": user_id})
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )
    user["_id"] = str(user["_id"])
    user["_token_payload"] = payload
    return user
