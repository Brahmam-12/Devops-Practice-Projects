resource "aws_s3_bucket" "s3" {
  count = var.bucket_count
  bucket = "${var.bucket_prefix}-${count.index+1}"
  tags = {
    "Name" = "${var.bucket_prefix}-${count.index+1}"
  }
}