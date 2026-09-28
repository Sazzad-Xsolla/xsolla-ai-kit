# Authentication and environment

This is the **only** file that names the host, the header and the credential.
Everywhere else says "an authenticated Quest Platform request". Keep it that
way, so a change to authentication touches one file.

## Host

Stage services used by this skill:

| Service | Job | Stage host |
|---|---|---|
| qp-server | quest CRUD | `https://qp-server.nl-k8s-stage.srv.local` |
| qp-events-collector | event ingestion | `https://qp-events-collector.nl-k8s-stage.srv.local` |
| qp-data | execution read-back | `https://qp-data.nl-k8s-stage.srv.local` |

The hosts resolve on the corporate network and use Xsolla's private CA. Never
disable TLS verification. Each service publishes `/openapi.json` without a
credential on stage; discovery does not prove CRUD access.

## Credential

```bash
export XSOLLA_MERCHANT_ID=<your merchant ID>
export XSOLLA_PROJECT_ID=<your project ID>
export XSOLLA_PROJECT_API_KEY=<your project API key>
```

Every request sends
`Authorization: Basic base64(XSOLLA_MERCHANT_ID:XSOLLA_PROJECT_API_KEY)`, the
same pattern other skills in this kit use.

Use the key on the server or agent side only. Never print, log or commit the
key or encoded header. Check variable names without printing values, and read
`.env` as text rather than sourcing it. Take ids and the key from one source;
if the environment and `.env` disagree, ask which source to use.

`XSOLLA_MERCHANT_ID` is always the `{merchant_id}` in the route. Never take it
from a quest body, a response or a guess. `ID 0` is valid. Do not search other
files, variables or shell history for credentials.

## Routes

Basic works only on this family:

| Operation | Route |
|---|---|
| Project read | `GET /api/v2/merchants/{merchant_id}/projects/{project_id}` |
| Onboard | `POST /api/v2/merchants/{merchant_id}/projects/{project_id}/onboard` |
| List quests | `GET /api/v2/merchants/{merchant_id}/projects/{project_id}/quests` |
| Create quest | `POST /api/v2/merchants/{merchant_id}/projects/{project_id}/quests` |
| Read, replace or delete | `GET`, `PUT`, `DELETE /api/v2/merchants/{merchant_id}/projects/{project_id}/quests/{id}` |

The old `/api/v2/projects/{project_id}/...` family is not used. A plain-text
`Cannot GET <path>` or `Cannot POST <path>` is a router miss, not an auth or
project answer. Stop, fetch the live OpenAPI and report the route status.

## Checking access

Before a write, read the project route and show `project_id`, `name`, `status`
and the merchant id used in the path. Then read the project quest list with a
small limit. These reads prove the key can see this project; they do not prove
write capability. Treat each new operation the same way when it first returns
an error:

- **404 with a plain-text body** such as `Cannot GET /api/v2/quests` or
  `Cannot POST /api/v2/quests`: the route is not published on this host yet.
  Stop. Tell the developer that the route is not published. Do not retry, and
  do not try another host or credential.
- **401 with a JSON body**: the host received the credential and did not
  accept it for this project. Ask the developer to check the merchant id and
  project key.
- **404 with a JSON body**: not found, no access, or the project is not
  onboarded to Quest Platform. These cases look identical by design. Never say
  the quest or the project does not exist.

## Onboarding

If the project GET returns `{"error":"Project not found"}`, the body does not
distinguish an unknown project, another merchant or an un-onboarded project.
Offer onboarding only after the developer says the project belongs to the
merchant in `XSOLLA_MERCHANT_ID`.

The write body is `{"merchant_name":"<merchant name>","project_name":"<project name>"}`.
Ask for both names, show the request without credentials, and wait for an
explicit yes. After a timeout or 5xx, read the project before offering it
again.

## Scope

The route supplies the merchant and project scope. The server stamps
`publisher_id` and `project_id` from the path on create. Do not invent or
override them. On a full `PUT`, send the values returned by a fresh single
quest read. The response has no account or workspace id; do not guess one.

## Service preflight

Use one read before the first call to each service, only for services the task
will call. The collector has no Basic event route on current stage; fetch its
OpenAPI when a task may send an event and report that block. qp-data answers
without a credential and must be queried only with the developer's own
confirmed scope.

## Service key: staff only

`X-REQUEST-APIKEY` is an internal lane bound to another account. It is not a
fallback for a publisher key. Use it only when the developer explicitly
chooses that lane, and never mix quests or events between lanes.
