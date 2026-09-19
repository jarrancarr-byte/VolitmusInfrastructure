import base64
import json
import os
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from auth import auth_start, auth_verify, auth_refresh

import boto3

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
ADID_RE = re.compile(r"^[A-Za-z0-9_-]{1,80}$")

_dynamodb = boto3.resource("dynamodb")
_secrets = boto3.client("secretsmanager")
_turnstile_secret_cache = None


def _now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(payload, separators=(",", ":")),
    }


def _parse_json(event, max_bytes=32768):
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    if len(body.encode("utf-8")) > max_bytes:
        raise ValueError("request_too_large")
    if not body:
        return {}
    value = json.loads(body)
    if not isinstance(value, dict):
        raise ValueError("object_required")
    return value


def _clean_text(value, max_len):
    if value is None:
        return ""
    return str(value).strip()[:max_len]


def _clean_adid(value):
    candidate = _clean_text(value, 80)
    if candidate and ADID_RE.fullmatch(candidate):
        return candidate
    return ""


def _normalize_email(value):
    email = _clean_text(value, 254).lower()
    if not email or not EMAIL_RE.fullmatch(email):
        raise ValueError("invalid_email")
    return email


def _bool_env(name, default=False):
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _turnstile_secret():
    global _turnstile_secret_cache
    if _turnstile_secret_cache is not None:
        return _turnstile_secret_cache

    arn = os.getenv("TURNSTILE_SECRET_ARN", "")
    if not arn:
        _turnstile_secret_cache = ""
        return ""

    result = _secrets.get_secret_value(SecretId=arn)
    _turnstile_secret_cache = result.get("SecretString", "")
    return _turnstile_secret_cache


def _source_ip(event):
    return event.get("requestContext", {}).get("http", {}).get("sourceIp", "")


def _verify_turnstile(event, payload):
    required = _bool_env("TURNSTILE_REQUIRED", False)
    token = _clean_text(
        payload.get("turnstileToken")
        or payload.get("cf-turnstile-response")
        or payload.get("turnstile_token"),
        4096,
    )

    # The website does not submit a token yet. In beta, verification can be
    # deployed disabled, then turned on after the site sends a token.
    if not token:
        return not required

    secret = _turnstile_secret()
    if not secret:
        return False

    form = {
        "secret": secret,
        "response": token,
    }
    ip = _source_ip(event)
    if ip:
        form["remoteip"] = ip

    request = urllib.request.Request(
        "https://challenges.cloudflare.com/turnstile/v0/siteverify",
        data=urllib.parse.urlencode(form).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    try:
        with urllib.request.urlopen(request, timeout=4) as reply:
            result = json.loads(reply.read().decode("utf-8"))
            return result.get("success") is True
    except Exception as exc:
        print(f"turnstile_verify_error={type(exc).__name__}")
        return False


def _attribution(payload):
    raw = payload.get("attribution") if isinstance(payload.get("attribution"), dict) else {}
    return {
        "firstAdId": _clean_adid(payload.get("firstAdId") or raw.get("firstAdId")),
        "latestAdId": _clean_adid(payload.get("latestAdId") or raw.get("latestAdId")),
        "anonymousId": _clean_text(payload.get("anonymousId") or raw.get("anonymousId"), 128),
        "firstSeenAt": _clean_text(raw.get("firstSeenAt"), 64),
        "latestSeenAt": _clean_text(raw.get("latestSeenAt"), 64),
        "firstLandingPath": _clean_text(raw.get("firstLandingPath"), 512),
        "latestLandingPath": _clean_text(raw.get("latestLandingPath"), 512),
    }


def _signup(event, ios_waitlist=False):
    try:
        payload = _parse_json(event)
        email = _normalize_email(payload.get("email"))
    except (ValueError, TypeError, json.JSONDecodeError):
        return _response(400, {"ok": False, "error": "invalid_request"})

    if payload.get("contactConsent") is not True:
        return _response(400, {"ok": False, "error": "contact_consent_required"})

    if not _verify_turnstile(event, payload):
        return _response(400, {"ok": False, "error": "verification_failed"})

    vehicle_model = _clean_text(payload.get("vehicleModel"), 160)
    device_model = _clean_text(payload.get("deviceModel"), 160)

    if not ios_waitlist:
        if not vehicle_model:
            return _response(400, {"ok": False, "error": "vehicle_model_required"})
        if not device_model:
            return _response(400, {"ok": False, "error": "device_model_required"})

    now = _now_iso()
    attr = _attribution(payload)
    table = _dynamodb.Table(os.environ["APPLICANTS_TABLE"])

    try:
        current = table.get_item(Key={"email": email}, ConsistentRead=True).get("Item") or {}
    except Exception as exc:
        print(f"beta_signup_read_error={type(exc).__name__}")
        return _response(503, {"ok": False, "error": "temporarily_unavailable"})

    current_status = current.get("status")
    android_workflow_states = {"applied", "approved", "invited", "active", "declined"}
    if ios_waitlist:
        if current_status in android_workflow_states:
            status = current_status
            platform = current.get("platform") or "Android"
            signup_type = current.get("signupType") or "android_beta"
        else:
            status = "ios_waitlist"
            platform = "iOS"
            signup_type = "ios_waitlist"
    else:
        status = current_status if current_status in {"approved", "invited", "active", "declined"} else "applied"
        platform = "Android"
        signup_type = "android_beta"

    # Preserve the earliest non-empty attribution while allowing an initial
    # direct/blank submission to acquire a real first-touch value later.
    first_ad_id = current.get("firstAdId") or attr["firstAdId"]
    anonymous_id = current.get("anonymousId") or attr["anonymousId"]
    first_seen_at = current.get("firstSeenAt") or attr["firstSeenAt"]
    first_landing_path = current.get("firstLandingPath") or attr["firstLandingPath"]

    # Never erase useful information merely because an optional field was
    # omitted on a later submission (especially an iOS waitlist submission
    # from somebody who is already an Android applicant).
    stored_vehicle_model = vehicle_model or _clean_text(current.get("vehicleModel"), 160)
    stored_battery_voltage = _clean_text(payload.get("batteryVoltage"), 40) or _clean_text(current.get("batteryVoltage"), 40)
    stored_device_model = device_model or _clean_text(current.get("deviceModel"), 160)
    stored_android_version = _clean_text(payload.get("androidVersion"), 64) or _clean_text(current.get("androidVersion"), 64)
    stored_detection_source = _clean_text(payload.get("deviceDetectionSource"), 64) or _clean_text(current.get("deviceDetectionSource"), 64)
    stored_region = _clean_text(payload.get("region"), 160) or _clean_text(current.get("region"), 160)

    values = {
        ":created": now,
        ":updated": now,
        ":platform": platform,
        ":signupType": signup_type,
        ":status": status,
        ":vehicleModel": stored_vehicle_model,
        ":batteryVoltage": stored_battery_voltage,
        ":deviceModel": stored_device_model,
        ":androidVersion": stored_android_version,
        ":deviceDetectionSource": stored_detection_source,
        ":region": stored_region,
        ":contactConsent": True,
        ":contactConsentAt": now,
        ":firstAdId": first_ad_id,
        ":latestAdId": attr["latestAdId"],
        ":anonymousId": anonymous_id,
        ":firstSeenAt": first_seen_at,
        ":latestSeenAt": attr["latestSeenAt"],
        ":firstLandingPath": first_landing_path,
        ":latestLandingPath": attr["latestLandingPath"],
    }

    try:
        table.update_item(
            Key={"email": email},
            UpdateExpression=(
                "SET createdAt = if_not_exists(createdAt, :created), "
                "updatedAt = :updated, platform = :platform, signupType = :signupType, "
                "#status = :status, vehicleModel = :vehicleModel, batteryVoltage = :batteryVoltage, "
                "deviceModel = :deviceModel, androidVersion = :androidVersion, "
                "deviceDetectionSource = :deviceDetectionSource, #region = :region, "
                "contactConsent = :contactConsent, contactConsentAt = :contactConsentAt, "
                "firstAdId = :firstAdId, latestAdId = :latestAdId, "
                "anonymousId = :anonymousId, "
                "firstSeenAt = :firstSeenAt, latestSeenAt = :latestSeenAt, "
                "firstLandingPath = :firstLandingPath, "
                "latestLandingPath = :latestLandingPath"
            ),
            ExpressionAttributeNames={"#status": "status", "#region": "region"},
            ExpressionAttributeValues=values,
        )
    except Exception as exc:
        print(f"beta_signup_write_error={type(exc).__name__}")
        return _response(503, {"ok": False, "error": "temporarily_unavailable"})

    return _response(202, {"ok": True, "status": "received"})


def _mobile_config():
    return _response(
        200,
        {
            "latestVersion": os.getenv("MOBILE_LATEST_VERSION", ""),
            "latestVersionCode": int(os.getenv("MOBILE_LATEST_VERSION_CODE", "0") or 0),
            "minimumVersionCode": int(os.getenv("MOBILE_MINIMUM_VERSION_CODE", "0") or 0),
            "betaEnabled": _bool_env("MOBILE_BETA_ENABLED", True),
            "message": os.getenv("MOBILE_BETA_MESSAGE", ""),
            "playStoreUrl": os.getenv("MOBILE_PLAY_STORE_URL", ""),
        },
    )


def lambda_handler(event, context):
    route_key = event.get("routeKey", "")

    if route_key == "GET /health":
        return _response(200, {"ok": True, "service": "voltimus-beta-api"})
    if route_key == "GET /mobile-config":
        return _mobile_config()
    if route_key == "POST /beta":
        return _signup(event, ios_waitlist=False)
    if route_key == "POST /ios-waitlist":
        return _signup(event, ios_waitlist=True)
    if route_key == "POST /auth/start":
        try:
            payload = json.loads(event.get("body") or "{}")
        except (TypeError, json.JSONDecodeError):
            payload = {}
        status, body = auth_start(payload)
        return _response(status, body)
    if route_key == "POST /auth/verify":
        try:
            payload = json.loads(event.get("body") or "{}")
        except (TypeError, json.JSONDecodeError):
            payload = {}
        status, body = auth_verify(payload)
        return _response(status, body)
    if route_key == "POST /auth/refresh":
        try:
            payload = json.loads(event.get("body") or "{}")
        except (TypeError, json.JSONDecodeError):
            payload = {}
        status, body = auth_refresh(payload)
        return _response(status, body)
    return _response(404, {"ok": False, "error": "not_found"})
