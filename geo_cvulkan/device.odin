package geo_cvulkan

import glfw "vendor:glfw"
import vk "vendor:vulkan"

Queue_Info :: struct {
	graphics_index: u32,
	present_index:  u32,
}

Vk_Context :: struct {
	instance:        vk.Instance,
	surface:         vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	device:          vk.Device,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
	queue_info:      Queue_Info,
}

vk_context_create :: proc(window: glfw.WindowHandle, loader: rawptr) -> Vk_Context {
	ctx: Vk_Context
	_create_instance(&ctx)
	vk.load_proc_addresses_instance(ctx.instance)

	if r := glfw.CreateWindowSurface(ctx.instance, window, nil, &ctx.surface); r != .SUCCESS {
		panic("Vulkan surface creation failed")
	}
	_select_physical_device(&ctx)
	_create_device(&ctx)
	return ctx
}

vk_context_destroy :: proc(ctx: ^Vk_Context) {
	vk.DestroyDevice(ctx.device, nil)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	vk.DestroyInstance(ctx.instance, nil)
}

// ── internals ────────────────────────────────────────────────────────────────

_create_instance :: proc(ctx: ^Vk_Context) {
	exts := glfw.GetRequiredInstanceExtensions()
	info := vk.ApplicationInfo{
		sType            = .APPLICATION_INFO,
		pApplicationName = "Midgaard",
		apiVersion       = vk.API_VERSION_1_0,
	}
	ci := vk.InstanceCreateInfo{
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &info,
		enabledExtensionCount   = u32(len(exts)),
		ppEnabledExtensionNames = raw_data(exts),
	}
	if r := vk.CreateInstance(&ci, nil, &ctx.instance); r != .SUCCESS {
		panic("vkCreateInstance failed")
	}
}

_select_physical_device :: proc(ctx: ^Vk_Context) {
	count: u32
	vk.EnumeratePhysicalDevices(ctx.instance, &count, nil)
	devs := make([]vk.PhysicalDevice, count)
	vk.EnumeratePhysicalDevices(ctx.instance, &count, raw_data(devs))

	for d in devs {
		if info, ok := _find_queues(d, ctx.surface); ok {
			ctx.physical_device = d
			ctx.queue_info = info
			delete(devs)
			return
		}
	}
	delete(devs)
	panic("no suitable Vulkan GPU found")
}

_find_queues :: proc(dev: vk.PhysicalDevice, surf: vk.SurfaceKHR) -> (Queue_Info, bool) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(dev, &count, nil)
	props := make([]vk.QueueFamilyProperties, count)
	defer delete(props)
	vk.GetPhysicalDeviceQueueFamilyProperties(dev, &count, raw_data(props))

	qi := Queue_Info{graphics_index = ~u32(0), present_index = ~u32(0)}
	for i := u32(0); i < count; i += 1 {
		if .GRAPHICS in props[i].queueFlags { qi.graphics_index = i }
		can_present: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(dev, i, surf, &can_present)
		if can_present { qi.present_index = i }
		if qi.graphics_index != ~u32(0) && qi.present_index != ~u32(0) {
			return qi, true
		}
	}
	return {}, false
}

_create_device :: proc(ctx: ^Vk_Context) {
	prio := [1]f32{1.0}
	q_infos := [2]vk.DeviceQueueCreateInfo{
		{sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = ctx.queue_info.graphics_index, queueCount = 1, pQueuePriorities = &prio[0]},
		{sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = ctx.queue_info.present_index,  queueCount = 1, pQueuePriorities = &prio[0]},
	}
	q_count := u32(2)
	if ctx.queue_info.graphics_index == ctx.queue_info.present_index { q_count = 1 }

	feats := vk.PhysicalDeviceFeatures{largePoints = true}
	exts  := [1]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	ci := vk.DeviceCreateInfo{
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = q_count,
		pQueueCreateInfos       = &q_infos[0],
		enabledExtensionCount   = 1,
		ppEnabledExtensionNames = &exts[0],
		pEnabledFeatures        = &feats,
	}
	if r := vk.CreateDevice(ctx.physical_device, &ci, nil, &ctx.device); r != .SUCCESS {
		panic("vkCreateDevice failed")
	}
	vk.load_proc_addresses_device(ctx.device)
	vk.GetDeviceQueue(ctx.device, ctx.queue_info.graphics_index, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(ctx.device, ctx.queue_info.present_index,  0, &ctx.present_queue)
}
