terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "iam/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "company-terraform-state-locks"
  }
}

provider "aws" { region = var.region }

# IAM role for Jenkins to push images to ECR and update EKS
resource "aws_iam_user" "jenkins" {
  name = "jenkins-ci"
  tags = { Purpose = "Jenkins CI/CD pipeline" }
}

resource "aws_iam_user_policy" "jenkins_ecr" {
  name = "jenkins-ecr-access"
  user = aws_iam_user.jenkins.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
                    "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload", "ecr:PutImage"]
        Resource = "*"
      }
    ]
  })
}


# ─── IAM POLICY: Cluster Autoscaler ──────────────────────────────────────────
# Cluster Autoscaler is a pod running INSIDE the cluster.
# It needs to call AWS APIs to scale the node group up and down.
# This policy gives it exactly those permissions — nothing more.
#
# HOW IT CONNECTS TO THE POD:
#   This policy is attached to the EKS node instance role.
#   Every node (EC2) has this role → every pod on that node can call these APIs.
#   (A more secure approach is IRSA — IAM Roles for Service Accounts —
#    but node-level attachment is simpler and fine for a single-cluster setup.)
#
# WHAT CLUSTER AUTOSCALER DOES WITH THESE PERMISSIONS:
#   Describe*  → reads current ASG state, how many nodes exist, what their tags are
#   SetDesiredCapacity → the actual scale-up/scale-down call (changes node count)
#   TerminateInstance  → removes a specific node when scaling down
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "ClusterAutoscalerPolicy"
  description = "Allows Cluster Autoscaler pod to scale EKS node groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # READ permissions — describe the current state of the ASG and nodes
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",     # see all node groups
          "autoscaling:DescribeAutoScalingInstances",  # see individual nodes
          "autoscaling:DescribeLaunchConfigurations",  # see node launch config
          "autoscaling:DescribeScalingActivities",     # see recent scale events
          "autoscaling:DescribeTags",                  # find node group by tags
          "ec2:DescribeLaunchTemplateVersions",        # read node launch template
          "ec2:DescribeInstanceTypes"                  # know node capacity
        ]
        Resource = "*"
      },
      {
        # WRITE permissions — actually scale the node group
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",              # scale up: desired = 3, scale down: desired = 1
          "autoscaling:TerminateInstanceInAutoScalingGroup"  # remove a specific node when scaling down
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach Cluster Autoscaler policy to the EKS node group instance role.
# The node group role name follows the EKS module naming convention.
# If your cluster name changes, update the role name here to match.
resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = "microservices-eks-default-node-group-role"   # EKS node group IAM role
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

variable "region" { default = "us-east-1" }

output "jenkins_user_arn"           { value = aws_iam_user.jenkins.arn }
output "cluster_autoscaler_policy"  { value = aws_iam_policy.cluster_autoscaler.arn }
