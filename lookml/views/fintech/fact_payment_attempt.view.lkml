# =============================================================================
# fact_payment_attempt — Payments Explore View
# =============================================================================
# One row per payment attempt from production.payments.fact_payment_attempt.
# Replaces the legacy production.analytics.fact_payment explore.
#
# Metric hierarchy (most robust → most granular):
#   L1 Visitor SR → L2 Cart SR → L3 First Attempt SR → L4 All Attempts SR → L5 System SR
#
# Waterfall decomposition:
#   Fraud Pre-Auth → 3DS → Sent to Issuer → Issuer Authorization
# =============================================================================

view: fact_payment_attempt {
  sql_table_name: production.payments.fact_payment_attempt ;;
  suggestions: no

  # ────────────────────────────────────────────────────────────────
  # IDENTITY & METADATA
  # ────────────────────────────────────────────────────────────────

  dimension: shopping_cart_id {
    type: string
    hidden: yes
    sql: ${TABLE}.shopping_cart_id ;;
  }

  dimension: visitor_id {
    type: string
    hidden: yes
    sql: ${TABLE}.visitor_id ;;
  }

  dimension_group: payment_attempt {
    type: time
    timeframes: [raw, date, week, month, quarter, year, day_of_week, week_of_year]
    convert_tz: no
    datatype: timestamp
    sql: ${TABLE}.payment_attempt_timestamp ;;
  }

  # ────────────────────────────────────────────────────────────────
  # GEOGRAPHY & CUSTOMER
  # ────────────────────────────────────────────────────────────────

  dimension: customer_country_code {
    type: string
    map_layer_name: countries
    label: "Customer Country"
    sql: ${TABLE}.customer_country_code ;;
  }

  dimension: customer_country {
    type: string
    label: "Customer Country Name"
    sql: ${TABLE}.customer_country ;;
  }

  dimension: country_group {
    type: string
    label: "Country Group"
    sql: ${TABLE}.country_group ;;
  }

  dimension: bin_issuer_country_code {
    type: string
    map_layer_name: countries
    label: "Card Issuer Country (BIN)"
    description: "ISO-2 country from card BIN. Primary geo dimension for card routing analysis."
    sql: ${TABLE}.bin_issuer_country_code ;;
  }

  dimension: bin_issuer_name {
    type: string
    label: "Card Issuer Name"
    sql: ${TABLE}.bin_issuer_name ;;
  }

  dimension: platform {
    type: string
    label: "Platform"
    sql: ${TABLE}.platform ;;
  }

  dimension: locale_code {
    type: string
    label: "Locale"
    sql: ${TABLE}.locale_code ;;
  }

  # ────────────────────────────────────────────────────────────────
  # PAYMENT METHOD & CARD
  # ────────────────────────────────────────────────────────────────

  dimension: payment_method {
    type: string
    label: "Payment Method"
    sql: ${TABLE}.payment_method ;;
  }

  dimension: payment_method_variant {
    type: string
    label: "Card Network"
    description: "VISA, MASTERCARD, AMEX, etc."
    sql: ${TABLE}.payment_method_variant ;;
  }

  dimension: bin_account_funding_type {
    type: string
    label: "Card Funding Type"
    description: "CREDIT, DEBIT, PREPAID"
    sql: ${TABLE}.bin_account_funding_type ;;
  }

  dimension: bin_network {
    type: string
    label: "BIN Network"
    sql: ${TABLE}.bin_network ;;
  }

  dimension: is_network_tokenized {
    type: yesno
    label: "Network Tokenized"
    description: "Apple Pay, Google Pay token usage"
    sql: ${TABLE}.is_network_tokenized ;;
  }

  # ────────────────────────────────────────────────────────────────
  # PAYMENT FLOW & ROUTING
  # ────────────────────────────────────────────────────────────────

  dimension: payment_processor {
    type: string
    label: "Payment Processor"
    description: "ADYEN, CHECKOUT, JPMC, or NULL (routing gap)"
    sql: ${TABLE}.payment_processor ;;
  }

  dimension: payment_flow {
    type: string
    label: "Payment Flow"
    description: "pay_now, rnpl_auth_0, rnpl_pay_early, rnpl_auto_capture"
    sql: ${TABLE}.payment_flow ;;
  }

  dimension: payment_terms {
    type: string
    label: "Payment Terms"
    description: "pay_now or pay_later"
    sql: ${TABLE}.payment_terms ;;
  }

  dimension: payment_initiator_type {
    type: string
    label: "Initiator Type"
    description: "CIT (Customer) or MIT (Merchant)"
    sql: ${TABLE}.payment_initiator_type ;;
  }

  dimension: is_rnpl {
    type: yesno
    label: "Is RNPL"
    sql: ${TABLE}.is_rnpl ;;
  }

  dimension: currency {
    type: string
    label: "Currency"
    sql: ${TABLE}.currency ;;
  }

  # ────────────────────────────────────────────────────────────────
  # DEDUPLICATION RANKS
  # ────────────────────────────────────────────────────────────────

  dimension: customer_attempt_rank {
    type: number
    label: "Customer Attempt Rank"
    description: "Rank within customer-visible attempts. 1 = first attempt."
    sql: ${TABLE}.customer_attempt_rank ;;
  }

  dimension: system_attempt_rank {
    type: number
    label: "System Attempt Rank"
    sql: ${TABLE}.system_attempt_rank ;;
  }

  dimension: is_first_customer_attempt {
    type: yesno
    label: "Is First Customer Attempt"
    sql: ${TABLE}.customer_attempt_rank = 1 ;;
  }

  # ────────────────────────────────────────────────────────────────
  # FRAUD (FORTER)
  # ────────────────────────────────────────────────────────────────

  dimension: fraud_pre_auth_result {
    type: string
    label: "Fraud Pre-Auth Result"
    description: "ACCEPT / THREE_DS / THREE_DS_EXEMPTION / REFUSE / NULL"
    sql: ${TABLE}.fraud_pre_auth_result ;;
  }

  dimension: fraud_post_auth_result {
    type: string
    label: "Fraud Post-Auth Result"
    sql: ${TABLE}.fraud_post_auth_result ;;
  }

  # ────────────────────────────────────────────────────────────────
  # 3DS
  # ────────────────────────────────────────────────────────────────

  dimension: three_ds_status {
    type: string
    label: "3DS Status"
    description: "out_of_scope, frictionless, success (challenge passed), failed"
    sql: ${TABLE}.three_ds_status ;;
  }

  dimension: challenge_issued {
    type: yesno
    label: "3DS Challenge Issued"
    sql: ${TABLE}.challenge_issued ;;
  }

  dimension: is_three_ds_passed {
    type: number
    hidden: yes
    sql: ${TABLE}.is_three_ds_passed ;;
  }

  # ────────────────────────────────────────────────────────────────
  # OUTCOME FLAGS
  # ────────────────────────────────────────────────────────────────

  dimension: sent_to_issuer_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.sent_to_issuer ;;
  }

  dimension: payment_initiated_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.payment_initiated ;;
  }

  dimension: is_payment_attempt_successful_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.is_payment_attempt_successful ;;
  }

  dimension: is_customer_attempt_successful_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.is_customer_attempt_successful ;;
  }

  dimension: is_shopping_cart_successful_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.is_shopping_cart_successful ;;
  }

  # ────────────────────────────────────────────────────────────────
  # ERROR FIELDS
  # ────────────────────────────────────────────────────────────────

  dimension: error_code {
    type: string
    label: "Error Code"
    description: "DO_NOT_HONOR, INSUFFICIENT_FUNDS, etc."
    sql: ${TABLE}.error_code ;;
  }

  dimension: error_type {
    type: string
    label: "Error Type"
    sql: ${TABLE}.error_type ;;
  }

  dimension: error_message {
    type: string
    label: "Error Message"
    sql: ${TABLE}.error_message ;;
  }

  dimension: issuer_declined_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.issuer_declined ;;
  }

  dimension: gateway_rejected_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.gateway_rejected ;;
  }

  dimension: application_error_flag {
    type: number
    hidden: yes
    sql: ${TABLE}.application_error ;;
  }

  # ────────────────────────────────────────────────────────────────
  # FINANCIAL
  # ────────────────────────────────────────────────────────────────

  dimension: amount_eur {
    type: number
    hidden: yes
    sql: ${TABLE}.amount_eur ;;
  }

  dimension: amount {
    type: number
    hidden: yes
    sql: ${TABLE}.amount ;;
  }

  # ────────────────────────────────────────────────────────────────
  # AMOUNT BUCKET (derived dimension)
  # ────────────────────────────────────────────────────────────────

  dimension: amount_bucket {
    type: string
    label: "Amount Bucket (EUR)"
    sql:
      CASE
        WHEN ${amount_eur} < 50 THEN '1. < 50'
        WHEN ${amount_eur} < 200 THEN '2. 50-200'
        WHEN ${amount_eur} < 500 THEN '3. 200-500'
        WHEN ${amount_eur} < 1000 THEN '4. 500-1000'
        ELSE '5. 1000+'
      END
    ;;
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — CART-LEVEL FUNNEL
  # ════════════════════════════════════════════════════════════════

  measure: payment_page_view_carts {
    type: count_distinct
    group_label: "1. Cart Funnel"
    label: "1.1 Payment Page View Carts"
    description: "Distinct carts that reached the payment page"
    sql: ${shopping_cart_id} ;;
  }

  measure: initiated_carts {
    type: count_distinct
    group_label: "1. Cart Funnel"
    label: "1.2 Initiated Carts"
    description: "Carts where the visitor attempted to pay"
    sql: CASE WHEN ${payment_initiated_flag} = 1 THEN ${shopping_cart_id} END ;;
  }

  measure: fraud_approved_carts {
    type: count_distinct
    group_label: "1. Cart Funnel"
    label: "1.3 Fraud Approved Carts"
    description: "Carts that passed fraud check (ACCEPT, THREE_DS, or THREE_DS_EXEMPTION)"
    sql: CASE WHEN ${fraud_pre_auth_result} IN ('ACCEPT', 'THREE_DS', 'THREE_DS_EXEMPTION') THEN ${shopping_cart_id} END ;;
  }

  measure: sent_to_issuer_carts {
    type: count_distinct
    group_label: "1. Cart Funnel"
    label: "1.4 Sent to Issuer Carts"
    sql: CASE WHEN ${sent_to_issuer_flag} = 1 THEN ${shopping_cart_id} END ;;
  }

  measure: settled_carts {
    type: count_distinct
    group_label: "1. Cart Funnel"
    label: "1.5 Settled Carts"
    description: "Carts that were successfully paid"
    sql: CASE WHEN ${is_shopping_cart_successful_flag} = 1 THEN ${shopping_cart_id} END ;;
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — GMV FUNNEL
  # ════════════════════════════════════════════════════════════════

  measure: payment_page_view_gmv {
    type: sum
    group_label: "2. GMV Funnel"
    label: "2.1 Payment Page View GMV (EUR)"
    sql: ${amount_eur} ;;
    value_format_name: decimal_0
  }

  measure: initiated_gmv {
    type: sum
    group_label: "2. GMV Funnel"
    label: "2.2 Initiated GMV (EUR)"
    sql: CASE WHEN ${payment_initiated_flag} = 1 THEN ${amount_eur} ELSE 0 END ;;
    value_format_name: decimal_0
  }

  measure: settled_gmv {
    type: sum
    group_label: "2. GMV Funnel"
    label: "2.5 Settled GMV (EUR)"
    sql: CASE WHEN ${is_shopping_cart_successful_flag} = 1 THEN ${amount_eur} ELSE 0 END ;;
    value_format_name: decimal_0
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — ATTEMPT COUNTS
  # ════════════════════════════════════════════════════════════════

  measure: total_attempts {
    type: count
    group_label: "3. Attempt Counts"
    label: "Total Attempts"
  }

  measure: successful_attempts {
    type: sum
    group_label: "3. Attempt Counts"
    label: "Successful Attempts"
    sql: ${is_customer_attempt_successful_flag} ;;
    value_format_name: decimal_0
  }

  measure: sent_to_issuer_attempts {
    type: sum
    group_label: "3. Attempt Counts"
    label: "Sent to Issuer Attempts"
    sql: ${sent_to_issuer_flag} ;;
    value_format_name: decimal_0
  }

  measure: three_ds_passed_attempts {
    type: sum
    group_label: "3. Attempt Counts"
    label: "3DS Passed Attempts"
    sql: ${is_three_ds_passed} ;;
    value_format_name: decimal_0
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — CONVERSION & SUCCESS RATES
  # ════════════════════════════════════════════════════════════════

  measure: payment_initiation_rate {
    type: number
    group_label: "4. Rates"
    label: "Payment Initiation Rate"
    description: "initiated_carts / payment_page_view_carts"
    sql: ${initiated_carts} / NULLIF(${payment_page_view_carts}, 0) ;;
    value_format_name: percent_2
  }

  measure: cart_payment_success_rate {
    type: number
    group_label: "4. Rates"
    label: "Cart Payment SR"
    description: "settled_carts / initiated_carts (L2 metric)"
    sql: ${settled_carts} / NULLIF(${initiated_carts}, 0) ;;
    value_format_name: percent_2
  }

  measure: attempt_success_rate {
    type: number
    group_label: "4. Rates"
    label: "Attempt SR"
    description: "successful_attempts / total_attempts"
    sql: ${successful_attempts} / NULLIF(${total_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: sent_to_issuer_rate {
    type: number
    group_label: "4. Rates"
    label: "Sent-to-Issuer Rate"
    description: "sent_to_issuer / total_attempts"
    sql: ${sent_to_issuer_attempts} / NULLIF(${total_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: authorization_rate {
    type: number
    group_label: "4. Rates"
    label: "Authorization Rate"
    description: "successful / sent_to_issuer (issuer-level auth rate)"
    sql: ${successful_attempts} / NULLIF(${sent_to_issuer_attempts}, 0) ;;
    value_format_name: percent_2
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — FRAUD WATERFALL
  # ════════════════════════════════════════════════════════════════

  measure: fraud_accept_attempts {
    type: count
    group_label: "5. Fraud Waterfall"
    label: "Fraud ACCEPT Attempts"
    filters: [fraud_pre_auth_result: "ACCEPT"]
  }

  measure: fraud_refuse_attempts {
    type: count
    group_label: "5. Fraud Waterfall"
    label: "Fraud REFUSE Attempts"
    filters: [fraud_pre_auth_result: "REFUSE"]
  }

  measure: fraud_three_ds_attempts {
    type: count
    group_label: "5. Fraud Waterfall"
    label: "Fraud THREE_DS Attempts"
    filters: [fraud_pre_auth_result: "THREE_DS"]
  }

  measure: fraud_three_ds_exemption_attempts {
    type: count
    group_label: "5. Fraud Waterfall"
    label: "Fraud THREE_DS_EXEMPTION Attempts"
    filters: [fraud_pre_auth_result: "THREE_DS_EXEMPTION"]
  }

  measure: fraud_block_rate {
    type: number
    group_label: "5. Fraud Waterfall"
    label: "Fraud Block Rate"
    description: "REFUSE / total"
    sql: ${fraud_refuse_attempts} / NULLIF(${total_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: fraud_accept_rate {
    type: number
    group_label: "5. Fraud Waterfall"
    label: "Fraud ACCEPT Share"
    sql: ${fraud_accept_attempts} / NULLIF(${total_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: three_ds_trigger_rate {
    type: number
    group_label: "5. Fraud Waterfall"
    label: "3DS Trigger Rate"
    description: "THREE_DS / total"
    sql: ${fraud_three_ds_attempts} / NULLIF(${total_attempts}, 0) ;;
    value_format_name: percent_2
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — 3DS DEEP DIVE
  # ════════════════════════════════════════════════════════════════

  measure: three_ds_challenged_attempts {
    type: count
    group_label: "6. 3DS Deep Dive"
    label: "3DS Challenged Attempts"
    filters: [fraud_pre_auth_result: "THREE_DS", challenge_issued: "Yes"]
  }

  measure: three_ds_frictionless_attempts {
    type: count
    group_label: "6. 3DS Deep Dive"
    label: "3DS Frictionless Attempts"
    filters: [fraud_pre_auth_result: "THREE_DS", challenge_issued: "No"]
  }

  measure: three_ds_challenged_successful {
    type: sum
    group_label: "6. 3DS Deep Dive"
    label: "3DS Challenged Successful"
    sql: ${is_customer_attempt_successful_flag} ;;
    filters: [fraud_pre_auth_result: "THREE_DS", challenge_issued: "Yes"]
  }

  measure: three_ds_frictionless_successful {
    type: sum
    group_label: "6. 3DS Deep Dive"
    label: "3DS Frictionless Successful"
    sql: ${is_customer_attempt_successful_flag} ;;
    filters: [fraud_pre_auth_result: "THREE_DS", challenge_issued: "No"]
  }

  measure: three_ds_challenge_rate {
    type: number
    group_label: "6. 3DS Deep Dive"
    label: "3DS Challenge Rate"
    description: "challenged / 3DS-triggered"
    sql: ${three_ds_challenged_attempts} / NULLIF(${fraud_three_ds_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: three_ds_pass_rate {
    type: number
    group_label: "6. 3DS Deep Dive"
    label: "3DS Pass Rate"
    description: "passed / 3DS-triggered"
    sql: ${three_ds_passed_attempts} / NULLIF(${fraud_three_ds_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: sr_three_ds_challenged {
    type: number
    group_label: "6. 3DS Deep Dive"
    label: "SR — 3DS Challenged"
    sql: ${three_ds_challenged_successful} / NULLIF(${three_ds_challenged_attempts}, 0) ;;
    value_format_name: percent_2
  }

  measure: sr_three_ds_frictionless {
    type: number
    group_label: "6. 3DS Deep Dive"
    label: "SR — 3DS Frictionless"
    sql: ${three_ds_frictionless_successful} / NULLIF(${three_ds_frictionless_attempts}, 0) ;;
    value_format_name: percent_2
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — ERROR MIX
  # ════════════════════════════════════════════════════════════════

  measure: issuer_declined_attempts {
    type: sum
    group_label: "7. Error Mix"
    label: "Issuer Declined"
    sql: ${issuer_declined_flag} ;;
    value_format_name: decimal_0
  }

  measure: gateway_rejected_attempts {
    type: sum
    group_label: "7. Error Mix"
    label: "Gateway Rejected"
    sql: ${gateway_rejected_flag} ;;
    value_format_name: decimal_0
  }

  measure: application_error_attempts {
    type: sum
    group_label: "7. Error Mix"
    label: "Application Error"
    sql: ${application_error_flag} ;;
    value_format_name: decimal_0
  }

  measure: issuer_decline_rate {
    type: number
    group_label: "7. Error Mix"
    label: "Issuer Decline Rate"
    description: "issuer_declined / sent_to_issuer"
    sql: ${issuer_declined_attempts} / NULLIF(${sent_to_issuer_attempts}, 0) ;;
    value_format_name: percent_2
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — PAYMENT COSTS
  # ════════════════════════════════════════════════════════════════

  measure: total_fee_eur {
    type: sum
    group_label: "8. Payment Costs"
    label: "Total Fee (EUR)"
    sql: ${TABLE}.total_fee_amount_eur_new ;;
    value_format_name: decimal_2
  }

  measure: scheme_fee_eur {
    type: sum
    group_label: "8. Payment Costs"
    label: "Scheme Fee (EUR)"
    sql: ${TABLE}.scheme_fee_amount_eur_new ;;
    value_format_name: decimal_2
  }

  measure: interchange_fee_eur {
    type: sum
    group_label: "8. Payment Costs"
    label: "Interchange Fee (EUR)"
    sql: ${TABLE}.interchange_fee_amount_eur_new ;;
    value_format_name: decimal_2
  }

  measure: acquirer_fee_eur {
    type: sum
    group_label: "8. Payment Costs"
    label: "Acquirer Fee (EUR)"
    sql: ${TABLE}.acquirer_fee_amount_eur_new ;;
    value_format_name: decimal_2
  }

  measure: payment_costs_pct_of_gmv {
    type: number
    group_label: "8. Payment Costs"
    label: "Payment Costs % of GMV"
    sql: ABS(${total_fee_eur}) / NULLIF(${settled_gmv}, 0) ;;
    value_format_name: percent_3
  }

  # ════════════════════════════════════════════════════════════════
  # MEASURES — RETRY / RECOVERY
  # ════════════════════════════════════════════════════════════════

  measure: multi_attempt_carts {
    type: count_distinct
    group_label: "9. Retry & Recovery"
    label: "Multi-Attempt Carts"
    description: "Carts with more than one customer attempt"
    sql:
      CASE WHEN ${customer_attempt_rank} > 1 THEN ${shopping_cart_id} END
    ;;
  }

  measure: multi_attempt_cart_rate {
    type: number
    group_label: "9. Retry & Recovery"
    label: "Multi-Attempt Cart Rate"
    description: "% of carts needing more than one customer attempt"
    sql: ${multi_attempt_carts} / NULLIF(${initiated_carts}, 0) ;;
    value_format_name: percent_2
  }
}
