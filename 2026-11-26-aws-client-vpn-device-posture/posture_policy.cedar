// Official-style Cedar device posture authorization policy for AWS Client VPN
// Attach first with --shadow-mode enabled, validate in CloudWatch Logs, then enforce.

permit(principal, action, resource)
when {
  context.crowdstrike.assessment.overall > 50
};

forbid(principal, action, resource)
when {
  context.crowdstrike.jailbroken == true
};
