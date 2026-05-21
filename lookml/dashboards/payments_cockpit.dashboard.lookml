# =============================================================================
# Payments Cockpit Dashboard
# =============================================================================
# End-to-end payment performance dashboard built on fact_payment_attempt.
#
# Sections:
#   1. Scorecard — Key KPIs (cart SR, first attempt SR, initiation rate, costs)
#   2. Cart Funnel — Payment page → Initiated → Fraud approved → Sent to issuer → Settled
#   3. Waterfall — Fraud/3DS/Issuer decomposition of attempt SR
#   4. Trend Charts — Weekly rates over time
#   5. Country Breakdown — Top markets with SR, fraud, 3DS, sent-to-issuer
#   6. Processor Performance — SR and volume by processor
#   7. Payment Method Mix — Volume split by payment method
# =============================================================================

- dashboard: payments_cockpit
  title: "Payments Cockpit"
  layout: newspaper
  preferred_viewer: dashboards-next
  refresh: 1 day

  filters:
    - name: Date Range
      title: "Date Range"
      type: field_filter
      default_value: "30 days"
      explore: fact_payment_attempt
      field: fact_payment_attempt.payment_attempt_date
      allow_multiple_values: true
      required: false
      ui_config:
        type: relative_timeframes

    - name: Customer Country
      title: "Customer Country"
      type: field_filter
      default_value: ""
      explore: fact_payment_attempt
      field: fact_payment_attempt.customer_country_code
      allow_multiple_values: true
      required: false

    - name: Platform
      title: "Platform"
      type: field_filter
      default_value: ""
      explore: fact_payment_attempt
      field: fact_payment_attempt.platform
      allow_multiple_values: true
      required: false

    - name: Payment Method
      title: "Payment Method"
      type: field_filter
      default_value: ""
      explore: fact_payment_attempt
      field: fact_payment_attempt.payment_method
      allow_multiple_values: true
      required: false

    - name: Payment Processor
      title: "Payment Processor"
      type: field_filter
      default_value: ""
      explore: fact_payment_attempt
      field: fact_payment_attempt.payment_processor
      allow_multiple_values: true
      required: false

    - name: Payment Flow
      title: "Payment Flow"
      type: field_filter
      default_value: ""
      explore: fact_payment_attempt
      field: fact_payment_attempt.payment_flow
      allow_multiple_values: true
      required: false

    - name: Initiator Type
      title: "Initiator Type"
      type: field_filter
      default_value: "CIT"
      explore: fact_payment_attempt
      field: fact_payment_attempt.payment_initiator_type
      allow_multiple_values: false
      required: false

    - name: First Attempt Only
      title: "First Customer Attempt Only"
      type: field_filter
      default_value: "Yes"
      explore: fact_payment_attempt
      field: fact_payment_attempt.is_first_customer_attempt
      allow_multiple_values: false
      required: false

  elements:

  # ── SECTION 1: SCORECARD ──────────────────────────────────────

    - title: "Initiated Carts"
      name: sc_initiated_carts
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.initiated_carts]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 0
      width: 4
      height: 3

    - title: "Settled GMV (EUR)"
      name: sc_settled_gmv
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.settled_gmv]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 4
      width: 4
      height: 3

    - title: "Cart Payment SR"
      name: sc_cart_sr
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.cart_payment_success_rate]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 8
      width: 4
      height: 3

    - title: "First Attempt SR"
      name: sc_attempt_sr
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.attempt_success_rate]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 12
      width: 4
      height: 3

    - title: "Sent-to-Issuer Rate"
      name: sc_sent_to_issuer
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.sent_to_issuer_rate]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 16
      width: 4
      height: 3

    - title: "Payment Costs % GMV"
      name: sc_costs_gmv
      explore: fact_payment_attempt
      type: single_value
      fields: [fact_payment_attempt.payment_costs_pct_of_gmv]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 0
      col: 20
      width: 4
      height: 3

  # ── SECTION 2: CART FUNNEL ────────────────────────────────────

    - title: "Payment Cart Funnel"
      name: cart_funnel
      explore: fact_payment_attempt
      type: looker_funnel
      fields:
        - fact_payment_attempt.payment_page_view_carts
        - fact_payment_attempt.initiated_carts
        - fact_payment_attempt.fraud_approved_carts
        - fact_payment_attempt.sent_to_issuer_carts
        - fact_payment_attempt.settled_carts
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      series_labels:
        fact_payment_attempt.payment_page_view_carts: "Payment Page Views"
        fact_payment_attempt.initiated_carts: "Payment Initiated"
        fact_payment_attempt.fraud_approved_carts: "Fraud Approved"
        fact_payment_attempt.sent_to_issuer_carts: "Sent to Issuer"
        fact_payment_attempt.settled_carts: "Settled"
      row: 3
      col: 0
      width: 12
      height: 8

  # ── SECTION 3: WATERFALL DECOMPOSITION ────────────────────────

    - title: "Attempt SR Waterfall"
      name: waterfall_table
      explore: fact_payment_attempt
      type: looker_grid
      fields:
        - fact_payment_attempt.total_attempts
        - fact_payment_attempt.fraud_block_rate
        - fact_payment_attempt.three_ds_trigger_rate
        - fact_payment_attempt.sent_to_issuer_rate
        - fact_payment_attempt.authorization_rate
        - fact_payment_attempt.attempt_success_rate
        - fact_payment_attempt.three_ds_challenge_rate
        - fact_payment_attempt.three_ds_pass_rate
        - fact_payment_attempt.sr_three_ds_frictionless
        - fact_payment_attempt.sr_three_ds_challenged
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 3
      col: 12
      width: 12
      height: 8

  # ── SECTION 4: WEEKLY TRENDS ──────────────────────────────────

    - title: "Cart SR — Weekly Trend"
      name: trend_cart_sr
      explore: fact_payment_attempt
      type: looker_line
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.cart_payment_success_rate
      sorts: [fact_payment_attempt.payment_attempt_week]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 11
      col: 0
      width: 8
      height: 6

    - title: "Attempt SR — Weekly Trend"
      name: trend_attempt_sr
      explore: fact_payment_attempt
      type: looker_line
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.attempt_success_rate
      sorts: [fact_payment_attempt.payment_attempt_week]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 11
      col: 8
      width: 8
      height: 6

    - title: "Sent-to-Issuer Rate — Weekly Trend"
      name: trend_sent_to_issuer
      explore: fact_payment_attempt
      type: looker_line
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.sent_to_issuer_rate
      sorts: [fact_payment_attempt.payment_attempt_week]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 11
      col: 16
      width: 8
      height: 6

  # ── SECTION 5: COUNTRY BREAKDOWN ──────────────────────────────

    - title: "Top Markets — Payment Performance"
      name: country_breakdown
      explore: fact_payment_attempt
      type: looker_grid
      fields:
        - fact_payment_attempt.bin_issuer_country_code
        - fact_payment_attempt.total_attempts
        - fact_payment_attempt.attempt_success_rate
        - fact_payment_attempt.cart_payment_success_rate
        - fact_payment_attempt.fraud_block_rate
        - fact_payment_attempt.three_ds_trigger_rate
        - fact_payment_attempt.sent_to_issuer_rate
        - fact_payment_attempt.authorization_rate
        - fact_payment_attempt.payment_costs_pct_of_gmv
      sorts: [fact_payment_attempt.total_attempts desc]
      limit: 30
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 17
      col: 0
      width: 24
      height: 10

  # ── SECTION 6: PROCESSOR PERFORMANCE ──────────────────────────

    - title: "Attempt SR by Processor — Weekly"
      name: processor_sr
      explore: fact_payment_attempt
      type: looker_line
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.payment_processor
        - fact_payment_attempt.attempt_success_rate
      pivots: [fact_payment_attempt.payment_processor]
      sorts: [fact_payment_attempt.payment_attempt_week]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 27
      col: 0
      width: 12
      height: 7

    - title: "Volume Split by Processor — Weekly"
      name: processor_volume
      explore: fact_payment_attempt
      type: looker_area
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.payment_processor
        - fact_payment_attempt.total_attempts
      pivots: [fact_payment_attempt.payment_processor]
      sorts: [fact_payment_attempt.payment_attempt_week]
      stacking: percent
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 27
      col: 12
      width: 12
      height: 7

  # ── SECTION 7: PAYMENT METHOD MIX ────────────────────────────

    - title: "Volume Split by Payment Method — Weekly"
      name: pm_volume
      explore: fact_payment_attempt
      type: looker_area
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.payment_method
        - fact_payment_attempt.total_attempts
      pivots: [fact_payment_attempt.payment_method]
      sorts: [fact_payment_attempt.payment_attempt_week]
      stacking: percent
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 34
      col: 0
      width: 12
      height: 7

    - title: "Attempt SR by Payment Method — Weekly"
      name: pm_sr
      explore: fact_payment_attempt
      type: looker_line
      fields:
        - fact_payment_attempt.payment_attempt_week
        - fact_payment_attempt.payment_method
        - fact_payment_attempt.attempt_success_rate
      pivots: [fact_payment_attempt.payment_method]
      sorts: [fact_payment_attempt.payment_attempt_week]
      listen:
        Date Range: fact_payment_attempt.payment_attempt_date
        Customer Country: fact_payment_attempt.customer_country_code
        Platform: fact_payment_attempt.platform
        Payment Method: fact_payment_attempt.payment_method
        Payment Processor: fact_payment_attempt.payment_processor
        Payment Flow: fact_payment_attempt.payment_flow
        Initiator Type: fact_payment_attempt.payment_initiator_type
        First Attempt Only: fact_payment_attempt.is_first_customer_attempt
      row: 34
      col: 12
      width: 12
      height: 7
