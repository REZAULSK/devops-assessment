# Both containers in the task write to this one log group, separated by stream
# prefix. Keeping them together means a single Logs Insights query can show an
# application error next to whatever the collector was doing at that moment.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
}

# A saved query is documentation that executes. This is the exact path the brief
# asks to demonstrate: take a trace id from X-Ray, land on the log lines for
# that one request.
resource "aws_cloudwatch_query_definition" "logs_for_trace" {
  name = "${local.name}/logs-for-a-trace-id"

  log_group_names = [aws_cloudwatch_log_group.app.name]

  query_string = <<-QUERY
    fields @timestamp, level, logger, message, trace_id, span_id, hero_id
    | filter trace_id = "PASTE-TRACE-ID-FROM-X-RAY"
    | sort @timestamp asc
  QUERY
}

# The reverse direction: find the slow or failing requests first, then carry
# their trace ids into X-Ray.
resource "aws_cloudwatch_query_definition" "recent_errors" {
  name = "${local.name}/recent-errors-with-trace-ids"

  log_group_names = [aws_cloudwatch_log_group.app.name]

  query_string = <<-QUERY
    fields @timestamp, level, logger, message, trace_id
    | filter level in ["ERROR", "WARNING"]
    | sort @timestamp desc
    | limit 50
  QUERY
}
