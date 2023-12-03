locals {
  protocols = {
    icmp = 1
    tcp  = 6
    udp  = 17
    all  = "all"
  }
}

locals {
  // map the network_security_groups into an array of all rules flattened
  /*
  from:
    {"group-1" = {"rule-1" = { ips = [1, 2], port=22, ...}}, ....}
  To:
    [{group = "group-1", rulename= "rule-1", port = 22, ip = 1}, {group = "group-1", rulename= "rule-1", port = 22, ip = 2} ]
  */
  flatten_rules_ip = flatten([
    for group, rules in var.network_security_groups : [
      for rulename, rule in rules : [
        for ip in rule.ips : {
          group     = group
          rulename  = rulename
          direction = rule.direction
          protocol  = rule.protocol
          ports     = rule.ports
          ip        = can(rule.ip) ? rule.ip : ""
          #   for ip in data.oci_core_private_ips.primary_vnic_primary_private_ip[each.value.instance_key].private_ips
        }
      ]
    ]
  ])
  flatten_rules_nsg = flatten([
    for group, rules in var.network_security_groups : [
      for rulename, rule in rules : {
        group            = group
        rulename         = rulename
        direction        = rule.direction
        protocol         = rule.protocol
        ports            = rule.ports
        source_type      = can(rule.source_type) ? rule.source_type : null
        destination_type = can(rule.destination_type) ? rule.destination_type : null
        nsg              = rule.nsg
      }
    ]
  ])
}

// Create a group
resource "oci_core_network_security_group" "security_group" {
  for_each = var.network_security_groups

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "Security group for ${each.key}"
}

// Create INGRESS rules
resource "oci_core_network_security_group_security_rule" "ingress_rule" {
  for_each = { for rule in "${local.flatten_rules_nsg.source_type == "NETWORK_SECURITY_GROUP" || local.flatten_rules_nsg.destination_type == "NETWORK_SECURITY_GROUP" ? local.flatten_rules_nsg : local.flatten_rules_ip}" :
    rule.direction == "INGRESS" && rule.source_type == "NETWORK_SECURITY_GROUP" ?
    "${rule.group}:${rule.rulename}:${rule.direction}:${rule.nsg}:${rule.ports.min}:${rule.ports.max}" :
  "${rule.group}:${rule.rulename}:${rule.direction}:${rule.ip}:${rule.ports.min}:${rule.ports.max}" => rule }

  network_security_group_id = oci_core_network_security_group.security_group[each.value.group].id
  direction                 = "INGRESS"
  protocol                  = lookup(local.protocols, each.value.protocol)
  description               = each.value.rulename
  stateless                 = false
  source_type               = coalesce(each.value.source_type, "CIDR_BLOCK") # use CIDR_BLOCK as default option
  source                    = each.value.source_type == "CIDR_BLOCK" ? each.value.ip : each.value.nsg

  dynamic "tcp_options" {
    for_each = each.value.protocol == "tcp" ? [each.value.ports] : []
    content {
      destination_port_range {
        max = tcp_options.value.max
        min = tcp_options.value.min
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "udp" ? [each.value.ports] : []
    content {
      destination_port_range {
        max = udp_options.value.max
        min = udp_options.value.min
      }
    }
  }
}

// Create EGRESS rules
resource "oci_core_network_security_group_security_rule" "egress_rule" {
  for_each = { for rule in "${local.flatten_rules_nsg.destination_type == "NETWORK_SECURITY_GROUP" || local.flatten_rules_nsg.source_type == "NETWORK_SECURITY_GROUP" ? local.flatten_rules_nsg : local.flatten_rules_ip}" :
    rule.direction == "EGRESS" && rule.destination_type == "NETWORK_SECURITY_GROUP" ?
    "${rule.group}:${rule.rulename}:${rule.direction}:${rule.nsg}:${rule.ports.min}:${rule.ports.max}" :
  "${rule.group}:${rule.rulename}:${rule.direction}:${rule.ip}:${rule.ports.min}:${rule.ports.max}" => rule }

  network_security_group_id = oci_core_network_security_group.security_group[each.value.group].id
  direction                 = "EGRESS"
  protocol                  = lookup(local.protocols, each.value.protocol)
  description               = each.value.rulename
  stateless                 = false
  destination_type          = coalesce(each.value.destination_type, "CIDR_BLOCK") # use CIDR_BLOCK as default option
  destination               = each.value.source_type == "CIDR_BLOCK" ? each.value.ip : each.value.nsg


  dynamic "tcp_options" {
    for_each = each.value.protocol == "tcp" ? [each.value.ports] : []
    content {
      destination_port_range {
        max = tcp_options.value.max
        min = tcp_options.value.min
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "udp" ? [each.value.ports] : []
    content {
      destination_port_range {
        max = udp_options.value.max
        min = udp_options.value.min
      }
    }
  }
}
