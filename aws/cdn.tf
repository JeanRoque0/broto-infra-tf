variable "cloudfront_public_key_pem" {
  type        = string
  description = "RSA-2048 public PEM only. Keep the matching private key in the application secret, never Terraform/state."
  validation {
    condition     = can(regex("-----BEGIN PUBLIC KEY-----", var.cloudfront_public_key_pem)) && !strcontains(var.cloudfront_public_key_pem, "PRIVATE")
    error_message = "Provide only an RSA public key in PEM format."
  }
}
resource "aws_cloudfront_public_key" "photos" {
  name        = "${var.name}-photos"
  encoded_key = var.cloudfront_public_key_pem
}
resource "aws_cloudfront_key_group" "photos" {
  name  = "${var.name}-photos"
  items = [aws_cloudfront_public_key.photos.id]
}
resource "aws_cloudfront_origin_access_control" "photos" {
  name                              = "${var.name}-photos"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_cache_policy" "photos" {
  name        = "${var.name}-photos"
  min_ttl     = 0
  default_ttl = 300
  max_ttl     = 300
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}
resource "aws_cloudfront_distribution" "photos" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Private Broto photos; signed URLs only"
  price_class     = "PriceClass_All" # Includes Brazilian edge locations.
  http_version    = "http2and3"
  origin {
    domain_name              = aws_s3_bucket.photos.bucket_regional_domain_name
    origin_id                = "photos-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.photos.id
  }
  default_cache_behavior {
    target_origin_id           = "photos-s3"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    trusted_key_groups         = [aws_cloudfront_key_group.photos.id]
    cache_policy_id            = aws_cloudfront_cache_policy.photos.id
    compress                   = false
    response_headers_policy_id = aws_cloudfront_response_headers_policy.photos.id
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = 0
  }
}
resource "aws_cloudfront_response_headers_policy" "photos" {
  name = "${var.name}-photos"
  cors_config {
    access_control_allow_credentials = false
    access_control_allow_headers { items = ["*"] }
    access_control_allow_methods { items = ["GET", "HEAD"] }
    access_control_allow_origins { items = split(",", var.cors_origins) }
    origin_override = true
  }
  security_headers_config {
    content_type_options { override = true }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      override                   = true
    }
  }
  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = "private, no-store"
      override = true
    }
  }
}
output "photos_cdn_url" { value = "https://${aws_cloudfront_distribution.photos.domain_name}" }
output "photos_cdn_key_id" { value = aws_cloudfront_public_key.photos.id }
