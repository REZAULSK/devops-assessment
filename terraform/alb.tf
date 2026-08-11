resource "aws_lb" "main" {
  name               = local.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  enable_deletion_protection = false # Must stay false for clean teardown.

  tags = { Name = local.name }
}

resource "aws_lb_target_group" "app" {
  # name_prefix rather than a fixed name: combined with create_before_destroy
  # below, a fixed name would collide with itself during replacement and the
  # apply would fail. (AWS caps this prefix at six characters.)
  name_prefix = "hero-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate tasks are registered by ENI address, not instance.

  health_check {
    path     = "/health"
    matcher  = "200"
    protocol = "HTTP"

    # Two consecutive successes to enter service, three failures to leave it.
    # Asymmetric on purpose: quick to admit a healthy task, slow to evict one
    # over a single blip.
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  # Long enough for in-flight requests to finish during a rolling deploy, short
  # enough that a deploy is not held open by idle connections.
  deregistration_delay = 30

  # Replacing a target group while a listener references it needs the new one to
  # exist first.
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = local.name }
}

# HTTP only.
#
# TLS terminates at the ALB in any real deployment, using an ACM certificate for
# a domain the account controls, with port 80 redirecting to 443. No domain is
# available for this assessment, so that listener is not created rather than
# faked with a self-signed certificate an ALB would not accept anyway.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
