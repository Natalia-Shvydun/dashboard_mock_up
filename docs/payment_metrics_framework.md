# Payment Metrics Framework

Canonical reference for all payment analytics at GetYourGuide.
Covers the funnel from landing on the payment page to completing payment.

**Primary data source:** `production.payments.fact_payment_attempt`

---

## North Star Metrics

| # | Metric | Formula | Grain | Source |
|---|--------|---------|-------|--------|
| NS-1 | **Payment Page Conversion Rate** | `visitors_booked / visitors_on_payment_page` | Visitor | `payment_initiation_events` + session data |
| NS-2 | **Payment Cost as % of GMV** | `total_fee_eur / settled_gmv_eur` | Cart (aggregated) | `fact_payment_attempt` (fee columns) |

**Guardrail metrics:**

| Guardrail | Metric | Definition |
|-----------|--------|------------|
| Experience quality | Multi-Attempt Cart Rate | % of carts requiring more than one customer attempt |
| Experience quality | 3DS Challenge Rate | % of 3DS-triggered attempts where a challenge was issued |
| Health | Core Corridor SR Floor | % of top-20 markets with first-attempt SR below 90% |
| Resilience | Routing Gap Rate | % of initiated attempts with `payment_processor IS NULL` |
| Resilience | Processor Concentration (HHI) | Herfindahl-Hirschman Index across processors |

---

## Metric Robustness Ordering

When analysing payment performance, evaluate metrics from **most robust** (least
sensitive to retry noise) to **most granular** (most diagnostic detail). This
ordering determines how you read results: start at L0 and drill down only when
you see a signal.

| Level | Metric | Grain | SQL key / dedup | Purpose |
|-------|--------|-------|-----------------|---------|
| L0 | Payment Page Conversion Rate | Visitor | One row per visitor who reached payment page | North star; full funnel from page load to booking |
| L1 | Visitor SR | Visitor | `COUNT(DISTINCT IF(has_success, visitor_id)) / COUNT(DISTINCT visitor_id)` | Business outcome; masks retries |
| L2 | Cart SR | Shopping cart | `MAX(is_shopping_cart_successful)` grouped by `shopping_cart_id` | Cart-level outcome; one cart = one purchase intent |
| L3 | First Customer Attempt SR | First attempt per cart | `customer_attempt_rank = 1` | Isolates first-try quality; best for routing/fraud diagnostics |
| L4 | All Customer Attempt SR | All customer attempts | No rank filter, count all CIT rows | Includes retry performance |
| L5 | System Attempt SR | System-level hits | All rows including system retries | Routing/fallback diagnostics |

### Divergence patterns

| Pattern | Interpretation |
|---------|---------------|
| L3 negative, L1 flat | Retries compensating; there IS a first-attempt problem |
| L5 negative, L3 flat | Internal fallback/retry issue, not primary routing |
| All levels negative | Real regression |
| L4 negative, driven by one country | Drill into that market |

---

## Area 1 -- Payment Initiation

Covers: user lands on the payment page → user initiates at least one payment attempt.

### Metrics available today

| Metric | Formula | Source | Dedup |
|--------|---------|--------|-------|
| **Payment Initiation Rate** | `initiated_carts / payment_page_view_carts` | `fact_payment_attempt`: count distinct `shopping_cart_id` where `payment_initiated = 1` over total distinct `shopping_cart_id` | Group by `shopping_cart_id` |
| **Payment Page Drop-off Rate** | `1 - Payment Initiation Rate` | Derived | -- |

### Metrics requiring future data model (`fact_payment_page_visit`)

| Metric | Formula | Required data |
|--------|---------|---------------|
| Payment Method Exploration Rate | % of visits interacting with >1 payment method | Click-stream events |
| Payment Methods Visibility Rate | % of visits where all available methods are seen | Page render events |
| Currency Switch Rate | % of visits with ≥1 currency switch | Event data |
| Payment Terms Switch Rate | % of visits with ≥1 pay-now/pay-later toggle | Event data |
| Time to Payment Initiation | Median time from page load to first initiation | Page load + initiation timestamps |

---

## Area 2 -- Payment Success

Covers: user initiates a payment → payment is successfully settled (or fails after retries).

### 2.1 Cart / Transaction Level (Business View)

| Metric | Formula | SQL pattern |
|--------|---------|-------------|
| **Cart Payment SR** | `successful_carts / initiated_carts` | `COUNT(DISTINCT CASE WHEN is_shopping_cart_successful = 1 THEN shopping_cart_id END) / COUNT(DISTINCT CASE WHEN payment_initiated = 1 THEN shopping_cart_id END)` |
| **Cart Outcome Distribution** | Share of carts by final state | Group by outcome bucket: paid / abandoned / fraud-blocked / 3DS-failed / issuer-declined / technical-error |
| **Multi-Attempt Cart Rate** | `carts_with_multiple_attempts / total_carts` | `COUNT(DISTINCT CASE WHEN max_customer_attempt_rank > 1 THEN shopping_cart_id END) / COUNT(DISTINCT shopping_cart_id)` |
| **Retry Recovery Rate** | `eventually_succeeded / failed_first_attempt` | Among carts where `customer_attempt_rank = 1` failed, % where `is_shopping_cart_successful = 1` |

### 2.2 Attempt-Level Waterfall

Every payment attempt passes through a sequential pipeline. Decompose the
attempt SR into these stages to identify where failures occur.

```
Attempt initiated
  │
  ├─[1] Fraud Pre-Auth (Forter) ──────── fraud_pre_auth_result
  │      ACCEPT  → proceed without 3DS
  │      THREE_DS → go to 3DS
  │      THREE_DS_EXEMPTION → skip 3DS, proceed
  │      REFUSE  → blocked, attempt ends
  │      NULL    → no Forter eval (MIT, some APMs)
  │
  ├─[2] 3DS Authentication ──────────── challenge_issued, is_three_ds_passed
  │      Frictionless pass (challenge_issued = false, three_ds_status = 'frictionless')
  │      Challenge issued (challenge_issued = true)
  │        ├─ Challenge passed (three_ds_status = 'success')
  │        └─ Challenge failed/abandoned (three_ds_status = 'failed')
  │
  ├─[3] Sent to Issuer ─────────────── sent_to_issuer
  │      1 = submitted to issuer
  │      0 = blocked before issuer (REFUSE + 3DS fail + routing gap)
  │
  └─[4] Issuer Authorization ───────── is_payment_attempt_successful
         Authorized → success
         Declined → error_code, error_type
           ├─ Issuer decline (issuer_declined = 1)
           ├─ Gateway rejected (gateway_rejected = 1)
           └─ Application error (application_error = 1)
```

### 2.3 Waterfall Metrics

All metrics below use `customer_attempt_rank = 1` AND `payment_initiator_type = 'CIT'`
unless stated otherwise.

#### Stage 1: Fraud Pre-Auth

| Metric | Formula | SQL |
|--------|---------|-----|
| Fraud Block Rate | REFUSE / total | `SUM(CASE WHEN fraud_pre_auth_result = 'REFUSE' THEN 1 ELSE 0 END) / COUNT(*)` |
| Fraud Accept Rate | ACCEPT / total | `SUM(CASE WHEN fraud_pre_auth_result = 'ACCEPT' THEN 1 ELSE 0 END) / COUNT(*)` |
| 3DS Trigger Rate | THREE_DS / total | `SUM(CASE WHEN fraud_pre_auth_result = 'THREE_DS' THEN 1 ELSE 0 END) / COUNT(*)` |
| 3DS Exemption Rate | THREE_DS_EXEMPTION / total | `SUM(CASE WHEN fraud_pre_auth_result = 'THREE_DS_EXEMPTION' THEN 1 ELSE 0 END) / COUNT(*)` |
| Null Fraud Rate | NULL / total | `SUM(CASE WHEN fraud_pre_auth_result IS NULL THEN 1 ELSE 0 END) / COUNT(*)` |

#### Stage 2: 3DS Authentication

Denominator: attempts where `fraud_pre_auth_result = 'THREE_DS'`.

| Metric | Formula | SQL (within 3DS-triggered) |
|--------|---------|---------------------------|
| 3DS Challenge Rate | challenged / 3DS-triggered | `SUM(CASE WHEN challenge_issued = true THEN 1 ELSE 0 END) / COUNT(*)` |
| 3DS Frictionless Rate | frictionless / 3DS-triggered | `SUM(CASE WHEN challenge_issued = false THEN 1 ELSE 0 END) / COUNT(*)` |
| 3DS Pass Rate | passed / 3DS-triggered | `SUM(is_three_ds_passed) / COUNT(*)` |
| SR -- 3DS Challenged | successful / challenged | `SUM(CASE WHEN challenge_issued AND is_customer_attempt_successful THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN challenge_issued THEN 1 ELSE 0 END), 0)` |
| SR -- 3DS Frictionless | successful / frictionless | `SUM(CASE WHEN NOT challenge_issued AND is_customer_attempt_successful THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN NOT challenge_issued THEN 1 ELSE 0 END), 0)` |

#### Stage 3: Sent to Issuer

| Metric | Formula | SQL |
|--------|---------|-----|
| Sent-to-Issuer Rate | sent / total | `SUM(sent_to_issuer) / COUNT(*)` |

Attempts NOT sent = fraud block + 3DS failure + routing gap (`payment_processor IS NULL`).

#### Stage 4: Issuer Authorization

Denominator: attempts where `sent_to_issuer = 1`.

| Metric | Formula | SQL (within sent-to-issuer) |
|--------|---------|---------------------------|
| Authorization Rate | authorized / sent | `SUM(is_payment_attempt_successful) / COUNT(*)` |
| Issuer Decline Rate | issuer_declined / sent | `SUM(issuer_declined) / COUNT(*)` |
| Gateway Reject Rate | gateway_rejected / sent | `SUM(gateway_rejected) / COUNT(*)` |
| Application Error Rate | application_error / sent | `SUM(application_error) / COUNT(*)` |

#### Error Mix

Top error codes by frequency (within declined attempts):

```sql
SELECT
  error_code,
  error_type,
  COUNT(*) AS occurrences,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM production.payments.fact_payment_attempt
WHERE customer_attempt_rank = 1
  AND payment_initiator_type = 'CIT'
  AND is_payment_attempt_successful = 0
  AND sent_to_issuer = 1
  AND payment_attempt_timestamp >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
GROUP BY error_code, error_type
ORDER BY occurrences DESC
```

### 2.4 RNPL-Specific Metrics

RNPL (Reserve Now Pay Later) has three distinct payment flows. Each must be
measured separately because they have different characteristics and dedup rules.

| Flow | `payment_flow` | `payment_initiator_type` | When | Dedup rule |
|------|---------------|-------------------------|------|------------|
| Authorization | `rnpl_auth_0` | CIT | Checkout -- $0 auth hold | `customer_attempt_rank = 1` |
| Auto-capture | `rnpl_auto_capture` | MIT | T-72h before travel | No rank filter -- need all retries |
| Pay early | `rnpl_pay_early` | CIT | Customer elects to pay early | `customer_attempt_rank = 1` |

| Metric | Formula | Notes |
|--------|---------|-------|
| RNPL Auth SR | successful auth / total auth attempts | CIT only; $0 hold |
| RNPL MIT SR | successful captures / total capture attempts | MIT; no Forter eval (NULL fraud is expected) |
| RNPL Pay-Early SR | successful / total pay-early attempts | CIT; same as pay_now SR |
| RNPL Cart SR | carts where final outcome = paid / total RNPL carts | Combines auth + MIT lifecycle per cart |
| RNPL Cancellation Rate | cancelled RNPL bookings / total RNPL bookings | Join to `fact_booking` with `status_id IN (1, 2)` |

**Critical rule:** Always filter to `payment_initiator_type = 'CIT'` when computing
fraud or 3DS metrics. MIT transactions have no Forter evaluation by design and will
inflate NULL fraud rates.

### 2.5 Payment Costs

| Metric | Formula | Source fields |
|--------|---------|--------------|
| Total Fee % of GMV | `SUM(total_fee_amount_eur) / SUM(settled_gmv_eur)` | `total_fee_amount_eur_new`, settled GMV |
| Scheme Fee % of GMV | `SUM(scheme_fee_amount_eur) / SUM(settled_gmv_eur)` | `scheme_fee_amount_eur_new` |
| Interchange Fee % of GMV | `SUM(interchange_fee_amount_eur) / SUM(settled_gmv_eur)` | `interchange_fee_amount_eur_new` |
| Acquirer Fee % of GMV | `SUM(acquirer_fee_amount_eur) / SUM(settled_gmv_eur)` | `acquirer_fee_amount_eur_new` |

---

## Deduplication Rules

| Metric type | Filter | Dedup | Notes |
|-------------|--------|-------|-------|
| Cart-level SR / conversion | `customer_attempt_rank = 1`, `CIT` | Group by `shopping_cart_id`, use `MAX(is_shopping_cart_successful)` | One row per cart |
| First customer attempt SR | `customer_attempt_rank = 1` | Count rows directly | Multiple carts per visitor possible |
| First-per-visitor SR | `customer_attempt_rank = 1` | `QUALIFY ROW_NUMBER() OVER (PARTITION BY visitor_id ORDER BY payment_attempt_timestamp) = 1` | Most robust for A/B tests |
| All customer attempts SR | `payment_initiator_type = 'CIT'` | Count all CIT rows | Includes retries |
| System attempt SR | No rank filter | All rows | Routing/fallback diagnostics |
| MIT analysis (RNPL) | `payment_flow = 'rnpl_auto_capture'` | No rank filter | Need full retry chain for lifecycle |
| Fraud / 3DS analysis | `payment_initiator_type = 'CIT'` | Per metric level above | MIT has no Forter eval |

---

## Dimensions

All metrics should be consistently segmentable by:

| Dimension | Column | Notes |
|-----------|--------|-------|
| Country / Region | `bin_issuer_country_code` (cards), `customer_country_code` (APMs, RNPL) | Card issuer country is the primary geo dimension for routing analysis |
| Platform | `platform` | iOS, Android, Web |
| Payment Method | `payment_method` | `payment_card`, `apple_pay`, `google_pay`, `paypal`, `klarna`, APMs |
| Payment Method Variant | `payment_method_variant` | Card network: VISA, MASTERCARD, AMEX, etc. |
| Payment Flow | `payment_flow` | `pay_now`, `rnpl_auth_0`, `rnpl_pay_early`, `rnpl_auto_capture` |
| Payment Terms | `payment_terms` | `pay_now`, `pay_later` |
| Amount Bucket | Derived from `amount_eur` | Custom buckets (e.g. <50, 50-200, 200-500, 500+) |
| Processor | `payment_processor` | `ADYEN`, `CHECKOUT`, `JPMC`, NULL |
| New / Repeat | Derived from customer data | Requires join to customer tables |
| Routing Rule | Derived from country + currency + network | See routing rule classification |
| Card Funding Type | `bin_account_funding_type` | CREDIT, DEBIT, PREPAID |

---

## Column Migration: Old Explore → New Framework

For teams migrating from the old `production.analytics.fact_payment` explore:

| Old column (`fact_payment`) | New column (`fact_payment_attempt`) |
|---------------------------|-------------------------------------|
| `author_boolean` | `is_payment_attempt_successful` |
| `fraud_check_success_outcome` | `fraud_pre_auth_result` |
| `3ds_outcome` | `three_ds_status` |
| `booked` | `is_shopping_cart_successful` |
| `cart_booked` | `is_shopping_cart_successful` (same) |
| `payment_initiated` | `payment_initiated` (same name, same semantics) |
| `sent_to_issuer` (dim) | `sent_to_issuer` (int flag) |
| `gmv_eur` | `amount_eur` |
| `scheme_fee_amount_eur_new` | `scheme_fee_amount_eur_new` (same) |
| `interchange_fee_amount_eur_new` | `interchange_fee_amount_eur_new` (same) |
| `acquirer_fee_amount_eur_new` | `acquirer_fee_amount_eur_new` (same) |
| `total_fee_amount_eur_new` | `total_fee_amount_eur_new` (same) |

---

## Target Data Model Architecture

`fact_payment_attempt`, `payment_initiation_events`, and `fact_payment_shopping_cart` are available today.
The following models are the target architecture. Each metric above is tagged
with whether it can be computed from existing tables today or requires
a future model.

| Model | Grain | Status | Purpose |
|-------|-------|--------|---------|
| `fact_payment_attempt` | 1 row per attempt | **Available** | All attempt-level, cart-level, and visitor-level metrics via dedup |
| `payment_initiation_events` | 1 row per initiation event | **Available** | Visitor SR, initiation tracking |
| `fact_payment_shopping_cart` | 1 row per cart | **Available** | Pre-aggregated cart outcomes, waterfall summary, retry/recovery, RNPL lifecycle |
| `fact_payment_page_visit` | 1 row per page visit | Future | Initiation area metrics (exploration, drop-off, time-to-initiate) |
| `fact_customer_payment_attempt` | 1 row per customer attempt | Future | Customer-visible attempt outcomes |
| `fact_system_payment_attempt` | 1 row per system attempt | Future | Routing/fallback internal diagnostics |
| `fact_processor_payment_attempt` | 1 row per processor hit | Future | Acquirer comparison, observed auth rates |
| `fact_payment` | 1 row per payment_reference | Future | Financial/settlement view, fees |
