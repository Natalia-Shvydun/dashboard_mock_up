-- =============================================================================
-- fact_payment_shopping_cart
-- =============================================================================
-- Cart-grain aggregation of production.payments.fact_payment_attempt.
-- One row per shopping_cart_id.
--
-- Covers: cart outcome, first/last CIT attempt snapshots, payment-method arrays,
-- attempt counts, first-attempt waterfall flags, retry/recovery indicators,
-- and the full RNPL lifecycle (auth → capture → pay-early).
--
-- Source:        production.payments.fact_payment_attempt (only)
-- Materialise:   production.payments.fact_payment_shopping_cart
-- Refresh:       Daily incremental, partitioned on cart_date.
--                RNPL carts need a 30-day lookback to pick up MIT captures.
-- =============================================================================

CREATE OR REPLACE TABLE production.payments.fact_payment_shopping_cart AS

-- ─── First CIT attempt per cart ────────────────────────────────────────────────
WITH first_cit AS (
  SELECT *
  FROM production.payments.fact_payment_attempt
  WHERE customer_attempt_rank = 1
    AND payment_initiator_type = 'CIT'
),

-- ─── Last CIT attempt per cart ─────────────────────────────────────────────────
last_cit AS (
  SELECT *
  FROM production.payments.fact_payment_attempt
  WHERE payment_initiator_type = 'CIT'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY shopping_cart_id
    ORDER BY customer_attempt_rank DESC, payment_attempt_timestamp DESC
  ) = 1
),

-- ─── Successful attempt (first one that succeeded) ─────────────────────────────
successful_attempt AS (
  SELECT *
  FROM production.payments.fact_payment_attempt
  WHERE is_payment_attempt_successful = 1
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY shopping_cart_id
    ORDER BY payment_attempt_timestamp ASC
  ) = 1
),

-- ─── Cart-level aggregation ────────────────────────────────────────────────────
cart_agg AS (
  SELECT
    shopping_cart_id,

    -- Attempt counts
    COUNT(*)                                                          AS total_attempt_count,
    SUM(IF(payment_initiator_type = 'CIT', 1, 0))                    AS cit_attempt_count,
    SUM(IF(payment_initiator_type = 'MIT', 1, 0))                    AS mit_attempt_count,
    MAX(CASE WHEN payment_initiator_type = 'CIT'
             THEN customer_attempt_rank END)                          AS customer_attempt_count,
    COUNT(DISTINCT payment_method)                                    AS distinct_payment_methods_count,

    -- Timestamps
    MIN(payment_attempt_timestamp)                                    AS first_attempt_at,
    MAX(payment_attempt_timestamp)                                    AS last_attempt_at,

    -- Outcome
    MAX(is_shopping_cart_successful)                                   AS is_successful,

    -- Payment method arrays (CIT only for methods/variants, ALL for processors)
    COLLECT_SET(
      CASE WHEN payment_initiator_type = 'CIT' THEN payment_method END
    )                                                                 AS payment_methods_attempted,
    COLLECT_SET(
      CASE WHEN payment_initiator_type = 'CIT' THEN payment_method_variant END
    )                                                                 AS payment_method_variants_attempted,
    COLLECT_SET(payment_processor)                                     AS processors_used,

    -- ─── RNPL lifecycle ────────────────────────────────────────────
    -- Auth ($0 hold at checkout)
    BOOL_OR(payment_flow = 'rnpl_auth_0')                             AS rnpl_auth_attempted,
    BOOL_OR(payment_flow = 'rnpl_auth_0'
            AND is_payment_attempt_successful = 1)                    AS rnpl_auth_successful,
    SUM(IF(payment_flow = 'rnpl_auth_0', 1, 0))                      AS rnpl_auth_attempt_count,
    MIN(CASE WHEN payment_flow = 'rnpl_auth_0'
             THEN payment_attempt_timestamp END)                      AS rnpl_auth_first_at,

    -- Auto-capture (MIT, T-72h)
    BOOL_OR(payment_flow = 'rnpl_auto_capture')                       AS rnpl_capture_attempted,
    BOOL_OR(payment_flow = 'rnpl_auto_capture'
            AND is_payment_attempt_successful = 1)                    AS rnpl_capture_successful,
    SUM(IF(payment_flow = 'rnpl_auto_capture', 1, 0))                AS rnpl_capture_attempt_count,
    MIN(CASE WHEN payment_flow = 'rnpl_auto_capture'
             THEN payment_attempt_timestamp END)                      AS rnpl_capture_first_at,
    MAX(CASE WHEN payment_flow = 'rnpl_auto_capture'
             THEN payment_attempt_timestamp END)                      AS rnpl_capture_last_at,

    -- Pay early (CIT, voluntary)
    BOOL_OR(payment_flow = 'rnpl_pay_early')                          AS rnpl_pay_early_attempted,
    BOOL_OR(payment_flow = 'rnpl_pay_early'
            AND is_payment_attempt_successful = 1)                    AS rnpl_pay_early_successful,
    MIN(CASE WHEN payment_flow = 'rnpl_pay_early'
             THEN payment_attempt_timestamp END)                      AS rnpl_pay_early_at

  FROM production.payments.fact_payment_attempt
  GROUP BY shopping_cart_id
)

-- ─── Final SELECT ──────────────────────────────────────────────────────────────
SELECT
  -- ── 1. Primary Key & Identity ───────────────────────────────────
  ca.shopping_cart_id,
  fc.visitor_id,

  -- ── 2. Context (from first CIT attempt) ─────────────────────────
  fc.customer_country_code,
  fc.customer_country,
  fc.country_group,
  fc.platform,
  fc.locale_code,
  fc.payment_terms,
  fc.is_rnpl,
  fc.payment_flow,
  fc.currency,

  -- ── 3. Timestamps ───────────────────────────────────────────────
  ca.first_attempt_at,
  ca.last_attempt_at,
  sa.payment_attempt_timestamp                                        AS successful_attempt_at,
  DATE(ca.first_attempt_at)                                           AS cart_date,

  -- ── 4. Attempt Counts ───────────────────────────────────────────
  ca.total_attempt_count,
  ca.cit_attempt_count,
  ca.mit_attempt_count,
  ca.customer_attempt_count,
  ca.distinct_payment_methods_count,

  -- ── 5. First CIT Attempt Snapshot ───────────────────────────────
  fc.payment_method                                                   AS first_payment_method,
  fc.payment_method_variant                                           AS first_payment_method_variant,
  fc.payment_processor                                                AS first_payment_processor,
  fc.bin_issuer_country_code                                          AS first_bin_issuer_country_code,
  fc.bin_account_funding_type                                         AS first_bin_account_funding_type,
  fc.bin_network                                                      AS first_bin_network,
  fc.fraud_pre_auth_result                                            AS first_fraud_pre_auth_result,
  fc.three_ds_status                                                  AS first_three_ds_status,
  fc.challenge_issued                                                 AS first_challenge_issued,
  fc.is_three_ds_passed                                               AS first_is_three_ds_passed,
  fc.sent_to_issuer                                                   AS first_sent_to_issuer,
  fc.is_payment_attempt_successful                                    AS first_is_attempt_successful,
  fc.error_code                                                       AS first_error_code,
  fc.error_type                                                       AS first_error_type,

  -- ── 6. Last CIT Attempt Snapshot ────────────────────────────────
  lc.payment_method                                                   AS last_payment_method,
  lc.payment_method_variant                                           AS last_payment_method_variant,
  lc.payment_processor                                                AS last_payment_processor,
  lc.bin_issuer_country_code                                          AS last_bin_issuer_country_code,
  lc.bin_account_funding_type                                         AS last_bin_account_funding_type,
  lc.bin_network                                                      AS last_bin_network,
  lc.fraud_pre_auth_result                                            AS last_fraud_pre_auth_result,
  lc.three_ds_status                                                  AS last_three_ds_status,
  lc.challenge_issued                                                 AS last_challenge_issued,
  lc.is_three_ds_passed                                               AS last_is_three_ds_passed,
  lc.sent_to_issuer                                                   AS last_sent_to_issuer,
  lc.is_payment_attempt_successful                                    AS last_is_attempt_successful,
  lc.error_code                                                       AS last_error_code,
  lc.error_type                                                       AS last_error_type,

  -- ── 7. Payment Method Arrays ────────────────────────────────────
  ca.payment_methods_attempted,
  ca.payment_method_variants_attempted,
  ca.processors_used,

  -- ── 8. Cart Outcome ─────────────────────────────────────────────
  ca.is_successful,

  CASE
    WHEN ca.is_successful = 1 THEN 'paid'
    WHEN lc.fraud_pre_auth_result = 'REFUSE' THEN 'fraud_blocked'
    WHEN lc.three_ds_status = 'failed'       THEN '3ds_failed'
    WHEN lc.issuer_declined = 1              THEN 'issuer_declined'
    WHEN lc.gateway_rejected = 1             THEN 'gateway_rejected'
    WHEN lc.application_error = 1            THEN 'technical_error'
    WHEN lc.sent_to_issuer = 0
     AND lc.payment_processor IS NULL        THEN 'routing_gap'
    ELSE 'abandoned'
  END                                                                 AS cart_outcome,

  (ca.customer_attempt_count > 1)                                     AS is_multi_attempt,
  (fc.is_payment_attempt_successful = 0 AND ca.is_successful = 1)     AS is_retry_recovery,

  -- ── 9. Waterfall Summary (first CIT attempt) ───────────────────
  (fc.fraud_pre_auth_result = 'REFUSE')                               AS first_fraud_blocked,
  (fc.fraud_pre_auth_result = 'THREE_DS')                             AS first_3ds_triggered,
  (fc.challenge_issued = true)                                        AS first_3ds_challenged,
  (COALESCE(fc.is_three_ds_passed, 0) = 1)                           AS first_3ds_passed,
  (fc.sent_to_issuer = 1)                                             AS first_sent_to_issuer_flag,
  (fc.is_payment_attempt_successful = 1)                              AS first_issuer_authorized,

  -- ── 10. RNPL Lifecycle ──────────────────────────────────────────
  ca.rnpl_auth_attempted,
  ca.rnpl_auth_successful,
  ca.rnpl_auth_attempt_count,
  ca.rnpl_auth_first_at,
  ca.rnpl_capture_attempted,
  ca.rnpl_capture_successful,
  ca.rnpl_capture_attempt_count,
  ca.rnpl_capture_first_at,
  ca.rnpl_capture_last_at,
  ca.rnpl_pay_early_attempted,
  ca.rnpl_pay_early_successful,
  ca.rnpl_pay_early_at,

  CASE
    WHEN NOT COALESCE(fc.is_rnpl, false)                 THEN NULL
    WHEN ca.rnpl_pay_early_successful                    THEN 'pay_early_paid'
    WHEN ca.rnpl_capture_successful                      THEN 'captured'
    WHEN ca.rnpl_capture_attempted
     AND NOT ca.rnpl_capture_successful                  THEN 'capture_failed'
    WHEN ca.rnpl_auth_successful
     AND NOT ca.rnpl_capture_attempted                   THEN 'auth_only_pending'
    WHEN ca.rnpl_auth_attempted
     AND NOT ca.rnpl_auth_successful                     THEN 'auth_failed'
    ELSE 'unknown'
  END                                                                 AS rnpl_lifecycle_outcome,

  -- ── 11. Financial (amounts only) ────────────────────────────────
  COALESCE(sa.amount_eur, fc.amount_eur)                              AS amount_eur,
  COALESCE(sa.amount, fc.amount)                                      AS amount

FROM cart_agg ca
INNER JOIN first_cit fc
  ON ca.shopping_cart_id = fc.shopping_cart_id
INNER JOIN last_cit lc
  ON ca.shopping_cart_id = lc.shopping_cart_id
LEFT JOIN successful_attempt sa
  ON ca.shopping_cart_id = sa.shopping_cart_id
;
