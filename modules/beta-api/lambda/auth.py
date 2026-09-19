import os
import re
import time
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError


TABLE_NAME = os.environ["APPLICANTS_TABLE"]
USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
CLIENT_ID = os.environ["COGNITO_MOBILE_CLIENT_ID"]

AUTH_SESSION_SECONDS = 10 * 60
ALLOWED_STATUSES = {"approved", "invited", "active"}

table = boto3.resource("dynamodb").Table(TABLE_NAME)
cognito = boto3.client("cognito-idp")


def _now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _normalize_email(value):
    return str(value or "").strip().lower()


def _applicant(email):
    result = table.get_item(
        Key={"email": email},
        ConsistentRead=True,
    )
    return result.get("Item")


def _allowed(item):
    if not item:
        return False
    return str(item.get("status", "")).lower() in ALLOWED_STATUSES


def _ensure_cognito_user(email):
    try:
        return cognito.admin_get_user(
            UserPoolId=USER_POOL_ID,
            Username=email,
        )
    except cognito.exceptions.UserNotFoundException:
        # Passwordless Cognito user. EMAIL_OTP is the authentication factor.
        cognito.admin_create_user(
            UserPoolId=USER_POOL_ID,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"},
            ],
            MessageAction="SUPPRESS",
        )

        return cognito.admin_get_user(
            UserPoolId=USER_POOL_ID,
            Username=email,
        )


def auth_start(payload):
    email = _normalize_email(payload.get("email"))

    if not email or "@" not in email:
        return 400, {"ok": False, "error": "invalid_request"}

    item = _applicant(email)

    # Deliberately do not disclose whether an address is approved.
    if not _allowed(item):
        return 202, {"ok": True, "status": "code_sent"}

    try:
        user = _ensure_cognito_user(email)

        result = cognito.admin_initiate_auth(
            UserPoolId=USER_POOL_ID,
            ClientId=CLIENT_ID,
            AuthFlow="USER_AUTH",
            AuthParameters={
                "USERNAME": email,
                "PREFERRED_CHALLENGE": "EMAIL_OTP",
            },
        )

        session = result.get("Session")
        challenge = result.get("ChallengeName")

        if challenge != "EMAIL_OTP" or not session:
            print(f"auth_start_unexpected_challenge={challenge or 'none'}")
            return 503, {"ok": False, "error": "temporarily_unavailable"}

        challenge_parameters = result.get("ChallengeParameters") or {}
        auth_username = (
            challenge_parameters.get("USERNAME")
            or user.get("Username")
            or email
        )

        expires_at = int(time.time()) + AUTH_SESSION_SECONDS

        current_status = str(item.get("status", "")).lower()
        next_status = "active" if current_status == "active" else "invited"

        table.update_item(
            Key={"email": email},
            UpdateExpression=(
                "SET authSession = :session, "
                "authSessionExpiresAt = :expires, "
                "authUsername = :username, "
                "#status = :status, "
                "updatedAt = :updated"
            ),
            ExpressionAttributeNames={
                "#status": "status",
            },
            ExpressionAttributeValues={
                ":session": session,
                ":expires": expires_at,
                ":username": auth_username,
                ":status": next_status,
                ":updated": _now_iso(),
            },
        )

        return 202, {"ok": True, "status": "code_sent"}

    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        print(f"auth_start_error={code}")
        return 503, {"ok": False, "error": "temporarily_unavailable"}


def auth_verify(payload):
    email = _normalize_email(payload.get("email"))
    code = str(payload.get("code") or "").strip()

    if not email or not code.isdigit() or not (4 <= len(code) <= 12):
        return 400, {"ok": False, "error": "invalid_request"}

    item = _applicant(email)

    if not _allowed(item):
        return 401, {"ok": False, "error": "invalid_code"}

    session = item.get("authSession")
    expires_at = int(item.get("authSessionExpiresAt") or 0)
    auth_username = item.get("authUsername") or email

    if not session or expires_at <= int(time.time()):
        return 401, {"ok": False, "error": "invalid_code"}

    try:
        result = cognito.admin_respond_to_auth_challenge(
            UserPoolId=USER_POOL_ID,
            ClientId=CLIENT_ID,
            ChallengeName="EMAIL_OTP",
            Session=session,
            ChallengeResponses={
                "USERNAME": auth_username,
                "EMAIL_OTP_CODE": code,
            },
        )

        auth = result.get("AuthenticationResult")

        if not auth or not auth.get("AccessToken"):
            return 401, {"ok": False, "error": "invalid_code"}

        user = cognito.admin_get_user(
            UserPoolId=USER_POOL_ID,
            Username=email,
        )

        attributes = {
            entry["Name"]: entry["Value"]
            for entry in user.get("UserAttributes", [])
        }

        now = _now_iso()

        table.update_item(
            Key={"email": email},
            UpdateExpression=(
                "SET #status = :active, "
                "updatedAt = :updated, "
                "lastAuthenticatedAt = :updated "
                "REMOVE authSession, authSessionExpiresAt, authUsername"
            ),
            ExpressionAttributeNames={
                "#status": "status",
            },
            ExpressionAttributeValues={
                ":active": "active",
                ":updated": now,
            },
        )

        expires_in = int(auth.get("ExpiresIn") or 3600)
        expires = (
            datetime.now(timezone.utc)
            + timedelta(seconds=expires_in)
        ).isoformat().replace("+00:00", "Z")

        return 200, {
            "ok": True,
            "email": attributes.get("email", email),
            "userId": attributes.get("sub", user.get("Username")),
            "accessToken": auth["AccessToken"],
            "refreshToken": auth.get("RefreshToken"),
            "expiresAt": expires,
        }

    except ClientError as exc:
        error = exc.response.get("Error", {}).get("Code", "ClientError")

        if error in {
            "CodeMismatchException",
            "ExpiredCodeException",
            "NotAuthorizedException",
        }:
            return 401, {"ok": False, "error": "invalid_code"}

        print(f"auth_verify_error={error}")
        return 503, {"ok": False, "error": "temporarily_unavailable"}


def auth_refresh(payload):
    refresh_token = str(payload.get("refreshToken") or "").strip()

    if not refresh_token:
        return 400, {"ok": False, "error": "invalid_request"}

    try:
        result = cognito.get_tokens_from_refresh_token(
            RefreshToken=refresh_token,
            ClientId=CLIENT_ID,
        )

        auth = result.get("AuthenticationResult") or {}

        if not auth.get("AccessToken"):
            return 401, {"ok": False, "error": "reauthentication_required"}

        expires_in = int(auth.get("ExpiresIn") or 3600)
        expires = (
            datetime.now(timezone.utc)
            + timedelta(seconds=expires_in)
        ).isoformat().replace("+00:00", "Z")

        return 200, {
            "ok": True,
            "accessToken": auth["AccessToken"],
            # Rotation normally returns a replacement refresh token.
            "refreshToken": auth.get("RefreshToken") or refresh_token,
            "expiresAt": expires,
        }

    except ClientError as exc:
        error = exc.response.get("Error", {}).get("Code", "ClientError")

        if error in {
            "NotAuthorizedException",
            "RefreshTokenReuseException",
        }:
            return 401, {
                "ok": False,
                "error": "reauthentication_required",
            }

        print(f"auth_refresh_error={error}")
        return 503, {"ok": False, "error": "temporarily_unavailable"}