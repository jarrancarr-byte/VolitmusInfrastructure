# Voltimus beta API

This increment makes the public VoltimusWeb beta request forms functional without automatically granting a Cognito account.

## Public endpoints

Base URL:

```text
https://api.voltimusmaximus.com
```

Routes:

```text
GET  /health
GET  /mobile-config
POST /beta
POST /ios-waitlist
```

### POST /beta

Matches the payload emitted by VoltimusWeb 0.3.10:

```json
{
  "signupType": "android_beta",
  "platform": "Android",
  "email": "rider@example.com",
  "vehicleModel": "Foholo F15",
  "deviceModel": "Moto Edge 2025",
  "androidVersion": "16",
  "deviceDetectionSource": "manual",
  "batteryVoltage": "60V",
  "region": "Washington, DC",
  "contactConsent": true,
  "firstAdId": "businesscard",
  "latestAdId": "businesscard",
  "anonymousId": "...",
  "attribution": {
    "anonymousId": "...",
    "firstAdId": "businesscard",
    "latestAdId": "businesscard",
    "firstSeenAt": "2026-09-12T14:00:00.000Z",
    "latestSeenAt": "2026-09-12T14:05:00.000Z",
    "firstLandingPath": "/metro?adid=businesscard",
    "latestLandingPath": "/beta"
  }
}
```

Required server-side fields:

- valid `email`
- `contactConsent: true`
- `vehicleModel`
- `deviceModel`

Successful response:

```http
HTTP/1.1 202 Accepted
Content-Type: application/json

{"ok":true,"status":"received"}
```

A new Android applicant receives `status = applied` in DynamoDB. Re-submitting the same email updates current details while preserving first-touch attribution and preserving later workflow states such as `approved`, `invited`, or `active`.

### POST /ios-waitlist

Accepts the corresponding VoltimusWeb iOS waitlist payload. Email and contact consent are required; vehicle and battery fields are optional. A new iOS-only record receives `status = ios_waitlist`.

If an email is already an Android applicant or an approved/invited/active tester, an iOS waitlist submission does not downgrade that status.

## Applicant data

DynamoDB table:

```text
voltimus-beta-beta-applicants
```

Primary key:

```text
email
```

Useful status values:

```text
ios_waitlist
applied
approved
invited
active
declined
```

The table has a `status-createdAt` GSI for administrative review, on-demand billing, point-in-time recovery, server-side encryption, and deletion protection.

## Approval is intentionally manual

The public form does **not** call `AdminCreateUser`.

The desired flow is:

```text
public request
    -> DynamoDB status=applied
    -> human review
    -> approve/invite script
    -> Cognito invitation email
    -> tester completes Cognito login
```

This prevents an Internet form submission from automatically becoming a beta identity.

## Turnstile rollout

The API contains server-side Cloudflare Turnstile verification and stores the secret in AWS Secrets Manager for Lambda use.

For VoltimusWeb 0.3.10, keep:

```hcl
beta_form_require_turnstile = false
```

because the website does not yet submit a Turnstile token. After the website sends one of these fields:

```text
turnstileToken
cf-turnstile-response
turnstile_token
```

set the variable to `true` and re-apply Terraform.

## CORS

Default browser origins are:

```text
https://voltimusmaximus.com
https://www.voltimusmaximus.com
http://localhost:4173
http://127.0.0.1:4173
```

The local origins are intentional for pre-launch end-to-end testing from `npm run dev`.

## Mobile config

`GET /mobile-config` returns Terraform-controlled beta settings. It does not require authentication and is intended for the mobile client's remote version/beta gate.

## Not in this increment

This increment intentionally does not add:

- automatic beta approval
- billing/subscriptions
- ride telemetry upload
- precise-location upload
- generalized authenticated feedback/crash APIs
- custom passwordless `/auth/start` or `/auth/verify` endpoints

The current Cognito Managed Login / authorization-code flow remains the identity source of truth.
