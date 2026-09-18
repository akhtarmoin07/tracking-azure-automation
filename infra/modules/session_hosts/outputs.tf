output "hosts" { value = { for key, vm in azurerm_windows_virtual_machine.host : key => { name = vm.name, id = vm.id } } }
output "host_ids" { value = { for key, vm in azurerm_windows_virtual_machine.host : key => vm.id } }
