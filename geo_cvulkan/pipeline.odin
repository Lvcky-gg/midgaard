package geo_cvulkan

import "core:os"
import vk "vendor:vulkan"
import geo_core "../geo_core"
import geo_layers "../geo_layers"
import geo_render "../geo_render"

Vk_Pipeline :: struct {
	render_pass:  vk.RenderPass,
	globe_set_layout: vk.DescriptorSetLayout,
	layout:       vk.PipelineLayout,
	globe_desc_pool: vk.DescriptorPool,
	globe_desc_set: vk.DescriptorSet,
	globe:        vk.Pipeline,
	features:     vk.Pipeline,
	framebuffers: []vk.Framebuffer,
}

vk_pipeline_create :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain) -> Vk_Pipeline {
	p: Vk_Pipeline
	_make_render_pass(ctx, sc, &p)
	_make_globe_set_layout(ctx, &p)
	_make_layout(ctx, &p)
	_make_globe_pipeline(ctx, sc, &p)
	_make_feature_pipeline(ctx, sc, &p)
	_make_framebuffers(ctx, sc, &p)
	return p
}

vk_pipeline_destroy :: proc(ctx: ^Vk_Context, p: ^Vk_Pipeline) {
	for fb in p.framebuffers { vk.DestroyFramebuffer(ctx.device, fb, nil) }
	vk.DestroyPipeline(ctx.device, p.features, nil)
	vk.DestroyPipeline(ctx.device, p.globe, nil)
	if p.globe_desc_pool != 0 {
		vk.DestroyDescriptorPool(ctx.device, p.globe_desc_pool, nil)
	}
	vk.DestroyPipelineLayout(ctx.device, p.layout, nil)
	vk.DestroyDescriptorSetLayout(ctx.device, p.globe_set_layout, nil)
	vk.DestroyRenderPass(ctx.device, p.render_pass, nil)
	delete(p.framebuffers)
}

vk_pipeline_set_globe_texture :: proc(ctx: ^Vk_Context, p: ^Vk_Pipeline, tex: ^Vk_Texture) {
	if tex == nil || !tex.ready { return }

	if p.globe_desc_pool == 0 {
		pool_size := vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1}
		pool_sizes := [1]vk.DescriptorPoolSize{pool_size}
		pool_ci := vk.DescriptorPoolCreateInfo{
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			maxSets       = 1,
			poolSizeCount = 1,
			pPoolSizes    = &pool_sizes[0],
		}
		if r := vk.CreateDescriptorPool(ctx.device, &pool_ci, nil, &p.globe_desc_pool); r != .SUCCESS {
			return
		}

		layouts := [1]vk.DescriptorSetLayout{p.globe_set_layout}
		alloc_ci := vk.DescriptorSetAllocateInfo{
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = p.globe_desc_pool,
			descriptorSetCount = 1,
			pSetLayouts        = &layouts[0],
		}
		if r := vk.AllocateDescriptorSets(ctx.device, &alloc_ci, &p.globe_desc_set); r != .SUCCESS {
			vk.DestroyDescriptorPool(ctx.device, p.globe_desc_pool, nil)
			p.globe_desc_pool = 0
			return
		}
	}

	img_info := vk.DescriptorImageInfo{
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = tex.view,
		sampler     = tex.sampler,
	}
	write := vk.WriteDescriptorSet{
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = p.globe_desc_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &img_info,
	}
	vk.UpdateDescriptorSets(ctx.device, 1, &write, 0, nil)
}

load_shader :: proc(device: vk.Device, path: string) -> vk.ShaderModule {
	bytes, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { panic(path) }
	defer delete(bytes, context.allocator)
	ci := vk.ShaderModuleCreateInfo{
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(bytes),
		pCode    = cast([^]u32)raw_data(bytes),
	}
	m: vk.ShaderModule
	vk.CreateShaderModule(device, &ci, nil, &m)
	return m
}

// ── internals ────────────────────────────────────────────────────────────────

_make_render_pass :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain, p: ^Vk_Pipeline) {
	att := vk.AttachmentDescription{
		format         = sc.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}
	atts := [1]vk.AttachmentDescription{att}
	ref  := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
	refs := [1]vk.AttachmentReference{ref}
	sub  := vk.SubpassDescription{pipelineBindPoint = .GRAPHICS, colorAttachmentCount = 1, pColorAttachments = &refs[0]}
	subs := [1]vk.SubpassDescription{sub}
	ci   := vk.RenderPassCreateInfo{
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1, pAttachments = &atts[0],
		subpassCount    = 1, pSubpasses   = &subs[0],
	}
	vk.CreateRenderPass(ctx.device, &ci, nil, &p.render_pass)
}

_make_globe_set_layout :: proc(ctx: ^Vk_Context, p: ^Vk_Pipeline) {
	b := vk.DescriptorSetLayoutBinding{
		binding            = 0,
		descriptorType     = .COMBINED_IMAGE_SAMPLER,
		descriptorCount    = 1,
		stageFlags         = {.FRAGMENT},
	}
	bindings := [1]vk.DescriptorSetLayoutBinding{b}
	ci := vk.DescriptorSetLayoutCreateInfo{
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &bindings[0],
	}
	vk.CreateDescriptorSetLayout(ctx.device, &ci, nil, &p.globe_set_layout)
}

_make_layout :: proc(ctx: ^Vk_Context, p: ^Vk_Pipeline) {
	r := vk.PushConstantRange{stageFlags = {.VERTEX}, offset = 0, size = size_of(geo_render.Push_Constants)}
	ranges := [1]vk.PushConstantRange{r}
	set_layouts := [1]vk.DescriptorSetLayout{p.globe_set_layout}
	ci := vk.PipelineLayoutCreateInfo{
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &set_layouts[0],
		pushConstantRangeCount = 1, pPushConstantRanges = &ranges[0],
	}
	vk.CreatePipelineLayout(ctx.device, &ci, nil, &p.layout)
}

_make_globe_pipeline :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain, p: ^Vk_Pipeline) {
	vert_m := load_shader(ctx.device, "shaders/globe.vert.spv")
	frag_m := load_shader(ctx.device, "shaders/globe.frag.spv")
	defer vk.DestroyShaderModule(ctx.device, vert_m, nil)
	defer vk.DestroyShaderModule(ctx.device, frag_m, nil)

	stages := [2]vk.PipelineShaderStageCreateInfo{
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX},   module = vert_m, pName = "main"},
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag_m, pName = "main"},
	}

	bind  := [1]vk.VertexInputBindingDescription{{binding = 0, stride = size_of(geo_core.Vertex), inputRate = .VERTEX}}
	attrs := [3]vk.VertexInputAttributeDescription{
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{location = 1, binding = 0, format = .R32G32B32_SFLOAT, offset = 12},
		{location = 2, binding = 0, format = .R32G32_SFLOAT,    offset = 24},
	}
	vert_in := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1, pVertexBindingDescriptions   = &bind[0],
		vertexAttributeDescriptionCount = 3, pVertexAttributeDescriptions = &attrs[0],
	}
	p.globe = _build_pipeline(ctx, sc, p, stages[:], &vert_in, .TRIANGLE_LIST)
}

_make_feature_pipeline :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain, p: ^Vk_Pipeline) {
	vert_m := load_shader(ctx.device, "shaders/feature.vert.spv")
	frag_m := load_shader(ctx.device, "shaders/feature.frag.spv")
	defer vk.DestroyShaderModule(ctx.device, vert_m, nil)
	defer vk.DestroyShaderModule(ctx.device, frag_m, nil)

	stages := [2]vk.PipelineShaderStageCreateInfo{
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX},   module = vert_m, pName = "main"},
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag_m, pName = "main"},
	}

	bind  := [1]vk.VertexInputBindingDescription{{binding = 0, stride = size_of(geo_layers.Feature_Point), inputRate = .VERTEX}}
	attrs := [2]vk.VertexInputAttributeDescription{
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT,    offset = 0},
		{location = 1, binding = 0, format = .R32G32B32A32_SFLOAT, offset = 12},
	}
	vert_in := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1, pVertexBindingDescriptions   = &bind[0],
		vertexAttributeDescriptionCount = 2, pVertexAttributeDescriptions = &attrs[0],
	}
	p.features = _build_pipeline(ctx, sc, p, stages[:], &vert_in, .POINT_LIST)
}

_build_pipeline :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain, p: ^Vk_Pipeline,
	stages: []vk.PipelineShaderStageCreateInfo,
	vert_in: ^vk.PipelineVertexInputStateCreateInfo,
	topology: vk.PrimitiveTopology) -> vk.Pipeline {

	ia  := vk.PipelineInputAssemblyStateCreateInfo{sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, topology = topology}
	vp  := vk.Viewport{width = f32(sc.extent.width), height = f32(sc.extent.height), maxDepth = 1}
	sc2 := vk.Rect2D{extent = sc.extent}
	vps := [1]vk.Viewport{vp}
	scs := [1]vk.Rect2D{sc2}
	vs  := vk.PipelineViewportStateCreateInfo{
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1, pViewports = &vps[0],
		scissorCount  = 1, pScissors  = &scs[0],
	}
	rs := vk.PipelineRasterizationStateCreateInfo{
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL, cullMode = {.BACK}, frontFace = .CLOCKWISE, lineWidth = 1,
	}
	ms := vk.PipelineMultisampleStateCreateInfo{
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	blend_att := vk.PipelineColorBlendAttachmentState{
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA, dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA, colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,       dstAlphaBlendFactor = .ZERO,                alphaBlendOp = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}
	blend_atts := [1]vk.PipelineColorBlendAttachmentState{blend_att}
	blend := vk.PipelineColorBlendStateCreateInfo{
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1, pAttachments = &blend_atts[0],
	}

	ci := vk.GraphicsPipelineCreateInfo{
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(stages)), pStages = &stages[0],
		pVertexInputState   = vert_in,
		pInputAssemblyState = &ia,
		pViewportState      = &vs,
		pRasterizationState = &rs,
		pMultisampleState   = &ms,
		pColorBlendState    = &blend,
		layout              = p.layout,
		renderPass          = p.render_pass,
	}
	cache: vk.PipelineCache
	pl: vk.Pipeline
	vk.CreateGraphicsPipelines(ctx.device, cache, 1, &ci, nil, &pl)
	return pl
}

_make_framebuffers :: proc(ctx: ^Vk_Context, sc: ^Vk_Swapchain, p: ^Vk_Pipeline) {
	p.framebuffers = make([]vk.Framebuffer, len(sc.views))
	for i in 0..<len(sc.views) {
		views := [1]vk.ImageView{sc.views[i]}
		ci := vk.FramebufferCreateInfo{
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = p.render_pass,
			attachmentCount = 1, pAttachments = &views[0],
			width           = sc.extent.width,
			height          = sc.extent.height,
			layers          = 1,
		}
		vk.CreateFramebuffer(ctx.device, &ci, nil, &p.framebuffers[i])
	}
}
