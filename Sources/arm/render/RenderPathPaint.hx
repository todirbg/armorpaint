package arm.render;

import iron.math.Mat4;
import iron.math.Vec4;
import iron.system.Input;
import iron.object.MeshObject;
import iron.RenderPath;
import iron.Scene;
import arm.util.ViewportUtil;
import arm.ui.UIView2D;
import arm.ui.UIHeader;
import arm.ui.UISidebar;
import arm.node.MakeMaterial;
import arm.Enums;

class RenderPathPaint {

	public static var dilated = true;
	public static var liveLayer: arm.data.LayerSlot = null;
	public static var liveLayerDrawn = 0;
	public static var liveLayerLocked = false;
	static var path: RenderPath;
	static var initVoxels = true; // Bake AO
	static var pushUndoLast: Bool;
	static var painto: MeshObject = null;
	static var planeo: MeshObject = null;
	static var visibles: Array<Bool> = null;
	static var mergedObjectVisible = false;
	static var savedFov = 0.0;
	static var baking = false;
	static var _texpaint: RenderTarget;
	static var _texpaint_mask: RenderTarget;
	static var _texpaint_nor: RenderTarget;
	static var _texpaint_pack: RenderTarget;
	static var _texpaint_undo: RenderTarget;
	static var _texpaint_nor_undo: RenderTarget;
	static var _texpaint_pack_undo: RenderTarget;

	public static function init(_path: RenderPath) {
		path = _path;

		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_blend0";
			t.width = Config.getTextureResX();
			t.height = Config.getTextureResY();
			t.format = "R8";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_blend1";
			t.width = Config.getTextureResX();
			t.height = Config.getTextureResY();
			t.format = "R8";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_colorid";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA32";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_picker";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA32";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_nor_picker";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA32";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_pack_picker";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA32";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_posnor_picker0";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA128";
			path.createRenderTarget(t);
		}
		{
			var t = new RenderTargetRaw();
			t.name = "texpaint_posnor_picker1";
			t.width = 1;
			t.height = 1;
			t.format = "RGBA128";
			path.createRenderTarget(t);
		}

		path.loadShader("shader_datas/copy_mrt3_pass/copy_mrt3_pass");
		path.loadShader("shader_datas/dilate_pass/dilate_pass");
	}

	@:access(iron.RenderPath)
	public static function commandsPaint(dilation = true) {
		var tid = Context.layer.id;

		var paintSpace = UIHeader.inst.worktab.position == SpacePaint || UIHeader.inst.worktab.position == SpaceBake;
		if (Context.pdirty > 0 && paintSpace) {
			if (Context.tool == ToolParticle) {
				path.setTarget("texparticle");
				path.clearTarget(0x00000000);
				path.bindTarget("_main", "gbufferD");
				if ((Context.xray || Context.brushAngleReject) && Config.raw.brush_3d) {
					path.bindTarget("gbuffer0", "gbuffer0");
				}

				var mo: MeshObject = cast Scene.active.getChild(".ParticleEmitter");
				mo.visible = true;
				mo.render(path.currentG, "mesh", @:privateAccess path.bindParams);
				mo.visible = false;

				mo = cast Scene.active.getChild(".Particle");
				mo.visible = true;
				mo.render(path.currentG, "mesh", @:privateAccess path.bindParams);
				mo.visible = false;
				@:privateAccess path.end();
			}

			if (Context.tool == ToolColorId) {
				path.setTarget("texpaint_colorid");
				path.clearTarget(0xff000000);
				path.bindTarget("gbuffer2", "gbuffer2");
				path.drawMeshes("paint");
				UIHeader.inst.headerHandle.redraws = 2;
			}
			else if (Context.tool == ToolPicker) {
				if (Context.pickPosNor) {
					path.setTarget("texpaint_posnor_picker0", ["texpaint_posnor_picker1"]);
					path.bindTarget("gbuffer2", "gbuffer2");
					path.bindTarget("_main", "gbufferD");
					path.drawMeshes("paint");
					var texpaint_posnor_picker0 = path.renderTargets.get("texpaint_posnor_picker0").image;
					var texpaint_posnor_picker1 = path.renderTargets.get("texpaint_posnor_picker1").image;
					var a = texpaint_posnor_picker0.getPixels();
					var b = texpaint_posnor_picker1.getPixels();
					Context.posXPicked = a.getFloat(0);
					Context.posYPicked = a.getFloat(4);
					Context.posZPicked = a.getFloat(8);
					Context.norXPicked = b.getFloat(0);
					Context.norYPicked = b.getFloat(4);
					Context.norZPicked = b.getFloat(8);
				}
				else {
					#if kha_metal
					//path.setTarget("texpaint_picker");
					//path.clearTarget(0xff000000);
					//path.setTarget("texpaint_nor_picker");
					//path.clearTarget(0xff000000);
					//path.setTarget("texpaint_pack_picker");
					//path.clearTarget(0xff000000);
					path.setTarget("texpaint_picker", ["texpaint_nor_picker", "texpaint_pack_picker"]);
					#else
					path.setTarget("texpaint_picker", ["texpaint_nor_picker", "texpaint_pack_picker"]);
					//path.clearTarget(0xff000000);
					#end
					path.bindTarget("gbuffer2", "gbuffer2");
					tid = Context.layer.id;
					path.bindTarget("texpaint" + tid, "texpaint");
					path.bindTarget("texpaint_nor" + tid, "texpaint_nor");
					path.bindTarget("texpaint_pack" + tid, "texpaint_pack");
					path.drawMeshes("paint");
					UIHeader.inst.headerHandle.redraws = 2;
					UISidebar.inst.hwnd2.redraws = 2;

					var texpaint_picker = path.renderTargets.get("texpaint_picker").image;
					var texpaint_nor_picker = path.renderTargets.get("texpaint_nor_picker").image;
					var texpaint_pack_picker = path.renderTargets.get("texpaint_pack_picker").image;
					var a = texpaint_picker.getPixels();
					var b = texpaint_nor_picker.getPixels();
					var c = texpaint_pack_picker.getPixels();

					// Picked surface values
					Context.swatch.base.Rb = a.get(0);
					Context.swatch.base.Gb = a.get(1);
					Context.swatch.base.Bb = a.get(2);
					Context.uvxPicked = a.get(3) / 255;
					Context.swatch.normal.Rb = b.get(0);
					Context.swatch.normal.Gb = b.get(1);
					Context.swatch.normal.Bb = b.get(2);
					Context.uvyPicked = c.get(3) / 255;
					Context.swatch.occlusion = c.get(0) / 255;
					Context.swatch.roughness = c.get(1) / 255;
					Context.swatch.metallic = c.get(2) / 255;
					// Pick material
					if (Context.pickerSelectMaterial) {
						var matid = b.get(3);
						for (m in Project.materials) {
							if (m.id == matid) {
								Context.setMaterial(m);
								Context.materialIdPicked = matid;
								break;
							}
						}
					}
				}
			}
			else {
				#if rp_voxelao
				if (Context.tool == ToolBake && Context.bakeType == BakeAO) {
					if (initVoxels) {
						initVoxels = false;
						// Init voxel texture
						var rp_gi = Config.raw.rp_gi;
						Config.raw.rp_gi = true;
						#if rp_voxelao
						Inc.initGI();
						#end
						Config.raw.rp_gi = rp_gi;
					}
					path.clearImage("voxels", 0x00000000);
					path.setTarget("");
					path.setViewport(256, 256);
					path.bindTarget("voxels", "voxels");
					path.drawMeshes("voxel");
					path.generateMipmaps("voxels");
				}
				#end

				var isMask = Context.layerIsMask;
				var texpaint = isMask ? "texpaint_mask" + tid : "texpaint" + tid;

				if (Context.tool == ToolBake && Context.brushTime == iron.system.Time.delta) {
					// Clear to black on bake start
					path.setTarget(texpaint);
					path.clearTarget(0xff000000);
				}

				path.setTarget("texpaint_blend1");
				path.bindTarget("texpaint_blend0", "tex");
				path.drawShader("shader_datas/copy_pass/copyR8_pass");

				path.setTarget(texpaint, ["texpaint_nor" + tid, "texpaint_pack" + tid, "texpaint_blend0"]);
				path.bindTarget("_main", "gbufferD");
				if ((Context.xray || Context.brushAngleReject) && Config.raw.brush_3d) {
					path.bindTarget("gbuffer0", "gbuffer0");
				}
				path.bindTarget("texpaint_blend1", "paintmask");
				#if rp_voxelao
				if (Context.tool == ToolBake && Context.bakeType == BakeAO) {
					path.bindTarget("voxels", "voxels");
				}
				#end
				if (Context.colorIdPicked) {
					path.bindTarget("texpaint_colorid", "texpaint_colorid");
				}

				// Read texcoords from gbuffer
				var readTC = (Context.tool == ToolFill && Context.fillTypeHandle.position == FillFace) ||
							  Context.tool == ToolClone ||
							  Context.tool == ToolBlur;
				if (readTC) {
					path.bindTarget("gbuffer2", "gbuffer2");
				}

				path.drawMeshes("paint");

				if (Context.tool == ToolBake && Context.bakeType == BakeCurvature && Context.bakeCurvSmooth > 0) {
					if (path.renderTargets.get("texpaint_blur") == null) {
						var t = new RenderTargetRaw();
						t.name = "texpaint_blur";
						t.width = Std.int(Config.getTextureResX() * 0.95);
						t.height = Std.int(Config.getTextureResY() * 0.95);
						t.format = "RGBA32";
						path.createRenderTarget(t);
					}
					var blurs = Math.round(Context.bakeCurvSmooth);
					for (i in 0...blurs) {
						path.setTarget("texpaint_blur");
						path.bindTarget(texpaint, "tex");
						path.drawShader("shader_datas/copy_pass/copy_pass");
						path.setTarget(texpaint);
						path.bindTarget("texpaint_blur", "tex");
						path.drawShader("shader_datas/copy_pass/copy_pass");
					}
				}

				if (dilation && Config.raw.dilate == DilateInstant) {
					dilate(true, false);
				}
			}
		}
	}

	public static function useLiveLayer(use: Bool) {
		var tid = Context.layer.id;
		var hid = History.undoI - 1 < 0 ? Config.raw.undo_steps - 1 : History.undoI - 1;
		if (use) {
			_texpaint = path.renderTargets.get("texpaint" + tid);
			_texpaint_undo = path.renderTargets.get("texpaint_undo" + hid);
			_texpaint_nor_undo = path.renderTargets.get("texpaint_nor_undo" + hid);
			_texpaint_pack_undo = path.renderTargets.get("texpaint_pack_undo" + hid);
			_texpaint_mask = path.renderTargets.get("texpaint_mask" + tid);
			_texpaint_nor = path.renderTargets.get("texpaint_nor" + tid);
			_texpaint_pack = path.renderTargets.get("texpaint_pack" + tid);
			path.renderTargets.set("texpaint_undo" + hid, path.renderTargets.get("texpaint" + tid));
			path.renderTargets.set("texpaint_nor_undo" + hid, path.renderTargets.get("texpaint_nor" + tid));
			path.renderTargets.set("texpaint_pack_undo" + hid, path.renderTargets.get("texpaint_pack" + tid));
			path.renderTargets.set("texpaint" + tid, path.renderTargets.get("texpaint_live"));
			if (_texpaint_mask != null) path.renderTargets.set("texpaint_mask" + tid, path.renderTargets.get("texpaint_mask_live"));
			path.renderTargets.set("texpaint_nor" + tid, path.renderTargets.get("texpaint_nor_live"));
			path.renderTargets.set("texpaint_pack" + tid, path.renderTargets.get("texpaint_pack_live"));
		}
		else {
			path.renderTargets.set("texpaint" + tid, _texpaint);
			path.renderTargets.set("texpaint_undo" + hid, _texpaint_undo);
			path.renderTargets.set("texpaint_nor_undo" + hid, _texpaint_nor_undo);
			path.renderTargets.set("texpaint_pack_undo" + hid, _texpaint_pack_undo);
			if (_texpaint_mask != null) path.renderTargets.set("texpaint_mask" + tid, _texpaint_mask);
			path.renderTargets.set("texpaint_nor" + tid, _texpaint_nor);
			path.renderTargets.set("texpaint_pack" + tid, _texpaint_pack);
		}
		liveLayerLocked = use;
	}

	static function commandsLiveBrush() {

		var tool = Context.tool;
		if (tool != ToolBrush &&
			tool != ToolEraser &&
			tool != ToolClone &&
			tool != ToolDecal &&
			tool != ToolText &&
			tool != ToolBlur) {
				return;
		}

		if (liveLayerLocked) return;

		if (liveLayer == null) {
			liveLayer = new arm.data.LayerSlot("_live");
			liveLayer.createMask(0x00000000);
		}

		var tid = Context.layer.id;
		if (Context.layerIsMask) {
			path.setTarget("texpaint_mask_live");
			path.bindTarget("texpaint_mask" + tid, "tex");
			path.drawShader("shader_datas/copy_pass/copy_pass");
		}
		else {
			path.setTarget("texpaint_live", ["texpaint_nor_live", "texpaint_pack_live"]);
			path.bindTarget("texpaint" + tid, "tex0");
			path.bindTarget("texpaint_nor" + tid, "tex1");
			path.bindTarget("texpaint_pack" + tid, "tex2");
			path.drawShader("shader_datas/copy_mrt3_pass/copy_mrt3_pass");
		}

		useLiveLayer(true);

		liveLayerDrawn = 2;

		UIView2D.inst.hwnd.redraws = 2;
		var _x = Context.paintVec.x;
		var _y = Context.paintVec.y;
		if (Context.brushLocked) {
			Context.paintVec.x = (Context.lockStartedX - iron.App.x()) / iron.App.w();
			Context.paintVec.y = (Context.lockStartedY - iron.App.y()) / iron.App.h();
		}
		var _lastX = Context.lastPaintVecX;
		var _lastY = Context.lastPaintVecY;
		var _pdirty = Context.pdirty;
		Context.lastPaintVecX = Context.paintVec.x;
		Context.lastPaintVecY = Context.paintVec.y;
		if (Operator.shortcut(Config.keymap.brush_ruler)) {
			Context.lastPaintVecX = Context.lastPaintX;
			Context.lastPaintVecY = Context.lastPaintY;
		}
		Context.pdirty = 2;

		commandsSymmetry();
		commandsPaint();

		useLiveLayer(false);

		Context.paintVec.x = _x;
		Context.paintVec.y = _y;
		Context.lastPaintVecX = _lastX;
		Context.lastPaintVecY = _lastY;
		Context.pdirty = _pdirty;
		Context.brushBlendDirty = true;
	}

	public static function commandsCursor() {
		var decal = Context.tool == ToolDecal || Context.tool == ToolText;
		var decalMask = decal && Operator.shortcut(Config.keymap.decal_mask, ShortcutDown);
		var tool = Context.tool;
		if (tool != ToolBrush &&
			tool != ToolEraser &&
			tool != ToolClone &&
			tool != ToolBlur &&
			tool != ToolParticle &&
			!decalMask) {
				return;
		}

		var fillLayer = Context.layer.fill_layer != null && !Context.layerIsMask;
		var fillMask = Context.layer.fill_mask != null && Context.layerIsMask;
		var groupLayer = Context.layer.getChildren() != null;
		if (!App.uiEnabled || App.isDragging || fillLayer || fillMask || groupLayer) {
			return;
		}

		var mx = Context.paintVec.x;
		var my = 1.0 - Context.paintVec.y;
		if (Context.brushLocked) {
			mx = (Context.lockStartedX - iron.App.x()) / iron.App.w();
			my = 1.0 - (Context.lockStartedY - iron.App.y()) / iron.App.h();
		}
		var radius = decalMask ? Context.brushDecalMaskRadius : Context.brushRadius;
		drawCursor(mx, my, Context.brushNodesRadius * radius / 3.4);

		// if (Context.brushLazyRadius > 0 && (Context.tool == ToolBrush || Context.tool == ToolEraser)) {
		// 	var _brushRadius = Context.brushRadius;
		// 	Context.brushRadius = Context.brushLazyRadius;
		// 	mx = Context.brushLazyX;
		// 	my = 1.0 - Context.brushLazyY;
		// 	if (Context.brushLocked) {
		// 		mx = (Context.lockStartedX - iron.App.x()) / iron.App.w();
		// 		my = 1.0 - (Context.lockStartedY - iron.App.y()) / iron.App.h();
		// 	}
		// 	drawCursor(mx, my, 0.2, 0.2, 0.2);
		// 	Context.brushRadius -= Context.brushLazyRadius;
		// }
	}

	@:access(iron.RenderPath)
	static function drawCursor(mx: Float, my: Float, radius: Float, tintR = 1.0, tintG = 1.0, tintB = 1.0) {
		var plane = cast(Scene.active.getChild(".Plane"), MeshObject);
		var geom = plane.data.geom;

		var g = path.frameG;
		if (Layers.pipeCursor == null) Layers.makeCursorPipe();

		path.setTarget("");
		g.setPipeline(Layers.pipeCursor);
		var decal = Context.tool == ToolDecal || Context.tool == ToolText;
		var decalMask = decal && Operator.shortcut(Config.keymap.decal_mask, ShortcutDown);
		var img = (decal && !decalMask) ? Context.decalImage : Res.get("cursor.k");
		g.setTexture(Layers.cursorTex, img);
		var gbuffer0 = path.renderTargets.get("gbuffer0").image;
		g.setTextureDepth(Layers.cursorGbufferD, gbuffer0);
		g.setFloat2(Layers.cursorMouse, mx, my);
		g.setFloat2(Layers.cursorTexStep, 1 / gbuffer0.width, 1 / gbuffer0.height);
		g.setFloat(Layers.cursorRadius, radius);
		var right = Scene.active.camera.rightWorld().normalize();
		g.setFloat3(Layers.cursorCameraRight, right.x, right.y, right.z);
		g.setFloat3(Layers.cursorTint, tintR, tintG, tintB);
		g.setMatrix(Layers.cursorVP, Scene.active.camera.VP.self);
		var helpMat = iron.math.Mat4.identity();
		helpMat.getInverse(Scene.active.camera.VP);
		g.setMatrix(Layers.cursorInvVP, helpMat.self);
		#if (kha_metal || kha_vulkan)
		g.setVertexBuffer(geom.get([{name: "tex", data: "short2norm"}]));
		#else
		g.setVertexBuffer(geom.vertexBuffer);
		#end
		g.setIndexBuffer(geom.indexBuffers[0]);
		g.drawIndexedVertices();

		g.disableScissor();
		path.end();
	}

	static function commandsSymmetry() {
		if (Context.symX || Context.symY || Context.symZ) {
			Context.ddirty = 2;
			var t = Context.paintObject.transform;
			var sx = t.scale.x;
			var sy = t.scale.y;
			var sz = t.scale.z;
			if (Context.symX) {
				t.scale.set(-sx, sy, sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symY) {
				t.scale.set(sx, -sy, sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symZ) {
				t.scale.set(sx, sy, -sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symX && Context.symY) {
				t.scale.set(-sx, -sy, sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symX && Context.symZ) {
				t.scale.set(-sx, sy, -sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symY && Context.symZ) {
				t.scale.set(sx, -sy, -sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			if (Context.symX && Context.symY && Context.symZ) {
				t.scale.set(-sx, -sy, -sz);
				t.buildMatrix();
				commandsPaint(false);
			}
			t.scale.set(sx, sy, sz);
			t.buildMatrix();
		}
	}

	static function paintEnabled(): Bool {
		var fillLayer = Context.layer.fill_layer != null && !Context.layerIsMask;
		var fillMask = Context.layer.fill_mask != null && Context.layerIsMask;
		var groupLayer = Context.layer.getChildren() != null;
		return !fillLayer && !fillMask && !groupLayer && !Context.foregroundEvent;
	}

	public static function begin() {
		if (!paintEnabled()) return;

		pushUndoLast = History.pushUndo;
		if (History.pushUndo && History.undoLayers != null) {
			History.paint();
		}

		// 2D paint
		if (Context.paint2d) {
			Context.paint2dView = true;
			// Set plane mesh
			painto = Context.paintObject;
			visibles = [];
			for (p in Project.paintObjects) {
				visibles.push(p.visible);
				p.visible = false;
			}
			if (Context.mergedObject != null) {
				mergedObjectVisible = Context.mergedObject.visible;
				Context.mergedObject.visible = false;
			}

			var cam = Scene.active.camera;
			Context.savedCamera.setFrom(cam.transform.local);
			savedFov = cam.data.raw.fov;
			ViewportUtil.updateCameraType(CameraPerspective);
			var m = Mat4.identity();
			m.translate(0, 0, 0.5);
			cam.transform.setMatrix(m);
			cam.data.raw.fov = 0.92;
			cam.buildProjection();
			cam.buildMatrix();

			var tw = 0.95 * UIView2D.inst.panScale;
			var tx = UIView2D.inst.panX / UIView2D.inst.ww;
			var ty = UIView2D.inst.panY / iron.App.h();
			m.setIdentity();
			m.scale(new Vec4(tw, tw, 1));
			m.setLoc(new Vec4(tx, ty, 0));
			var m2 = Mat4.identity();
			m2.getInverse(Scene.active.camera.VP);
			m.multmat(m2);

			planeo = cast Scene.active.getChild(".Plane");
			planeo.visible = true;
			Context.paintObject = planeo;

			var v = new Vec4();
			var sx = v.set(m._00, m._01, m._02).length();
			planeo.transform.rot.fromEuler(-Math.PI / 2, 0, 0);
			planeo.transform.scale.set(sx, 1.0, sx);
			planeo.transform.scale.z *= Config.getTextureResY() / Config.getTextureResX();
			planeo.transform.loc.set(m._30, -m._31, 0.0);
			planeo.transform.buildMatrix();
		}

		if (liveLayerDrawn > 0) liveLayerDrawn--;

		if (Config.raw.brush_live && Context.pdirty <= 0 && Context.ddirty <= 0 && Context.brushTime == 0) {
			// Depth is unchanged, draw before gbuffer gets updated
			commandsLiveBrush();
		}
	}

	public static function end() {
		if (Config.raw.brush_3d) commandsCursor();
		Context.ddirty--;
		Context.rdirty--;

		if (!paintEnabled()) return;
		Context.pdirty--;
	}

	public static function draw() {
		if (!paintEnabled()) return;

		if (Config.raw.brush_live && Context.pdirty <= 0 && Context.ddirty > 0 && Context.brushTime == 0) {
			// gbuffer has been updated now but brush will lag 1 frame
			commandsLiveBrush();
		}

		if (History.undoLayers != null) {

			commandsSymmetry();

			if (Context.pdirty > 0) dilated = false;
			if (Context.tool == ToolBake) {
				if (Context.bakeType == BakeNormal || Context.bakeType == BakeHeight || Context.bakeType == BakeDerivative) {
					if (!baking && Context.pdirty > 0) {
						baking = true;
						var _bakeType = Context.bakeType;
						Context.bakeType = Context.bakeType == BakeNormal ? BakeNormalObject : BakePosition; // Bake high poly data
						MakeMaterial.parsePaintMaterial();
						var _paintObject = Context.paintObject;
						var highPoly = Project.paintObjects[Context.bakeHighPoly];
						var _visible = highPoly.visible;
						highPoly.visible = true;
						Context.selectPaintObject(highPoly);
						commandsPaint();
						highPoly.visible = _visible;
						if (pushUndoLast) History.paint();
						Context.selectPaintObject(_paintObject);

						function _renderFinal() {
							Context.bakeType = _bakeType;
							MakeMaterial.parsePaintMaterial();
							Context.pdirty = 1;
							commandsPaint();
							Context.pdirty = 0;
							baking = false;
						}
						function _renderDeriv() {
							Context.bakeType = BakeHeight;
							MakeMaterial.parsePaintMaterial();
							Context.pdirty = 1;
							commandsPaint();
							Context.pdirty = 0;
							if (pushUndoLast) History.paint();
							iron.App.notifyOnInit(_renderFinal);
						}
						iron.App.notifyOnInit(Context.bakeType == BakeDerivative ? _renderDeriv : _renderFinal);
					}
				}
				else if (Context.bakeType == BakeObjectID) {
					var _layerFilter = Context.layerFilter;
					var _paintObject = Context.paintObject;
					var isMerged = Context.mergedObject != null;
					var _visible = isMerged && Context.mergedObject.visible;
					Context.layerFilter = 1;
					if (isMerged) Context.mergedObject.visible = false;

					for (p in Project.paintObjects) {
						Context.selectPaintObject(p);
						commandsPaint();
					}

					Context.layerFilter = _layerFilter;
					Context.selectPaintObject(_paintObject);
					if (isMerged) Context.mergedObject.visible = _visible;
				}
				#if (kha_direct3d12 || kha_vulkan)
				else if (Context.bakeType == BakeAO  ||
						 Context.bakeType == BakeLightmap ||
						 Context.bakeType == BakeBentNormal ||
						 Context.bakeType == BakeThickness) {
					RenderPathRaytrace.commandsBake();
					if (Config.raw.dilate == DilateInstant) { // && Context.pdirty == 1
						dilate(true, false);
					}
				}
				#end
				else {
					commandsPaint();
				}
			}
			else { // Paint
				commandsPaint();
			}
		}

		//

		if (Context.brushBlendDirty) {
			Context.brushBlendDirty = false;
			#if kha_metal
			path.setTarget("texpaint_blend0");
			path.clearTarget(0x00000000);
			path.setTarget("texpaint_blend1");
			path.clearTarget(0x00000000);
			#else
			path.setTarget("texpaint_blend0", ["texpaint_blend1"]);
			path.clearTarget(0x00000000);
			#end
		}

		if (Context.paint2d) {
			Context.paint2dView = false;
			// Restore paint mesh
			planeo.visible = false;
			planeo.transform.loc.set(0.0, 0.0, 0.0);
			for (i in 0...Project.paintObjects.length) {
				Project.paintObjects[i].visible = visibles[i];
			}
			if (Context.mergedObject != null) {
				Context.mergedObject.visible = mergedObjectVisible;
			}
			Context.paintObject = painto;
			Scene.active.camera.transform.setMatrix(Context.savedCamera);
			Scene.active.camera.data.raw.fov = savedFov;
			ViewportUtil.updateCameraType(Context.cameraType);
			Scene.active.camera.buildProjection();
			Scene.active.camera.buildMatrix();

			RenderPathDeferred.drawGbuffer();
		}
	}

	public static function bindLayers() {
		var isLive = Config.raw.brush_live && liveLayerDrawn > 0;
		var isMaterialSpace = UIHeader.inst.worktab.position == SpaceMaterial;
		if (isLive || isMaterialSpace) useLiveLayer(true);

		for (i in 0...Project.layers.length) {
			var l = Project.layers[i];
			path.bindTarget("texpaint" + l.id, "texpaint" + l.id);
			path.bindTarget("texpaint_nor" + l.id, "texpaint_nor" + l.id);
			path.bindTarget("texpaint_pack" + l.id, "texpaint_pack" + l.id);
			if (l.texpaint_mask != null) {
				path.bindTarget("texpaint_mask" + l.id, "texpaint_mask" + l.id);
			}
		}
	}

	public static function unbindLayers() {
		var isLive = Config.raw.brush_live && liveLayerDrawn > 0;
		var isMaterialSpace = UIHeader.inst.worktab.position == SpaceMaterial;
		if (isLive || isMaterialSpace) useLiveLayer(false);
	}

	public static function dilate(base: Bool, nor_pack: Bool) {
		if (Config.raw.dilate_radius > 0 && !Context.paint2d) {
			arm.util.UVUtil.cacheDilateMap();
			Layers.makeTempImg();
			var tid = Context.layer.id;
			if (base) {
				path.setTarget("temptex0");
				path.bindTarget("texpaint" + tid, "tex");
				path.drawShader("shader_datas/copy_pass/copy_pass");
				path.setTarget("texpaint" + tid);
				path.bindTarget("temptex0", "tex");
				path.drawShader("shader_datas/dilate_pass/dilate_pass");
			}
			if (nor_pack) {
				path.setTarget("temptex0");
				path.bindTarget("texpaint_nor" + tid, "tex");
				path.drawShader("shader_datas/copy_pass/copy_pass");
				path.setTarget("texpaint_nor" + tid);
				path.bindTarget("temptex0", "tex");
				path.drawShader("shader_datas/dilate_pass/dilate_pass");

				path.setTarget("temptex0");
				path.bindTarget("texpaint_pack" + tid, "tex");
				path.drawShader("shader_datas/copy_pass/copy_pass");
				path.setTarget("texpaint_pack" + tid);
				path.bindTarget("temptex0", "tex");
				path.drawShader("shader_datas/dilate_pass/dilate_pass");
			}
		}
	}
}
