# Signing Profile
resource "aws_signer_signing_profile" "mediaconvert_signing_profile" {
  # name_prefix = "mediaconvert_signing_profile"
  platform_id = "AWSLambda-SHA384-ECDSA"
  signature_validity_period {
    value = 5
    type  = "YEARS"
  }
}

resource "aws_lambda_code_signing_config" "mediaconvert_signing_config" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.mediaconvert_signing_profile.version_arn]
  }
  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

resource "aws_signer_signing_job" "mediaconvert_build_signing_job" {
  profile_name = aws_signer_signing_profile.mediaconvert_signing_profile.name

  source {
    s3 {
      bucket  = aws_s3_bucket.mediaconvert-function-code.bucket
      key     = "convert_function.zip"
      version = aws_s3_object.mediaconvert-function-code-object.version_id
    }
  }

  destination {
    s3 {
      bucket = aws_s3_bucket.mediaconvert-function-code-signed.bucket
    }
  }

  ignore_signing_job_failure = true
  depends_on                 = [aws_lambda_function.mediaconvert-function]
}
