import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';
export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution

    gbufferAlbedo: GPUTexture;
    gbufferNormal: GPUTexture;
    gbufferDepth: GPUTexture;
    gbufferAlbedoView: GPUTextureView;
    gbufferNormalView: GPUTextureView;
    gbufferDepthView: GPUTextureView;
    gSceneBindGroupLayout: GPUBindGroupLayout;
    gSceneBindGroup: GPUBindGroup;
    gbufferPosition: GPUTexture;
    gbufferPositionView: GPUTextureView;


    cSceneBindGroupLayout: GPUBindGroupLayout;
    cSceneBindGroup: GPUBindGroup;

    pipelineGBuffer: GPURenderPipeline;
    pipelineFullscreen: GPURenderPipeline;
    constructor(stage: Stage) {
        super(stage);
        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass

        // Array of light indices per cluster
        this.gbufferAlbedo = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba8unorm",
            usage: GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING,
        });

        this.gbufferNormal = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING,
        });

        this.gbufferDepth = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "depth24plus",
            usage: GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING,
        });
        this.gbufferPosition = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage:
                GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING,
        });

        this.gbufferPositionView = this.gbufferPosition.createView();

        this.gbufferAlbedoView = this.gbufferAlbedo.createView();
        this.gbufferNormalView = this.gbufferNormal.createView();
        this.gbufferDepthView = this.gbufferDepth.createView();

        this.gSceneBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "Clusted Deferred Gbuffer scene bgl",
            entries: [
                {
                // camera uniforms
                binding: 0,
                visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                buffer: { type: "uniform" },
                }
            ],
        });
        this.gSceneBindGroup = renderer.device.createBindGroup({
            label: "Clusted Deferred Gbuffer",
            layout: this.gSceneBindGroupLayout,
            entries: [
                { binding: 0, resource: { buffer: this.camera.uniformsBuffer } }
            ],
        });

        this.pipelineGBuffer = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                bindGroupLayouts: [
                this.gSceneBindGroupLayout,
                renderer.modelBindGroupLayout,
                renderer.materialBindGroupLayout,
                ],
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "Deferred Cluster GBuffer Vert shader",
                    code: shaders.naiveVertSrc
                }),
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "Deferred Clustered GBuffer Frag shader",
                    code: shaders.clusteredDeferredFragSrc
                }),
                targets: [
                        { format: "rgba8unorm" },   // albedo
                        { format: "rgba16float" },  // normal
                        { format: "rgba16float" },  // position
                ]
            }
        });


        this.cSceneBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "Deferred Clustered lighting scene bgl",
            entries: [
                {
                // camera uniforms
                binding: 0,
                visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                buffer: { type: "uniform" },
                },
                {
                // light set
                binding: 1,
                visibility: GPUShaderStage.FRAGMENT,
                buffer: { type: "read-only-storage" },
                },
                {
                // cluster grid
                binding: 2,
                visibility: GPUShaderStage.FRAGMENT,
                buffer: { type: "read-only-storage" },
                },
                {
                // cluster light indices
                binding: 3,
                visibility: GPUShaderStage.FRAGMENT,
                buffer: { type: "read-only-storage" },
                },
                {
                // albedo
                binding: 4,
                visibility: GPUShaderStage.FRAGMENT,
                texture: { sampleType: "float" },
                },
                // normal
                {                
                binding: 5,
                visibility: GPUShaderStage.FRAGMENT,
                texture: { sampleType: "float" },
                },
                // depth
                {
                binding: 6,
                visibility: GPUShaderStage.FRAGMENT,
                texture: { sampleType: "depth" },
                },
                //position
                {
                    binding: 7, 
                    visibility: GPUShaderStage.FRAGMENT, 
                    texture: { sampleType: "float" } 
                }
            ],
        });
        this.cSceneBindGroup = renderer.device.createBindGroup({
            label: "clustering deferred Bind Group scene bg",
            layout: this.cSceneBindGroupLayout,
            entries: [
                { binding: 0, resource: { buffer: this.camera.uniformsBuffer } },
                { binding: 1, resource: { buffer: this.lights.lightSetStorageBuffer } },
                { binding: 2, resource: { buffer: this.lights.clusterLightGridBuffer } },
                {
                    binding: 3,
                    resource: { buffer: this.lights.clusterLightIndexBuffer }
                },
                {
                    binding: 4,
                    resource: this.gbufferAlbedoView
                },
                {
                    binding: 5,
                    resource: this.gbufferNormalView
                },
                {
                    binding: 6,
                    resource: this.gbufferDepthView
                },
                { 
                    binding: 7, 
                    resource: this.gbufferPositionView 
                }
            ],
        });

        this.pipelineFullscreen = renderer.device.createRenderPipeline({
            label: "clustered deferred - fullscreen pipeline",
            layout: renderer.device.createPipelineLayout({
                bindGroupLayouts: [
                this.cSceneBindGroupLayout,
                ],
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "Deferred Cluster Fullscreen Vert shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                }),
                buffers: [] // fullscreen triangle is generated procedurally in the shader
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "Deferred Cluster Fullscreen Frag shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc,
                }),
                targets:[
                        { format: renderer.canvasFormat }
                ]
            }
        });
    }

    override draw() {
        const encoder = renderer.device.createCommandEncoder();

        // Cluster lights
        this.lights.doLightClustering(encoder);

        // G-buffer pass
        const gbufferPass = encoder.beginRenderPass({
        label: "clustered deferred - gbuffer pass",
        colorAttachments: [
            {
                view: this.gbufferAlbedoView,
                clearValue: [0, 0, 0, 1],
                loadOp: "clear",
                storeOp: "store",
            },
            {
                view: this.gbufferNormalView,
                clearValue: [0, 0, 0, 1],
                loadOp: "clear",
                storeOp: "store",
            },
            { 
                view: this.gbufferPositionView,
                loadOp: "clear", 
                storeOp: "store", 
                clearValue: [0, 0, 0, 1] 
            },
        ],
        depthStencilAttachment: {
            view: this.gbufferDepthView,
            depthClearValue: 1.0,
            depthLoadOp: "clear",
            depthStoreOp: "store",
        },
        });

        gbufferPass.setPipeline(this.pipelineGBuffer);
        gbufferPass.setBindGroup(
        shaders.constants.bindGroup_scene,
        this.gSceneBindGroup
        );

        this.scene.iterate(
        (node) => {
            gbufferPass.setBindGroup(
            shaders.constants.bindGroup_model,
            node.modelBindGroup
            );
        },
        (material) => {
            gbufferPass.setBindGroup(
            shaders.constants.bindGroup_material,
            material.materialBindGroup
            );
        },
        (primitive) => {
            gbufferPass.setVertexBuffer(0, primitive.vertexBuffer);
            gbufferPass.setIndexBuffer(primitive.indexBuffer, "uint32");
            gbufferPass.drawIndexed(primitive.numIndices);
        }
        );

        gbufferPass.end();

        // Fullscreen lighting pass

        const canvasTextureView =
        renderer.context.getCurrentTexture().createView();

        const lightingPass = encoder.beginRenderPass({
        label: "clustered deferred - lighting pass",
        colorAttachments: [
            {
            view: canvasTextureView,
            clearValue: [0, 0, 0, 1],
            loadOp: "clear",
            storeOp: "store",
            },
        ],
        });

        lightingPass.setPipeline(this.pipelineFullscreen);
        lightingPass.setBindGroup(0, this.cSceneBindGroup);
        lightingPass.draw(3);
        lightingPass.end();

        renderer.device.queue.submit([encoder.finish()]);
    }
}
