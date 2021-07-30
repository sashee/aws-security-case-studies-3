provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_s3_bucket" "production" {
  force_destroy = "true"
}

resource "aws_s3_bucket" "dev" {
  force_destroy = "true"
}

resource "aws_s3_bucket_object" "secret_file" {
  key     = "secret.txt"
  bucket  = aws_s3_bucket.production.bucket
  content = "production secret"
}

# the lambda code
data "archive_file" "lambda_zip_inline" {
  type        = "zip"
  output_path = "/tmp/lambda-${random_id.id.hex}.zip"
  source {
    content  = <<EOF
const AWS = require("aws-sdk");
module.exports.handler = async (event, context) => {
	const s3 = new AWS.S3();
	const bucket = process.env.BUCKET;
	const contents = await s3.listObjectsV2({Bucket: bucket}).promise();
	return contents;
};
EOF
    filename = "main.js"
  }
}

resource "aws_iam_role" "production" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "production_permissions" {
  statement {
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.production.arn,
      "${aws_s3_bucket.production.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "production_role_policy" {
  role   = aws_iam_role.production.id
  policy = data.aws_iam_policy_document.production_permissions.json
}

resource "aws_iam_role" "dev" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "dev_permissions" {
  statement {
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.dev.arn,
      "${aws_s3_bucket.dev.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "dev_role_policy" {
  role   = aws_iam_role.dev.id
  policy = data.aws_iam_policy_document.dev_permissions.json
}

resource "aws_lambda_function" "production" {
  function_name    = "function-${random_id.id.hex}"
  filename         = data.archive_file.lambda_zip_inline.output_path
  source_code_hash = data.archive_file.lambda_zip_inline.output_base64sha256
  handler          = "main.handler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.production.arn
  environment {
    variables = {
      BUCKET = aws_s3_bucket.production.bucket
    }
  }
}

resource "aws_lambda_function" "dev" {
  function_name    = "function-dev-${random_id.id.hex}"
  filename         = data.archive_file.lambda_zip_inline.output_path
  source_code_hash = data.archive_file.lambda_zip_inline.output_base64sha256
  handler          = "main.handler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.dev.arn
  environment {
    variables = {
      BUCKET = aws_s3_bucket.dev.bucket
    }
  }
}

# tester user
resource "aws_iam_user" "user" {
  name          = "user-${random_id.id.hex}"
  force_destroy = "true"
}

resource "aws_iam_access_key" "user-keys" {
  user = aws_iam_user.user.name
}

resource "aws_iam_user_policy" "user_permissions" {
  user = aws_iam_user.user.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "NotAction": [
        "lambda:GetFunction",
				"lambda:InvokeFunction"
      ],
      "Effect": "Deny",
      "Resource": "${aws_lambda_function.production.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_user_policy_attachment" "lambda-full-access" {
  user       = aws_iam_user.user.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
}

output "production_lambda_arn" {
  value = aws_lambda_function.production.arn
}

output "dev_lambda_arn" {
  value = aws_lambda_function.dev.arn
}

output "production_bucket" {
  value = aws_s3_bucket.production.bucket
}

output "secret" {
  value = aws_s3_bucket_object.secret_file.id
}

output "access_key_id" {
  value = aws_iam_access_key.user-keys.id
}
output "secret_access_key" {
  value     = aws_iam_access_key.user-keys.secret
  sensitive = true
}
