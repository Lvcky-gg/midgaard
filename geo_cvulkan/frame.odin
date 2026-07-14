package geo_cvulkan

import vk "vendor:vulkan"
import geo_render "../geo_render"

Vk_Frame_Data :: struct {
	command_pool:    vk.CommandPool,
	command_buffers: []vk.CommandBuffer,
	image_available: vk.Semaphore,
	render_finished: vk.Semaphore,
	fence:           vk.Fence,
}

// Vk_Draw_State is the per-frame snapshot passed to vk_draw_frame.
// geo_app fills this from its App struct each loop iteration.
Vk_Draw_State :: struct {
	ctx:           ^Vk_Context,
	swapchain:     ^Vk_Swapchain,
	pipeline:      ^Vk_Pipeline,
	frame:         ^Vk_Frame_Data,
	globe_vb:      Vk_Buffer,
	globe_ib:      Vk_Buffer,
	globe_ic:      u32,
	feature_vb:    Vk_Buffer,
	feature_count: u32,
	mvp:           [16]f32,
}

vk_frame_create :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain) -> Vk_Frame_Data {
	f: Vk_Frame_Data

	pool_ci := vk.CommandPoolCreateInfo{
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.queue_info.graphics_index,
	}
	vk.CreateCommandPool(ctx.device, &pool_ci, nil, &f.command_pool)

	f.command_buffers = make([]vk.CommandBuffer, len(sc.views))
	alloc_ci := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = f.command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(f.command_buffers)),
	}
	vk.AllocateCommandBuffers(ctx.device, &alloc_ci, raw_data(f.command_buffers))

	sem_ci   := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	fence_ci := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO, flags = {.SIGNALED}}
	vk.CreateSemaphore(ctx.device, &sem_ci,   nil, &f.image_available)
	vk.CreateSemaphore(ctx.device, &sem_ci,   nil, &f.render_finished)
	vk.CreateFence(ctx.device,     &fence_ci, nil, &f.fence)
	return f
}

vk_frame_destroy :: proc(ctx: ^Vk_Context, f: ^Vk_Frame_Data) {
	vk.DestroyFence(ctx.device, f.fence, nil)
	vk.DestroySemaphore(ctx.device, f.render_finished, nil)
	vk.DestroySemaphore(ctx.device, f.image_available, nil)
	vk.DestroyCommandPool(ctx.device, f.command_pool, nil)
	delete(f.command_buffers)
}

vk_draw_frame :: proc(ds: ^Vk_Draw_State) {
	f   := ds.frame
	ctx := ds.ctx
	sc  := ds.swapchain
	pl  := ds.pipeline

	vk.WaitForFences(ctx.device, 1, &f.fence, true, ~u64(0))
	vk.ResetFences(ctx.device, 1, &f.fence)

	img_idx: u32
	null_fence: vk.Fence
	if r := vk.AcquireNextImageKHR(ctx.device, sc.handle, ~u64(0), f.image_available, null_fence, &img_idx); r != .SUCCESS {
		return
	}

	cmd := f.command_buffers[img_idx]
	vk.ResetCommandBuffer(cmd, {})
	_record(ds, cmd, img_idx)

	wait_sems  := [1]vk.Semaphore{f.image_available}
	sig_sems   := [1]vk.Semaphore{f.render_finished}
	wait_stage := [1]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	cmds       := [1]vk.CommandBuffer{cmd}
	submit := vk.SubmitInfo{
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1, pWaitSemaphores   = &wait_sems[0],  pWaitDstStageMask = &wait_stage[0],
		commandBufferCount   = 1, pCommandBuffers   = &cmds[0],
		signalSemaphoreCount = 1, pSignalSemaphores = &sig_sems[0],
	}
	vk.QueueSubmit(ctx.graphics_queue, 1, &submit, f.fence)

	scs     := [1]vk.SwapchainKHR{sc.handle}
	idxs    := [1]u32{img_idx}
	present := vk.PresentInfoKHR{
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1, pWaitSemaphores = &sig_sems[0],
		swapchainCount     = 1, pSwapchains     = &scs[0], pImageIndices = &idxs[0],
	}
	vk.QueuePresentKHR(ctx.present_queue, &present)
}

_record :: proc(ds: ^Vk_Draw_State, cmd: vk.CommandBuffer, img_idx: u32) {
	ctx := ds.ctx
	sc  := ds.swapchain
	pl  := ds.pipeline

	vk.BeginCommandBuffer(cmd, &vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO, flags = {.ONE_TIME_SUBMIT}})

	clear  := vk.ClearValue{color = {float32 = {0.03, 0.06, 0.11, 1.0}}}
	clears := [1]vk.ClearValue{clear}
	rp_begin := vk.RenderPassBeginInfo{
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = pl.render_pass,
		framebuffer     = pl.framebuffers[img_idx],
		renderArea      = {extent = sc.extent},
		clearValueCount = 1, pClearValues = &clears[0],
	}
	vk.CmdBeginRenderPass(cmd, &rp_begin, .INLINE)

	pc := geo_render.Push_Constants{mvp = ds.mvp}

	// Globe
	vk.CmdBindPipeline(cmd, .GRAPHICS, pl.globe)
	vbs     := [1]vk.Buffer{ds.globe_vb.handle}
	offsets := [1]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vbs[0], &offsets[0])
	vk.CmdBindIndexBuffer(cmd, ds.globe_ib.handle, 0, .UINT32)
	if pl.globe_desc_set != 0 {
		sets := [1]vk.DescriptorSet{pl.globe_desc_set}
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pl.layout, 0, 1, &sets[0], 0, nil)
	}
	vk.CmdPushConstants(cmd, pl.layout, {.VERTEX}, 0, size_of(geo_render.Push_Constants), &pc)
	vk.CmdDrawIndexed(cmd, ds.globe_ic, 1, 0, 0, 0)

	// Feature points
	if ds.feature_count > 0 {
		vk.CmdBindPipeline(cmd, .GRAPHICS, pl.features)
		feat_vbs := [1]vk.Buffer{ds.feature_vb.handle}
		vk.CmdBindVertexBuffers(cmd, 0, 1, &feat_vbs[0], &offsets[0])
		vk.CmdPushConstants(cmd, pl.layout, {.VERTEX}, 0, size_of(geo_render.Push_Constants), &pc)
		vk.CmdDraw(cmd, ds.feature_count, 1, 0, 0)
	}

	vk.CmdEndRenderPass(cmd)
	vk.EndCommandBuffer(cmd)
}
