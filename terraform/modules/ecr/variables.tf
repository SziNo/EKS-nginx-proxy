variable "repository_names" {
  description = "A létrehozandó ECR repók nevei (mindegyikből egy repó lesz)"
  type        = set(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE: ugyanaz a tag felülírható; IMMUTABLE: egy tag csak egyszer tölthető fel"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Csak MUTABLE vagy IMMUTABLE lehet."
  }
}

variable "force_delete" {
  description = "true esetén a repó akkor is törölhető, ha van benne image"
  type        = bool
  default     = true
}

variable "scan_on_push" {
  description = "Sebezhetőségi szkennelés minden feltöltéskor"
  type        = bool
  default     = true
}
