# Számított és közös értékek, amelyeket a modulhívások használnak.
locals {
  # A két alkalmazás neve: ebből lesznek az ECR repók.
  # A scripts/build-push.sh ugyanezeket a neveket használja (külön, a saját ciklusában).
  services = ["service-a", "service-b"]
}