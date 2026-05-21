# =============================================================================
# Patch for models/getyourguide.model.lkml — add these include lines
# =============================================================================
# Insert under the "FINANCE & PAYMENTS" section, alongside the existing
# fact_payment / fact_payment_attempt / payment_initiation_events includes.
# Around line 86 in the current model:
#
#   include: "/explores/getyourguide/fact_payment.explore.lkml"
#   include: "/explores/getyourguide/fact_payment_attempt.explore.lkml"
#   include: "/explores/getyourguide/payment_initiation_events.explore.lkml"
# + include: "/explores/getyourguide/fact_routing_experiment_cube.explore.lkml"
# + include: "/explores/getyourguide/fact_payment_attempt.explore.lkml"  # new payments explore
#
# Then add the dashboard includes at the bottom of the includes block:

include: "/explores/getyourguide/fact_routing_experiment_cube.explore.lkml"
include: "/explores/getyourguide/fact_payment_attempt.explore.lkml"
include: "/dashboards/routing_experiment.dashboard.lookml"
include: "/dashboards/payments_cockpit.dashboard.lookml"
