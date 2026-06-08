# cloudfront.tf
# ├── CloudFront Distribution
# ├── Origin Access Control (S3 직접 접근 차단)
# └── S3 버킷 (장애 대응 프로세스 자산화)

# ─── 1. S3 버킷 (정적 자산 + 장애 대응 자산화) ───────────────────
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.project_name}-assets" }
}

# 현재 AWS 계정 ID 조회 (버킷 이름 중복 방지)
data "aws_caller_identity" "current" {}

# 퍼블릭 접근 완전 차단 (CloudFront OAC로만 접근)
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 버킷 버전 관리 (자산 이력 보존)
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─── 2. Origin Access Control (S3 직접 접근 차단) ─────────────────
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 버킷 정책: CloudFront OAC만 접근 허용
resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.assets.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

# ─── 3. CloudFront Distribution ───────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} CloudFront"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"  # 미국, 유럽, 아시아 (한국 포함)
  aliases             = ["www.${var.domain_name}", var.domain_name]

  # ── Origin 1: ALB (동적 요청) ──────────────────────────────────
  origin {
    domain_name = aws_lb.web_alb.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"  # ALB → HTTPS만 허용
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Origin 2: S3 (정적 자산) ───────────────────────────────────
  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ── Cache Behavior 1: 정적 자산 (S3) ──────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # 정적 자산: 7일 캐싱
    min_ttl     = 0
    default_ttl = 604800   # 7일
    max_ttl     = 31536000 # 1년
  }

  # ── Cache Behavior 2: API 요청 (캐싱 비활성화) ────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host", "Origin"]
      cookies { forward = "all" }
    }

    # API: 캐싱 없음
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ── Default Cache Behavior: ALB (동적 요청) ────────────────────
  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto"]
      cookies { forward = "all" }
    }

    min_ttl     = 0
    default_ttl = 60   # 1분
    max_ttl     = 3600 # 1시간
  }

  # ── ACM 인증서 (us-east-1 필수) ───────────────────────────────
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cf_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ── 지역 제한 없음 ─────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ── 커스텀 에러 페이지 ─────────────────────────────────────────
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"  # SPA 라우팅 지원
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  tags = { Name = "${var.project_name}-cf" }

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

# ─── 4. ACM 인증서 (CloudFront는 반드시 us-east-1) ───────────────
data "aws_acm_certificate" "cf_cert" {
  provider    = aws.us_east_1   # ← 별도 provider 필요
  domain      = "${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# ─── 5. Route53 레코드 업데이트 (ALB → CloudFront) ───────────────
# loadbalancer.tf의 www 레코드를 CloudFront로 교체
resource "aws_route53_record" "cf_www" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false  # CloudFront는 false 권장
  }
}

resource "aws_route53_record" "cf_root" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

