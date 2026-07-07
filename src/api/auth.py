from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel
import os

SECRET_KEY = os.getenv("SECRET_KEY", "changeme_in_production_use_long_random_string")
ALGORITHM  = "HS256"
TOKEN_EXPIRE_HOURS = 24

pwd_context    = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme  = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

# ── Users database (simple — replace with DB in production) ──────────────────
USERS = {
    "admin": {
        "username": "admin",
        "hashed_password": pwd_context.hash("patchguard2026"),
        "role": "admin"
    }
}

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

class User(BaseModel):
    username: str
    role: str

def verify_password(plain, hashed):
    return pwd_context.verify(plain, hashed)

def get_user(username: str):
    if username in USERS:
        return USERS[username]
    return None

def authenticate_user(username: str, password: str):
    user = get_user(username)
    if not user:
        return False
    if not verify_password(password, user["hashed_password"]):
        return False
    return user

def create_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(hours=TOKEN_EXPIRE_HOURS))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token invalide ou expire",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = get_user(username)
    if user is None:
        raise credentials_exception
    return User(username=user["username"], role=user["role"])
