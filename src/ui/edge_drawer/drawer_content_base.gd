class_name DrawerContentBase extends Control
## Base class for all edge drawer content nodes.
## Every drawer content must extend this and implement all methods.

signal request_close()


func on_drawer_opened() -> void:
	pass


func on_drawer_closed() -> void:
	pass


## Return true if this content wants to handle ESC itself (e.g. while a rename edit is active).
func wants_escape_handled() -> bool:
	return false


## Handle the ESC key. Return true if ESC was consumed (drawer stays open), false to let the drawer close.
func handle_escape() -> bool:
	return false
