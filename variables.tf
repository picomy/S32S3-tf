variable "DataSetName" {
  type        = string
  description = "Your Dataset Name, this name will be used to distinguish the task uniquey."
}

variable "vpcID" {
  type        = string
  description = "Which VPC do you deploy ECS Task into?"
}

variable "subnetIDs" {
  type        = list(string)
  description = "Which VPC do you deploy ECS Task into?"
}

variable "securityGroups" {
  type        = list(any)
  description = "The security group will be attached with lambda,ecs task"
}
