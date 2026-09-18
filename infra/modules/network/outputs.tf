output "host_subnet_id" { value = azurerm_subnet.hosts.id }
output "endpoint_subnet_id" { value = azurerm_subnet.endpoints.id }
output "file_dns_zone_id" { value = azurerm_private_dns_zone.files.id }
output "ready" {
  value      = azurerm_virtual_network.avd.id
  depends_on = [azurerm_subnet_nat_gateway_association.hosts, azurerm_nat_gateway_public_ip_association.egress, azurerm_subnet_network_security_group_association.hosts, azurerm_private_dns_zone_virtual_network_link.files]
}
