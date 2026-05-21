# Routing Experiment — LookML port

LookML conversion of [Routing Experiment Deep Dive](https://natalia-shvydun.github.io/routing-experiment-report/) (the React dashboard backed by `public/data.json` in this repo) into the `gyg-looker` project, modelled after `dashboards/l2_search_n_discovery__transaction.dashboard.lookml`.

## File map

```
lookml/
├── views/fintech/
│   ├── fact_routing_experiment_cube.view.lkml         ← attempt-level cube + filtered measures
│   └── fact_routing_experiment_visitor_sr.view.lkml   ← visitor-level KPIs
├── explores/getyourguide/
│   └── fact_routing_experiment_cube.explore.lkml      ← wraps both views, pins experiment_id
├── dashboards/
│   └── routing_experiment.dashboard.lookml            ← 7-section dashboard, mirrors React panels
├── sql/
│   ├── fact_routing_experiment_cube.sql               ← producing query for the cube table
│   └── fact_routing_experiment_visitor_sr.sql         ← producing query for the visitor-SR table
└── getyourguide.model.patch.lkml                      ← include lines to drop into models/getyourguide.model.lkml
```

## Drop-in instructions

```bash
# from the repo root of this Cursor workspace
cp lookml/views/fintech/*.view.lkml          ~/Desktop/Work/gyg-looker/views/fintech/
cp lookml/explores/getyourguide/*.explore.lkml ~/Desktop/Work/gyg-looker/explores/getyourguide/
cp lookml/dashboards/*.dashboard.lookml       ~/Desktop/Work/gyg-looker/dashboards/
```

Then add the include in `gyg-looker/models/getyourguide.model.lkml` near the existing `fact_payment_attempt.explore.lkml` line (see `getyourguide.model.patch.lkml`):

```lookml
include: "/explores/getyourguide/fact_routing_experiment_cube.explore.lkml"
```

## Backing tables

The model targets two new Databricks tables (Unity Catalog):

| Table | Grain | Producer |
|---|---|---|
| `production.payments.fact_routing_experiment_cube` | `(experiment_id, group_name, routing_rule, bin_issuer_country_code, currency, payment_processor, payment_method_variant, payment_initiator_type, is_first_attempt, system_attempt_rank, payment_flow, fraud_pre_auth_result, challenge_issued, experiment_iteration)` | `lookml/sql/fact_routing_experiment_cube.sql` |
| `production.payments.fact_routing_experiment_visitor_sr` | `(experiment_id, experiment_iteration, group_name)` | `lookml/sql/fact_routing_experiment_visitor_sr.sql` |

Schedule both producing queries daily (e.g. via a Databricks Job using `databricks.yml`), to match the dashboard's `refresh: 1 day`.

If you'd rather not materialise tables, both views can be converted to PDTs by replacing the `sql_table_name:` line with a `derived_table: { sql: ...; persist_for: "24 hours" }` block — the SQL files in `lookml/sql/` translate directly.

## Panel mapping (React → LookML)

| React panel (`src/components/report/panels/*.jsx`) | LookML tile name | Visualisation |
|---|---|---|
| `KPISummaryPanel` (top of report) | `kpi_total_attempts`, `kpi_total_visitors`, `kpi_attempt_sr_delta`, `kpi_visitor_sr_delta` | 4× `single_value` |
| `KPISummaryPanel` (full table) + `SignificanceSummary` | `significance_summary` | `looker_grid` (transposed) with z-score table-calcs |
| `AcquirerSplitPanel` | `acquirer_split_chart` + `acquirer_split_table` | `looker_bar` (% stacked) + `looker_grid` |
| `RoutingRulePanel` | `routing_rule_chart` + `routing_rule_table` | `looker_bar` (% stacked) + `looker_grid` |
| `CountrySRPanel` | `country_sr_table` | `looker_grid` with sorting + z-score conditional formatting |
| `SuccessRatePanel` | covered by `acquirer_split_table` (per-acquirer SR) + `significance_summary` | n/a (folded in) |
| `FraudPanel` | `fraud_mix_chart` + `fraud_rates_table` | `looker_column` + `looker_grid` |
| `ThreeDSPanel` | `threeds_table` | `looker_grid` (transposed, pivoted on `group_name`) |

## Filter mapping (FilterPanel → dashboard filters)

| React filter | Dashboard filter | Field | Default |
|---|---|---|---|
| `countries` | Issuer Country | `bin_issuer_country_code` | (all) |
| `currencies` | Currency | `currency` | (all) |
| `routingRules` | Routing Rule | `routing_rule` | (all) |
| `paymentFlows` | Payment Flow | `payment_flow` | `pay_now,rnpl_pay_early` |
| `initiatorType` | Initiator Type | `payment_initiator_type` | `CIT` |
| `firstAttemptOnly` | First Attempt Only | `is_first_attempt` | `Yes` |
| `systemAttemptRanks` | System Attempt Rank | `system_attempt_rank` | `1` |
| `experimentIterations` | Experiment Iteration | `experiment_iteration` | (all) |
| `processors` | Processor | `payment_processor` | (all) |
| `networks` | Network | `payment_method_variant` | (all) |
| `challengeIssued` | 3DS Challenge Issued | `challenge_issued` | (all) |

## Significance methodology

Looker has no native two-proportion z-test, so each table that needs significance computes z in a `dynamic_fields:` table-calculation:

```text
p_pooled = (s1 + s2) / (n1 + n2)
se       = sqrt( p_pooled * (1 - p_pooled) * (1/n1 + 1/n2) )
z        = (p2 - p1) / se
```

Cells with `|z| ≥ 1.96` (two-sided p < 0.05) are highlighted red via `conditional_formatting`. The exact p-value is intentionally not computed — Looker table-calc syntax doesn't have `exp()` reliably across rendering engines, so the polynomial CDF approximation used in `src/utils/stats.js` would render unreliably.

If you need the literal p-value column, push it down into the producing SQL (Databricks supports `2 * (1 - normal_cdf(abs(z)))` via `BUILTIN_NORMAL_CDF`) and expose it as a measure on the view.

## Things to verify before merging

1. **Experiment column names** — `lookml/sql/fact_routing_experiment_cube.sql` assumes `fact_payment_attempt` carries `experiment_id`, `experiment_group`, `routing_rule`, `system_attempt_rank`, `is_first_attempt`, `is_customer_attempt_successful`, `sent_to_issuer`, `three_ds_passed`, `fraud_pre_auth_result`, `challenge_issued`. The first three may need a join to your assignment / experiment tracking table — wire to the actual source in your warehouse.
2. **Iteration boundaries** — currently hard-coded to Apr-2 → Apr-30 (Iteration 1) and ≥ May-1 (Iteration 2). Update if the experiment runs further.
3. **Visitor-SR producer** — `payment_initiation_events.is_successful_booker` is a placeholder; align with the actual visitor → booker flag your team uses.
4. **`always_filter` on experiment_id** — both explores pin `experiment_id = 'pay-payment-orchestration-routing-in-house'`. If you generalise the cube to host multiple routing experiments, expose this as a dashboard filter and remove the `always_filter`.
5. **Dashboard layout rows** — newspaper layout with a 24-col grid. Heights/rows are tuned by eye; verify on a real Looker instance and tweak `row:` / `height:` as needed.
