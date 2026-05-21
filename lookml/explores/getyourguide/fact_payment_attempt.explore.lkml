include: "/views/fintech/fact_payment_attempt.view.lkml"

explore: fact_payment_attempt {
  from: fact_payment_attempt
  label: "Payments — fact_payment_attempt"
  description: "One row per payment attempt. Supports the full metric hierarchy: cart funnel, attempt-level waterfall (fraud → 3DS → sent-to-issuer → authorization), payment costs, and retry analysis. Filter to customer_attempt_rank = 1 and CIT for standard first-attempt analysis."

  always_filter: {
    filters: [
      fact_payment_attempt.payment_attempt_date: "30 days"
    ]
  }
}
