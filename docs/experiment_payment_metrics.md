# Payment Experiment Metrics — Canonical Definitions

Standard metric set, SQL definitions, and significance testing rules for
payment experiments. Use this as the reference when configuring experiment
metrics in the experimentation platform or building ad-hoc analysis notebooks.

**Assignment source:** `production.experimentation_product.assignment`
**Payment source:** `production.payments.fact_payment_attempt`
**Visitor source:** `production.payments.payment_initiation_events`

---

## Pre-requisites: Assignment & Filtering CTEs

Every experiment analysis starts with these CTEs. Replace `{EXPERIMENT_HASH}`,
`{START_DATE}`, and optionally `{PLATFORM}`.

```sql
WITH filtered_customers AS (
    SELECT visitor_id
    FROM production.dwh.dim_customer c
    JOIN production.dwh.fact_customer_to_visitor ctv USING (customer_id_anon)
    WHERE c.is_filtered_ticket_reseller_partner_or_internal = 1
),

assignment AS (
    SELECT
        experiment_hash,
        variant AS group_name,
        visitor_id,
        timestamp AS assigned_at
    FROM production.experimentation_product.assignment
    LEFT ANTI JOIN filtered_customers fc USING (visitor_id)
    INNER JOIN production.experimentation_product.fact_non_bot_visitors nbv USING (visitor_id)
    WHERE experiment_hash = '{EXPERIMENT_HASH}'
      AND date >= '{START_DATE}'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY visitor_id, experiment_hash
        ORDER BY timestamp
    ) = 1
),

base_attempts AS (
    SELECT
        a.group_name,
        a.visitor_id,
        p.shopping_cart_id,
        p.bin_issuer_country_code AS country,
        p.payment_method,
        p.payment_processor,
        p.customer_attempt_rank,
        p.system_attempt_rank,
        p.payment_initiator_type,
        p.payment_flow,
        p.is_customer_attempt_successful,
        p.is_shopping_cart_successful,
        p.is_payment_attempt_successful,
        p.fraud_pre_auth_result,
        p.challenge_issued,
        p.is_three_ds_passed,
        p.three_ds_status,
        p.sent_to_issuer,
        p.error_code,
        p.error_type,
        p.payment_attempt_timestamp,
        p.amount_eur
    FROM assignment a
    JOIN production.payments.fact_payment_attempt p
      ON a.visitor_id = p.visitor_id
     AND p.payment_attempt_timestamp >= '{START_DATE}'
     AND p.payment_attempt_timestamp > a.assigned_at - INTERVAL 60 SECONDS
    WHERE p.payment_initiator_type = 'CIT'
      AND p.system_attempt_rank = 1
)
```

---

## Metric Tiers

### Tier 1: Primary Metrics (decision metrics)

These are the metrics used to make ship/no-ship decisions.

#### M1: Payment Page Conversion Rate

- **Formula:** `visitors_booked / visitors_on_payment_page`
- **Grain:** Visitor
- **Source:** `payment_initiation_events` joined to assignment
- **Numerator:** Distinct visitors with `is_successful_booker = 1`
- **Denominator:** Distinct visitors who appear in `payment_initiation_events`

```sql
SELECT
    group_name,
    COUNT(DISTINCT visitor_id) AS visitors,
    COUNT(DISTINCT CASE WHEN is_successful_booker = 1 THEN visitor_id END) AS bookers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN is_successful_booker = 1 THEN visitor_id END)
        / COUNT(DISTINCT visitor_id), 4) AS conversion_rate_pct
FROM (
    SELECT
        a.group_name,
        a.visitor_id,
        MAX(pie.is_successful_booker) AS is_successful_booker
    FROM assignment a
    JOIN production.payments.payment_initiation_events pie
      ON a.visitor_id = pie.visitor_id
     AND pie.event_timestamp >= '{START_DATE}'
     AND pie.event_timestamp > a.assigned_at - INTERVAL 60 SECONDS
    GROUP BY 1, 2
)
GROUP BY 1
```

#### M2: Payment Success Rate (Visitor-Level)

- **Formula:** `visitors_booked / visitors_initiated`
- **Grain:** Visitor
- **Numerator:** Distinct visitors with at least one successful cart
- **Denominator:** Distinct visitors with at least one initiated payment

```sql
SELECT
    group_name,
    COUNT(DISTINCT visitor_id) AS visitors_initiated,
    COUNT(DISTINCT CASE WHEN has_success = 1 THEN visitor_id END) AS visitors_booked,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN has_success = 1 THEN visitor_id END)
        / COUNT(DISTINCT visitor_id), 4) AS payment_sr_pct
FROM (
    SELECT
        group_name,
        visitor_id,
        MAX(is_shopping_cart_successful) AS has_success
    FROM base_attempts
    WHERE customer_attempt_rank = 1
    GROUP BY 1, 2
)
GROUP BY 1
```

### Tier 2: Secondary Metrics

#### M3: Payment Initiation Rate

- **Formula:** `visitors_initiated / visitors_on_payment_page`
- **Grain:** Visitor
- **Definition:** See experiment_analysis_rules.md for event-based initiation
  (MobileAppUITap, UISubmit, MobileAppPaymentSubmit).

#### M4: Cart Payment Success Rate

- **Formula:** `successful_carts / initiated_carts`
- **Grain:** Shopping cart

```sql
SELECT
    group_name,
    COUNT(DISTINCT shopping_cart_id) AS carts,
    COUNT(DISTINCT CASE WHEN cart_success = 1 THEN shopping_cart_id END) AS successful_carts,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN cart_success = 1 THEN shopping_cart_id END)
        / COUNT(DISTINCT shopping_cart_id), 4) AS cart_sr_pct
FROM (
    SELECT
        group_name,
        shopping_cart_id,
        MAX(is_shopping_cart_successful) AS cart_success
    FROM base_attempts
    WHERE customer_attempt_rank = 1
    GROUP BY 1, 2
)
GROUP BY 1
```

### Tier 3: Diagnostic Metrics

#### M5: First Customer Attempt SR

- **Formula:** `successful_first_attempts / total_first_attempts`
- **Grain:** First CIT attempt per cart

```sql
SELECT
    group_name,
    COUNT(*) AS first_attempts,
    SUM(is_customer_attempt_successful) AS successful,
    ROUND(100.0 * SUM(is_customer_attempt_successful) / COUNT(*), 4) AS first_attempt_sr_pct
FROM base_attempts
WHERE customer_attempt_rank = 1
GROUP BY 1
```

#### M6: First-Per-Visitor SR

Most robust attempt-level metric for A/B tests. One data point per visitor.

```sql
SELECT
    group_name,
    COUNT(*) AS visitors,
    SUM(is_customer_attempt_successful) AS successful,
    ROUND(100.0 * SUM(is_customer_attempt_successful) / COUNT(*), 4) AS first_visitor_sr_pct
FROM (
    SELECT *
    FROM base_attempts
    WHERE customer_attempt_rank = 1
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY visitor_id
        ORDER BY payment_attempt_timestamp
    ) = 1
)
GROUP BY 1
```

#### M7: Waterfall Decomposition

```sql
SELECT
    group_name,
    COUNT(*) AS attempts,
    ROUND(100.0 * SUM(CASE WHEN fraud_pre_auth_result = 'REFUSE' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_block_pct,
    ROUND(100.0 * SUM(CASE WHEN fraud_pre_auth_result = 'THREE_DS' THEN 1 ELSE 0 END) / COUNT(*), 2) AS three_ds_trigger_pct,
    ROUND(100.0 * SUM(sent_to_issuer) / COUNT(*), 2) AS sent_to_issuer_pct,
    ROUND(100.0 * SUM(CASE WHEN sent_to_issuer = 1 AND is_payment_attempt_successful = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(sent_to_issuer), 0), 2) AS auth_rate_pct,
    ROUND(100.0 * SUM(is_customer_attempt_successful) / COUNT(*), 2) AS attempt_sr_pct
FROM base_attempts
WHERE customer_attempt_rank = 1
GROUP BY 1
```

#### M8: 3DS Metrics

```sql
SELECT
    group_name,
    COUNT(*) AS three_ds_attempts,
    ROUND(100.0 * SUM(CASE WHEN challenge_issued THEN 1 ELSE 0 END) / COUNT(*), 2) AS challenge_rate_pct,
    ROUND(100.0 * SUM(is_three_ds_passed) / COUNT(*), 2) AS pass_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN NOT challenge_issued AND is_customer_attempt_successful = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT challenge_issued THEN 1 ELSE 0 END), 0), 2) AS frictionless_sr_pct,
    ROUND(100.0 * SUM(CASE WHEN challenge_issued AND is_customer_attempt_successful = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN challenge_issued THEN 1 ELSE 0 END), 0), 2) AS challenged_sr_pct
FROM base_attempts
WHERE customer_attempt_rank = 1
  AND fraud_pre_auth_result = 'THREE_DS'
GROUP BY 1
```

#### M9: Error Mix

```sql
SELECT
    group_name,
    error_code,
    error_type,
    COUNT(*) AS occurrences,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY group_name), 2) AS share_pct
FROM base_attempts
WHERE customer_attempt_rank = 1
  AND is_payment_attempt_successful = 0
  AND sent_to_issuer = 1
GROUP BY 1, 2, 3
ORDER BY group_name, occurrences DESC
```

#### M10: Multi-Attempt Rate

```sql
SELECT
    group_name,
    COUNT(DISTINCT shopping_cart_id) AS total_carts,
    COUNT(DISTINCT CASE WHEN max_rank > 1 THEN shopping_cart_id END) AS multi_attempt_carts,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN max_rank > 1 THEN shopping_cart_id END)
        / COUNT(DISTINCT shopping_cart_id), 2) AS multi_attempt_pct
FROM (
    SELECT
        group_name,
        shopping_cart_id,
        MAX(customer_attempt_rank) AS max_rank
    FROM base_attempts
    GROUP BY 1, 2
)
GROUP BY 1
```

---

## Statistical Testing

### Two-proportion z-test

```python
import math
from scipy.stats import norm

def z_test(s1, n1, s2, n2):
    """Compare two proportions. s=successes, n=total.
    Returns dict with delta, z-stat, CI, MDE, and significance flag."""
    if n1 == 0 or n2 == 0:
        return None
    p1, p2 = s1 / n1, s2 / n2
    delta = p2 - p1
    pool = (s1 + s2) / (n1 + n2)
    if pool in (0, 1):
        return None
    se_p = math.sqrt(pool * (1 - pool) * (1 / n1 + 1 / n2))
    se_u = math.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    z = delta / se_p
    p_value = 2 * (1 - norm.cdf(abs(z)))
    return dict(
        p1=p1, p2=p2,
        delta=delta,
        delta_pp=delta * 100,
        z=z,
        p_value=p_value,
        ci_lo=delta - 1.96 * se_u,
        ci_hi=delta + 1.96 * se_u,
        mde=(1.96 + 0.84) * se_p,
        is_significant=p_value < 0.05 and (
            (delta > 0 and delta - 1.96 * se_u > 0) or
            (delta < 0 and delta + 1.96 * se_u < 0)
        ),
    )
```

### Significance criteria

All three must hold for "truly significant":

1. **|z| > 1.96** (p < 0.05 two-sided)
2. **95% CI excludes zero** (`ci_lo > 0` for positive, `ci_hi < 0` for negative)
3. **Adequate power:** `|delta| >= MDE` at 80% power

Do NOT apply a practical significance threshold (e.g., delta > 1pp). It masks
real issues in large markets.

### SRM (Sample Ratio Mismatch) check

Run before any metric analysis. If SRM is detected, the experiment is
compromised and results are unreliable.

```python
from scipy.stats import chi2

def srm_check(n_control, n_test, expected_ratio=0.5):
    """Check for Sample Ratio Mismatch."""
    n_total = n_control + n_test
    expected_c = n_total * expected_ratio
    expected_t = n_total * (1 - expected_ratio)
    chi2_stat = (
        (n_control - expected_c) ** 2 / expected_c
        + (n_test - expected_t) ** 2 / expected_t
    )
    p_value = 1 - chi2.cdf(chi2_stat, df=1)
    return dict(
        chi2=round(chi2_stat, 4),
        p_value=round(p_value, 6),
        is_srm=p_value < 0.01,
    )
```

### Sample size / power analysis

```python
def required_sample_size_per_group(p_baseline, mde_relative, alpha=0.05, power=0.8):
    """Minimum sample size per group for a two-proportion test.
    mde_relative is the relative change (e.g. 0.01 for 1% relative lift)."""
    z_alpha = norm.ppf(1 - alpha / 2)
    z_beta = norm.ppf(power)
    p_alt = p_baseline * (1 + mde_relative)
    p_bar = (p_baseline + p_alt) / 2
    n = (
        (z_alpha * math.sqrt(2 * p_bar * (1 - p_bar))
         + z_beta * math.sqrt(p_baseline * (1 - p_baseline) + p_alt * (1 - p_alt)))
        / (p_alt - p_baseline)
    ) ** 2
    return math.ceil(n)
```

---

## Country-Level Drill-Down

For every primary metric, drill down by `bin_issuer_country_code`:

```sql
SELECT
    group_name,
    country,
    COUNT(*) AS attempts,
    SUM(is_customer_attempt_successful) AS successful,
    ROUND(100.0 * SUM(is_customer_attempt_successful) / COUNT(*), 4) AS sr_pct
FROM (
    SELECT * FROM base_attempts WHERE customer_attempt_rank = 1
)
GROUP BY 1, 2
HAVING COUNT(*) >= 100
ORDER BY group_name, attempts DESC
```

Then apply z-test per country. Flag countries that are:
- Statistically significant (CI excludes zero)
- Have at least 100 observations per arm

Sort by delta to find worst/best-performing markets.

### Visitor concentration check

Before concluding a market has a real problem, verify the effect is not
driven by a handful of heavy-retry visitors:

```sql
SELECT
    group_name, visitor_id,
    COUNT(*) AS attempts,
    SUM(is_customer_attempt_successful) AS successful
FROM base_attempts
WHERE country = '{COUNTRY}'
GROUP BY 1, 2
ORDER BY attempts DESC
LIMIT 30
```

If top 2-3 visitors dominate failures, it is an artifact, not systemic.

---

## Analysis Workflow

1. **SRM check** — verify control/test ratio before any metric analysis
2. **Top-line metrics** — compute all tier-1 metrics (conversion, payment SR)
3. **Diagnostic waterfall** — fraud/3DS/sent-to-issuer/auth decomposition
4. **Country drill-down** — identify underperforming markets
5. **Root cause per market** — provider split, fraud context, 3DS challenge rates
6. **Visitor concentration** — verify findings are not driven by outlier visitors
7. **Daily trends** — check for ramp-up artifacts or weekend/weekday mix issues
8. **Power analysis** — verify adequate sample size for observed effect

---

## Output Format

Present results as markdown tables. Top-line example:

```
Metric                  ctrl        test       delta pp    z       sig
─────────────────────   ─────────   ─────────  ────────   ─────   ───
Conversion Rate          85.12%      85.34%    +0.22       +1.1   NS
Payment SR (visitor)     92.45%      92.61%    +0.16       +0.8   NS
First Attempt SR         78.50%      78.20%    -0.30       -1.1   NS
Cart SR                  88.30%      88.15%    -0.15       -0.6   NS
```

Country-level: include country, ctrl_n, test_n, ctrl SR, test SR, delta pp,
z, significance flag.

---

## Known Issues & Gotchas

| Issue | Impact | Mitigation |
|-------|--------|------------|
| Android `save_card_consent` hardcoded to true | Inflates control adoption; contaminates experiment | Use iOS only for save-card metrics |
| Payment method mix shift (Simpson's Paradox) | Stored cards shift volume from high-SR wallets to lower-SR cards | Analyse per payment method, not just overall |
| MIT transactions inflate NULL fraud rates | Misleading fraud block rate | Always filter `payment_initiator_type = 'CIT'` |
| Multi-cart visitors | Appear as duplication but are real repeat purchases | Expect ~1.9 customer attempts per visitor |
| `group_name` case mismatch | Statsig returns mixed case | Always `LOWER(group_name)` |
| Weekend/weekday mix | Short experiments may be biased | Wait for >= 1 full week |
| Forter pay_now vs pay_later split | Over-blocking is pay_now-specific | Analyse by `payment_terms` before concluding |
