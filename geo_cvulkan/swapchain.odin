package geo_cvulkan

import glfw "vendor:glfw"
import vk "vendor:vulkan"

Vk_Swapchain :: struct {
	handle: vk.SwapchainKHR,
	format: vk.Format,
	extent: vk.Extent2D,
	images: []vk.Image,
	views:  []vk.ImageView,
}

vk_swapchain_create :: proc(ctx: ^Vk_Context, window: glfw.WindowHandle) -> Vk_Swapchain {
	caps: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &caps)

	fmt_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &fmt_count, nil)
	fmts := make([]vk.SurfaceFormatKHR, fmt_count)
	defer delete(fmts)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &fmt_count, raw_data(fmts))

	chosen := fmts[0]
	for f in fmts {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			chosen = f; break
		}
	}

	extent := caps.currentExtent
	if extent.width == ~u32(0) {
		w, h := glfw.GetFramebufferSize(window)
		extent = vk.Extent2D{width = u32(w), height = u32(h)}
	}

	img_count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && img_count > caps.maxImageCount {
		img_count = caps.maxImageCount
	}

	q_indices := [2]u32{ctx.queue_info.graphics_index, ctx.queue_info.present_index}
	sharing  := vk.SharingMode.EXCLUSIVE
	q_count  := u32(0)
	q_ptr:   [^]u32
	if ctx.queue_info.graphics_index != ctx.queue_info.present_index {
		sharing = .CONCURRENT
		q_count = 2
		q_ptr   = &q_indices[0]
	}

	ci := vk.SwapchainCreateInfoKHR{
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.surface,
		minImageCount    = img_count,
		imageFormat      = chosen.format,
		imageColorSpace  = chosen.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageSharingMode = sharing,
		queueFamilyIndexCount = q_count,
		pQueueFamilyIndices   = q_ptr,
		preTransform    = caps.currentTransform,
		compositeAlpha  = {.OPAQUE},
		presentMode     = .FIFO,
		clipped         = true,
	}
	sc: Vk_Swapchain
	if r := vk.CreateSwapchainKHR(ctx.device, &ci, nil, &sc.handle); r != .SUCCESS {
		panic("vkCreateSwapchainKHR failed")
	}
	sc.format = chosen.format
	sc.extent = extent

	total: u32
	vk.GetSwapchainImagesKHR(ctx.device, sc.handle, &total, nil)
	sc.images = make([]vk.Image, total)
	vk.GetSwapchainImagesKHR(ctx.device, sc.handle, &total, raw_data(sc.images))

	sc.views = make([]vk.ImageView, total)
	for i in 0..<int(total) {
		vi := vk.ImageViewCreateInfo{
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = sc.images[i],
			viewType = .D2,
			format   = sc.format,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		if r := vk.CreateImageView(ctx.device, &vi, nil, &sc.views[i]); r != .SUCCESS {
			panic("vkCreateImageView failed")
		}
	}
	return sc
}

vk_swapchain_destroy :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain) {
	for v in sc.views { vk.DestroyImageView(ctx.device, v, nil) }
	vk.DestroySwapchainKHR(ctx.device, sc.handle, nil)
	delete(sc.images)
	delete(sc.views)
}
