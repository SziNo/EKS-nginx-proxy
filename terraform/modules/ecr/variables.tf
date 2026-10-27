variable "name_prefix" {
  description = "A repó nevek előtagja (pl. a cluster neve); a repók neve <előtag>/<szolgáltatás> lesz"
  type        = string

  # Az ECR repó név csak kisbetűt, számot és a . _ - / jeleket tartalmazhat
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*$", var.name_prefix))
    error_message = "Az előtag csak kisbetűt, számot és . _ - jeleket tartalmazhat, és betűvel vagy számmal kezdődjön."
  }
}

variable "repository_names" {
  description = "A szolgáltatások nevei; mindegyikből egy <előtag>/<név> repó lesz"
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
  description = "true esetén a repó akkor is törölhető, ha van benne image. Az alapérték a biztonságos false; aki törölhető repót akar, kérje kifejezetten (a root gyakorláshoz true-t ad át)."
  type        = bool
  default     = false
}

variable "scan_on_push" {
  description = "Sebezhetőségi szkennelés minden feltöltéskor"
  type        = bool
  default     = true
}