package geo_cvulkan

import "core:bytes"
import "core:image"
import _ "core:image/jpeg"
import _ "core:image/png"
import vk "vendor:vulkan"

Vk_Texture :: struct {
	image:   vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	sampler: vk.Sampler,
	ready:   bool,
}

// vk_texture_create_from_file creates a sampled RGBA8 texture from an image path.
// If decoding/loading fails, it creates a 1x1 fallback texel.
vk_texture_create_from_file :: proc(ctx: ^Vk_Context, path: string) -> Vk_Texture {
	img, err := image.load_from_file(path, allocator = context.allocator)
	if err != nil || img == nil {
		fallback := [4]u8{26, 48, 74, 255}
		return _create_texture_rgba8(ctx, 1, 1, fallback[:])
	}
	defer image.destroy(img)

	rgba := _to_rgba8(img)
	defer delete(rgba)

	if len(rgba) == 0 {
		fallback := [4]u8{26, 48, 74, 255}
		return _create_texture_rgba8(ctx, 1, 1, fallback[:])
	}
	return _create_texture_rgba8(ctx, img.width, img.height, rgba)
}

vk_texture_destroy :: proc(ctx: ^Vk_Context, t: ^Vk_Texture) {
	if t.view != 0 {
		vk.DestroyImageView(ctx.device, t.view, nil)
		t.view = 0
	}
	if t.sampler != 0 {
		vk.DestroySampler(ctx.device, t.sampler, nil)
		t.sampler = 0
	}
	if t.image != 0 {
		vk.DestroyImage(ctx.device, t.image, nil)
		t.image = 0
	}
	if t.memory != 0 {
		vk.FreeMemory(ctx.device, t.memory, nil)
		t.memory = 0
	}
	t.ready = false
}

_to_rgba8 :: proc(img: ^image.Image) -> []u8 {
	if img.depth != 8 { return nil }

	src := bytes.buffer_to_bytes(&img.pixels)
	count := img.width * img.height
	out := make([]u8, count*4)

	switch img.channels {
	case 4:
		copy(out, src)
	case 3:
		for i in 0..<count {
			s := i * 3
			d := i * 4
			out[d+0] = src[s+0]
			out[d+1] = src[s+1]
			out[d+2] = src[s+2]
			out[d+3] = 255
		}
	case 1:
		for i in 0..<count {
			v := src[i]
			d := i * 4
			out[d+0] = v
			out[d+1] = v
			out[d+2] = v
			out[d+3] = 255
		}
	case 2:
		for i in 0..<count {
			s := i * 2
			d := i * 4
			v := src[s+0]
			out[d+0] = v
			out[d+1] = v
			out[d+2] = v
			out[d+3] = src[s+1]
		}
	case:
		delete(out)
		return nil
	}
	return out
}

_create_texture_rgba8 :: proc(ctx: ^Vk_Context, width, height: int, rgba: []u8) -> Vk_Texture {
	t: Vk_Texture

	staging := vk_buffer_upload(ctx,
		vk.DeviceSize(len(rgba)),
		{.TRANSFER_SRC},
		raw_data(rgba))
	defer vk_buffer_destroy(ctx, &staging)

	img_ci := vk.ImageCreateInfo{
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = .R8G8B8A8_SRGB,
		extent        = {width = u32(width), height = u32(height), depth = 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = {.TRANSFER_DST, .SAMPLED},
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if r := vk.CreateImage(ctx.device, &img_ci, nil, &t.image); r != .SUCCESS {
		return t
	}

	req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, t.image, &req)
	alloc := vk.MemoryAllocateInfo{
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = _find_memory_type(ctx.physical_device, req.memoryTypeBits, {.DEVICE_LOCAL}),
	}
	if r := vk.AllocateMemory(ctx.device, &alloc, nil, &t.memory); r != .SUCCESS {
		vk.DestroyImage(ctx.device, t.image, nil)
		t.image = 0
		return t
	}
	vk.BindImageMemory(ctx.device, t.image, t.memory, 0)

	_copy_staging_to_image(ctx, staging.handle, t.image, u32(width), u32(height))

	view_ci := vk.ImageViewCreateInfo{
		sType      = .IMAGE_VIEW_CREATE_INFO,
		image      = t.image,
		viewType   = .D2,
		format     = .R8G8B8A8_SRGB,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	if r := vk.CreateImageView(ctx.device, &view_ci, nil, &t.view); r != .SUCCESS {
		vk_texture_destroy(ctx, &t)
		return t
	}

	samp_ci := vk.SamplerCreateInfo{
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .LINEAR,
		addressModeU = .REPEAT,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxAnisotropy = 1,
		minLod       = 0,
		maxLod       = 0,
	}
	if r := vk.CreateSampler(ctx.device, &samp_ci, nil, &t.sampler); r != .SUCCESS {
		vk_texture_destroy(ctx, &t)
		return t
	}

	t.ready = true
	return t
}

_copy_staging_to_image :: proc(ctx: ^Vk_Context, src: vk.Buffer, dst: vk.Image, width, height: u32) {
	pool_ci := vk.CommandPoolCreateInfo{
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT},
		queueFamilyIndex = ctx.queue_info.graphics_index,
	}
	pool: vk.CommandPool
	vk.CreateCommandPool(ctx.device, &pool_ci, nil, &pool)
	defer vk.DestroyCommandPool(ctx.device, pool, nil)

	cmd: vk.CommandBuffer
	alloc_ci := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	vk.AllocateCommandBuffers(ctx.device, &alloc_ci, &cmd)

	begin := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO, flags = {.ONE_TIME_SUBMIT}}
	vk.BeginCommandBuffer(cmd, &begin)

	barrier_to_dst := vk.ImageMemoryBarrier{
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {},
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = ~u32(0),
		dstQueueFamilyIndex = ~u32(0),
		image               = dst,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(cmd,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		0, nil,
		0, nil,
		1, &barrier_to_dst)

	copy := vk.BufferImageCopy{
		imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		imageExtent      = {width = width, height = height, depth = 1},
	}
	vk.CmdCopyBufferToImage(cmd, src, dst, .TRANSFER_DST_OPTIMAL, 1, &copy)

	barrier_to_shader := vk.ImageMemoryBarrier{
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.TRANSFER_WRITE},
		dstAccessMask       = {.SHADER_READ},
		oldLayout           = .TRANSFER_DST_OPTIMAL,
		newLayout           = .SHADER_READ_ONLY_OPTIMAL,
		srcQueueFamilyIndex = ~u32(0),
		dstQueueFamilyIndex = ~u32(0),
		image               = dst,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(cmd,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{},
		0, nil,
		0, nil,
		1, &barrier_to_shader)

	vk.EndCommandBuffer(cmd)

	submit_cmds := [1]vk.CommandBuffer{cmd}
	submit := vk.SubmitInfo{
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &submit_cmds[0],
	}
	null_fence: vk.Fence
	vk.QueueSubmit(ctx.graphics_queue, 1, &submit, null_fence)
	vk.QueueWaitIdle(ctx.graphics_queue)
}
