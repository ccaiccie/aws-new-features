# ---------------------------------------------------------------- Optional: Network Synthetic Monitor (active probes)
# Performance Monitor sends no probes. For hybrid paths, Network Synthetic Monitor sends ICMP echo
# or TCP SYN probes from a subnet to on-premises addresses and publishes round-trip time and
# packet loss, plus a network health indicator (NHI) for paths through Direct Connect.
# Only useful if this VPC can actually reach the on-premises address (DX or VPN), which this lab does not build.
resource "aws_networkmonitor_monitor" "hybrid" {
  count              = var.onprem_probe_destination != "" ? 1 : 0
  monitor_name       = "${var.name_prefix}-hybrid"
  aggregation_period = 60
}

resource "aws_networkmonitor_probe" "icmp" {
  count        = var.onprem_probe_destination != "" ? 1 : 0
  monitor_name = aws_networkmonitor_monitor.hybrid[0].monitor_name
  source_arn   = aws_subnet.client.arn
  destination  = var.onprem_probe_destination
  protocol     = "ICMP"
}
