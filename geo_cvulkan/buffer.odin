package geo_cvulkan

import "core:mem"
import vk "vendor:vulkan"

Vk_Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
}

// vk_buffer_upload creates a host-visible buffer and copies data into it.
vk_buffer_upload :: proc(ctx: ^Vk_Context, size: vk.DeviceSize, usage: vk.BufferUsageFlags, data: rawptr) -> Vk_Buffer {
	ci := vk.BufferCreateInfo{
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	buf: Vk_Buffer
	if r := vk.CreateBuffer(ctx.device, &ci, nil, &buf.handle); r != .SUCCESS {
		panic("vkCreateBuffer failed")
	}

	req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buf.handle, &req)

	ai := vk.MemoryAllocateInfo{
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = _find_memory_type(ctx.physical_device, req.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT}),
	}
	if r := vk.AllocateMemory(ctx.device, &ai, nil, &buf.memory); r != .SUCCESS {
		panic("vkAllocateMemory failed")
	}
	vk.BindBufferMemory(ctx.device, buf.handle, buf.memory, 0)

	mapped: rawptr
	vk.MapMemory(ctx.device, buf.memory, 0, size, {}, &mapped)
	mem.copy_non_overlapping(mapped, data, int(size))
	vk.UnmapMemory(ctx.device, buf.memory)

	return buf
}

vk_buffer_destroy :: proc(ctx: ^Vk_Context, buf: ^Vk_Buffer) {
	if buf.handle != 0 {
		vk.DestroyBuffer(ctx.device, buf.handle, nil)
		vk.FreeMemory(ctx.device, buf.memory, nil)
		buf.handle = 0
	}
}

_find_memory_type :: proc(physical: vk.PhysicalDevice, filter: u32, props: vk.MemoryPropertyFlags) -> u32 {
	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical, &mem_props)
	for i := u32(0); i < mem_props.memoryTypeCount; i += 1 {
		if (filter & (1<<i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & props) == props {
			return i
		}
	}
	panic("no suitable memory type")
}
