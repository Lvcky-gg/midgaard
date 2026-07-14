package geo_cvulkan

import "core:dynlib"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

// vk_load_library opens libvulkan, resolves vkGetInstanceProcAddr, and wires
// both GLFW and the vendor wrapper so all Vulkan calls work.
vk_load_library :: proc() -> rawptr {
	lib, ok := dynlib.load_library("libvulkan.so.1")
	if !ok { panic("libvulkan.so.1 not found") }

	loader, found := dynlib.symbol_address(lib, "vkGetInstanceProcAddr")
	if !found { panic("vkGetInstanceProcAddr not found in libvulkan") }

	glfw.InitVulkanLoader(cast(vk.ProcGetInstanceProcAddr)loader)
	vk.load_proc_addresses_global(loader)
	return loader
}
