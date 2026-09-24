# GitLab on OpenShift (Lightwell demo)
#
# Two install modes (setup script):
#   LIGHTWELL_GITLAB_MODE=omnibus  (default) — single gitlab/gitlab-ce Deployment + Runner
#   LIGHTWELL_GITLAB_MODE=helm     — official gitlab/gitlab Helm chart + chart runner
#
# Files:
#   values-demo.yaml  — Helm values (CE, OpenShift Routes, reduced memory)
#   omnibus.yaml      — Omnibus Deployment, Route, Runner skeleton
#
# See ../../GITLAB-OPENSHIFT.md
