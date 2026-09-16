resource "aws_lb" "api" {
  name                       = var.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  idle_timeout               = 180
  enable_http2               = true
}
resource "aws_lb_target_group" "api" {
  name                 = var.name
  vpc_id               = aws_vpc.main.id
  target_type          = "instance"
  protocol             = "HTTP"
  port                 = 8080
  deregistration_delay = 100
  health_check {
    path                = "/readyz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
locals {
  public_url = var.api_domain != "" ? "https://${var.api_domain}" : "http://${aws_lb.api.dns_name}"
}
resource "aws_lb_listener" "https" {
  count             = var.origin_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.origin_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"
  dynamic "default_action" {
    for_each = var.origin_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
  dynamic "default_action" {
    for_each = var.origin_certificate_arn == "" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "application/json"
        status_code  = "503"
        message_body = "{\"error\":\"https_configuration_pending\"}"
      }
    }
  }
}
resource "aws_lb_listener_rule" "bootstrap_health" {
  count        = var.origin_certificate_arn == "" ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    path_pattern { values = ["/livez", "/readyz", "/healthz"] }
  }
  condition {
    http_request_method { values = ["GET", "HEAD"] }
  }
}
