# GitLab on OpenShift (Lightwell demo)
#
# Customer setup (any GitLab): ../../GITLAB.md
# Kit deploy / this cluster:   ../../GITLAB-OPENSHIFT.md
#
# Two install modes (setup script):
#   LIGHTWELL_GITLAB_MODE=omnibus  (default) — single gitlab/gitlab-ce Deployment + Runner
#   LIGHTWELL_GITLAB_MODE=helm     — official gitlab/gitlab Helm chart + chart runner
#
# Files:
#   values-demo.yaml  — Helm values (CE, OpenShift Routes, reduced memory)
#   omnibus.yaml      — Omnibus Deployment, Route, Runner skeleton
#
# Note: omnibus uses emptyDir. Re-applying the Deployment template recreates the
# pod and wipes GitLab data — prefer patching Role/ConfigMap only when possible.
