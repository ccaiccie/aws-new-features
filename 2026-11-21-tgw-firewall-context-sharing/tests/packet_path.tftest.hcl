mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["us-east-1a", "us-east-1b"]
      zone_ids = ["use1-az1", "use1-az2"]
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      insecure_value = "ami-0123456789abcdef0"
    }
  }
}

run "isolated_bidirectional_lab" {
  command = plan

  assert {
    condition = (
      aws_ec2_transit_gateway.this.default_route_table_association == "disable" &&
      aws_ec2_transit_gateway.this.default_route_table_propagation == "disable" &&
      length(aws_ec2_transit_gateway_route_table_association.spoke) == 2 &&
      length(aws_route_table_association.spoke) == 4
    )
    error_message = "Spokes must have explicit subnet and TGW associations with no default TGW bypass."
  }

  assert {
    condition = (
      toset([for route in aws_ec2_transit_gateway_route.inspect : route.destination_cidr_block]) == toset([var.dev_vpc_cidr, var.prod_vpc_cidr]) &&
      toset([for route in aws_ec2_transit_gateway_route.deliver : route.destination_cidr_block]) == toset([var.dev_vpc_cidr, var.prod_vpc_cidr]) &&
      aws_route.peer_via_tgw["dev"].destination_cidr_block == var.prod_vpc_cidr &&
      aws_route.peer_via_tgw["prod"].destination_cidr_block == var.dev_vpc_cidr
    )
    error_message = "Both directions need a remote VPC route and a match in each TGW route table."
  }

  assert {
    condition = (
      !aws_instance.client.associate_public_ip_address &&
      !aws_instance.server.associate_public_ip_address &&
      !aws_ec2_instance_connect_endpoint.dev.preserve_client_ip &&
      toset(keys(aws_cloudwatch_log_group.firewall)) == toset(["FLOW", "ALERT"])
    )
    error_message = "The two test hosts must remain private and both firewall log types must be configured."
  }
}
