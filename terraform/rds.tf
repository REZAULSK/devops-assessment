# ---------------------------------------------------------------------------
# Database
#
# The brief does not mention a database. The application requires one: config.py
# declares DATABASE_URL with no default, and the app builds its schema during
# startup. Deploying without RDS produces a task that starts, fails, and is
# replaced forever.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.database[*].id

  tags = { Name = local.name }
}

# Alphanumeric on purpose. The password is embedded in a URL, and characters
# like `@`, `/` and `#` are URL delimiters — a password containing them produces
# a connection string that parses into the wrong host. 40 characters of
# alphanumeric is stronger than 20 characters of mixed symbols anyway.
resource "random_password" "database" {
  length  = 40
  special = false
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = "heroes"
  username = "hero"
  password = random_password.database.result

  allocated_storage     = 20
  max_allocated_storage = 50 # Storage autoscaling; avoids a disk-full outage.
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  # Single-AZ is a cost decision for a short-lived stack. Production would set
  # multi_az = true, which roughly doubles the instance cost and buys automatic
  # failover to a standby in the second AZ.
  multi_az = false

  backup_retention_period = 1
  skip_final_snapshot     = true # Assessment stacks must destroy cleanly.
  deletion_protection     = false
  apply_immediately       = true

  auto_minor_version_upgrade   = true
  performance_insights_enabled = false # Not free on t4g.micro beyond 7 days.

  # Slow queries and connection errors are the two things worth having in
  # CloudWatch before an incident rather than after one.
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = local.name }
}

# ---------------------------------------------------------------------------
# Connection string
#
# Stored as a secret and injected by ECS at task start, never as a plain
# environment variable in the task definition. Task definitions are readable by
# anyone with `ecs:DescribeTaskDefinition`, and they are retained as immutable
# revisions — a password placed there is effectively published permanently.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "database_url" {
  name = "${local.name}/database-url"

  # Assessment stacks are created and destroyed repeatedly. The default 30-day
  # recovery window would block re-creating a secret of the same name.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id

  secret_string = format(
    "postgresql+psycopg://%s:%s@%s/%s",
    aws_db_instance.main.username,
    random_password.database.result,
    aws_db_instance.main.endpoint,
    aws_db_instance.main.db_name,
  )
}
