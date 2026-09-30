# Authentication and environment

This skill is production-only. Use the production Quest Platform project and
the production Web3 catalog project supplied by the configured integration.
Never use a staging credential, staging service or staging Publisher Account
catalog as a fallback.

Service locations, credentials and certificate configuration belong to the
host-managed integration. Do not hardcode private hostnames, private CA
details, service keys or environment-specific route claims in this public
skill. Resolve every route from the live production OpenAPI document for the
service being called.

## Services

The integration may expose separate services for quest configuration, event
ingestion, execution read-back and Web3 catalog lookups. Use only the service
that owns the requested operation. Fetch its production OpenAPI document before
the first call. A missing route is not replaced with a guessed path or a
staging route.

## Minting service

Use read-only catalog and wallet operations supplied by the production Web3
integration. Never call a claim endpoint directly. Rewards are issued only by
an activated quest.

For a named item, resolve the human-readable item in the production Publisher
Account catalog, then validate the exact `(catalog_project, sku)` pair in the
production minting catalog. Preserve the catalog project returned with the
item in the `web3_item` body. A zero or ambiguous result stops the flow.

## Credential

Use the production credential supplied by the configured integration. It must
be scoped to the selected merchant and project. Never ask the publisher to
paste a secret into chat, print a header, or use a staging secret.

The default local configuration uses these production-only names. A host
integration may provide the same values through its managed secret source:

| Value | Use |
|---|---|
| `XSOLLA_PROD_MERCHANT_ID` | merchant scope for the project |
| `XSOLLA_PROD_PROJECT_ID` | Quest Platform project scope |
| `XSOLLA_PROD_PROJECT_API_KEY` | authenticated project access |

Never print, log or commit credentials or encoded headers. Send only the
authentication method accepted by the live production contract. Do not mix
credentials from different environments or send multiple auth schemes in one
request.

Read local configuration only as text, taking the three production credential
names from one source. The catalog project is not a credential and must come
from the resolved item, never from the Quest Platform project by default. The
process environment may override a complete local `.env`; do
not mix partial sources. Never source, execute, echo or expose the file. Ignore
stage-named variables. If the complete production source is unavailable,
report that the production project is not connected and stop. Do not ask the
publisher to paste secrets.

## The merchant id in the path

When the live contract uses merchant and project path parameters, both must
come from the same resolved production credential source. Never take them from
the quest body, a read-back row, an earlier answer or a guess. A developer who
names another merchant or project needs the matching production credential.

The server may stamp publisher and project fields from the route. Read them
back after creation and stop if they do not match the resolved scope.

## Project-scoped routes

Use the merchant/project-scoped Quest Platform route family returned by the
live production OpenAPI. The usual operations are:

| Operation | Use |
|---|---|
| project GET | verify scope and onboarding |
| project quest list GET | find an existing quest by paging |
| quest POST | create an inactive draft |
| quest GET/PUT/DELETE | read, replace or soft-delete one quest |

Do not substitute an account-scoped, publisher-scoped or unscoped route from a
different authentication lane. A route that is absent from the live contract
is not called.

## When a route is missing

A 404 router miss means the method and path are not deployed at that location.
It is not proof of a bad credential or missing project:

1. Stop and do not retry a guessed route.
2. Fetch the live OpenAPI document for the same service.
3. If it contains the same operation under another route, show the developer
   the proposed route and ask before calling it. For a write, show the request
   again.
4. If the operation is absent, report that it is unavailable and stop.

## Reading a 401 or 404

Report the service's response body verbatim when it explains the blocker, but
do not expose credential material. Keep these distinctions:

- authentication required or invalid credentials means the selected
  production credential was not accepted;
- a project-not-found response is not enough to distinguish an unknown,
  un-onboarded or differently scoped project;
- a plain router-miss response means the route is wrong or unavailable;
- a missing quest response means it is not found or not visible with this
  credential.

Do not switch to another credential, environment or route after a failure.

## Onboarding

If the live production contract documents onboarding, treat it as a separate
write. Offer it only after the developer confirms that the selected project
belongs to the selected merchant and provides any required non-secret names.
Show the request without credentials and wait for explicit confirmation.

After a timeout or server error, read the project before offering onboarding
again. Never use onboarding as a probe and never infer that a 404 requires it.

## Service preflight

Run one read-only preflight per service, only when the task needs that service:

- Quest configuration: read the selected project and the quest list.
- Event ingestion: fetch the production OpenAPI and confirm the accepted
  event operation and credential lane before sending anything.
- Execution read-back: confirm the production OpenAPI and response scope before
  using the candidate query in `verification.md`.
- Web3 catalog: resolve the named item and validate its catalog project and
  SKU; for a Web3 reward, also check the recipient wallet before activation
  and again before the event.

Bring-up and preflight are GET-only. Ask before any other call.

## Scope

Read the selected production project and show only a short name/status summary
in the normal publisher reply. Before the first write, confirm that it is the
intended project. On create, verify the returned publisher and project fields.
On a full `PUT`, preserve the values from the latest single-quest read.

Never guess a scope or silently switch projects, merchants or credentials.

## Service key: staff only

Internal service or master keys are outside this public skill. Never request,
print or use one as a fallback for a production publisher credential. If the
developer asks for an internal lane, stop and direct them to the Quest
Platform owner.

## Route families this skill does not drive

Do not probe account administration, workspace administration, credential
management, grant administration or data-republish routes. They are outside
quest setup and require a separately documented owner-approved integration.

## Deployment status

A project read does not prove that event submission, execution read-back or
Web3 payout is ready. Confirm each required operation against the live
production contract before using it. Never fall back to a staging lane.
