package arm;

import kha.System;
import kha.Window;
import kha.Image;
import zui.Zui;
import zui.Id;
import zui.Nodes;
import iron.data.SceneFormat;
import iron.data.MeshData;
import iron.data.Data;
import iron.object.MeshObject;
import iron.Scene;
import arm.Viewport;
import arm.sys.File;
import arm.sys.Path;
import arm.ui.UIFiles;
import arm.ui.UIBox;
import arm.ui.UINodes;
import arm.ui.BoxPreferences;
import arm.util.MeshUtil;
import arm.shader.MakeMaterial;
import arm.io.ImportAsset;
import arm.io.ImportArm;
import arm.io.ImportGpl;
import arm.io.ImportMesh;
import arm.io.ImportTexture;
import arm.io.ExportArm;
import arm.io.ExportGpl;
import arm.ProjectFormat;
#if (is_paint || is_sculpt)
import arm.util.RenderUtil;
import arm.ui.UIBase;
import arm.data.LayerSlot;
import arm.data.BrushSlot;
import arm.data.FontSlot;
import arm.data.MaterialSlot;
import arm.io.ImportBlendMaterial;
import arm.logic.NodesBrush;
#end
#if is_lab
import kha.Blob;
#end

class Project {

	public static var raw: TProjectFormat = {};
	public static var filepath = "";
	public static var assets: Array<TAsset> = [];
	public static var assetNames: Array<String> = [];
	public static var assetId = 0;
	public static var meshAssets: Array<String> = [];
	public static var materialGroups: Array<TNodeGroup> = [];
	public static var paintObjects: Array<MeshObject> = null;
	public static var assetMap = new Map<Int, Dynamic>(); // kha.Image | kha.Font
	static var meshList: Array<String> = null;
	#if (is_paint || is_sculpt)
	public static var materials: Array<MaterialSlot> = null;
	public static var brushes: Array<BrushSlot> = null;
	public static var layers: Array<LayerSlot> = null;
	public static var fonts: Array<FontSlot> = null;
	public static var atlasObjects: Array<Int> = null;
	public static var atlasNames: Array<String> = null;
	#end
	#if is_lab
	public static var materialData: iron.data.MaterialData = null; ////
	public static var materials: Array<Dynamic> = null; ////
	public static var nodes = new Nodes();
	public static var canvas: TNodeCanvas;
	public static var defaultCanvas: Blob = null;
	#end

	public static function projectOpen() {
		UIFiles.show("arm", false, false, function(path: String) {
			if (!path.endsWith(".arm")) {
				Console.error(Strings.error0());
				return;
			}

			var current = @:privateAccess kha.graphics2.Graphics.current;
			if (current != null) current.end();

			ImportArm.runProject(path);

			if (current != null) current.begin(false);
		});
	}

	public static function projectSave(saveAndQuit = false) {
		if (filepath == "") {
			#if krom_ios
			var documentDirectory = Krom.saveDialog("", "");
			documentDirectory = documentDirectory.substr(0, documentDirectory.length - 8); // Strip /'untitled'
			filepath = documentDirectory + "/" + kha.Window.get(0).title + ".arm";
			#elseif krom_android
			filepath = Krom.savePath() + "/" + kha.Window.get(0).title + ".arm";
			#else
			projectSaveAs(saveAndQuit);
			return;
			#end
		}

		#if (krom_windows || krom_linux || krom_darwin)
		var filename = Project.filepath.substring(Project.filepath.lastIndexOf(Path.sep) + 1, Project.filepath.length - 4);
		Window.get(0).title = filename + " - " + Manifest.title;
		#end

		function _init() {
			ExportArm.runProject();
			if (saveAndQuit) System.stop();
		}
		iron.App.notifyOnInit(_init);
	}

	public static function projectSaveAs(saveAndQuit = false) {
		UIFiles.show("arm", true, false, function(path: String) {
			var f = UIFiles.filename;
			if (f == "") f = tr("untitled");
			filepath = path + Path.sep + f;
			if (!filepath.endsWith(".arm")) filepath += ".arm";
			projectSave(saveAndQuit);
		});
	}

	public static function projectNewBox() {
		#if (is_paint || is_sculpt)
		UIBox.showCustom(function(ui: Zui) {
			if (ui.tab(Id.handle(), tr("New Project"))) {
				if (meshList == null) {
					meshList = File.readDirectory(Path.data() + Path.sep + "meshes");
					for (i in 0...meshList.length) meshList[i] = meshList[i].substr(0, meshList[i].length - 4); // Trim .arm
					meshList.unshift("plane");
					meshList.unshift("sphere");
					meshList.unshift("rounded_cube");
				}

				ui.row([0.5, 0.5]);
				Context.raw.projectType = ui.combo(Id.handle({ position: Context.raw.projectType }), meshList, tr("Template"), true);
				Context.raw.projectAspectRatio = ui.combo(Id.handle({ position: Context.raw.projectAspectRatio }), ["1:1", "2:1", "1:2"], tr("Aspect Ratio"), true);

				@:privateAccess ui.endElement();
				ui.row([0.5, 0.5]);
				if (ui.button(tr("Cancel"))) {
					UIBox.hide();
				}
				if (ui.button(tr("OK")) || ui.isReturnDown) {
					Project.projectNew();
					Viewport.scaleToBounds();
					UIBox.hide();
				}
			}
		});
		#end

		#if is_lab
		Project.projectNew();
		Viewport.scaleToBounds();
		#end
	}

	public static function projectNew(resetLayers = true) {
		#if (krom_windows || krom_linux || krom_darwin)
		Window.get(0).title = Manifest.title;
		#end
		filepath = "";

		#if (is_paint || is_sculpt)
		if (Context.raw.mergedObject != null) {
			Context.raw.mergedObject.remove();
			Data.deleteMesh(Context.raw.mergedObject.data.handle);
			Context.raw.mergedObject = null;
		}
		Context.raw.layerPreviewDirty = true;
		Context.raw.layerFilter = 0;
		Project.meshAssets = [];
		#end

		Viewport.reset();
		Context.raw.paintObject = Context.mainObject();

		Context.selectPaintObject(Context.mainObject());
		for (i in 1...paintObjects.length) {
			var p = paintObjects[i];
			if (p == Context.raw.paintObject) continue;
			Data.deleteMesh(p.data.handle);
			p.remove();
		}
		var meshes = Scene.active.meshes;
		var len = meshes.length;
		for (i in 0...len) {
			var m = meshes[len - i - 1];
			if (Context.raw.projectObjects.indexOf(m) == -1 &&
				m.name != ".ParticleEmitter" &&
				m.name != ".Particle") {
				Data.deleteMesh(m.data.handle);
				m.remove();
			}
		}
		var handle = Context.raw.paintObject.data.handle;
		if (handle != "SceneSphere" && handle != "ScenePlane") {
			Data.deleteMesh(handle);
		}

		if (Context.raw.projectType != ModelRoundedCube) {
			var raw: TMeshData = null;
			if (Context.raw.projectType == ModelSphere || Context.raw.projectType == ModelTessellatedPlane) {
				var mesh: Dynamic = Context.raw.projectType == ModelSphere ?
					new arm.geom.Sphere(1, 512, 256) :
					new arm.geom.Plane(1, 1, 512, 512);
				raw = {
					name: "Tessellated",
					vertex_arrays: [
						{ values: mesh.posa, attrib: "pos", data: "short4norm" },
						{ values: mesh.nora, attrib: "nor", data: "short2norm" },
						{ values: mesh.texa, attrib: "tex", data: "short2norm" }
					],
					index_arrays: [
						{ values: mesh.inda, material: 0 }
					],
					scale_pos: mesh.scalePos,
					scale_tex: mesh.scaleTex
				};
			}
			else {
				Data.getBlob("meshes/" + meshList[Context.raw.projectType] + ".arm", function(b: kha.Blob) {
					raw = iron.system.ArmPack.decode(b.toBytes()).mesh_datas[0];
				});
			}

			var md = new MeshData(raw, function(md: MeshData) {});
			Data.cachedMeshes.set("SceneTessellated", md);

			if (Context.raw.projectType == ModelTessellatedPlane) {
				Viewport.setView(0, 0, 0.75, 0, 0, 0); // Top
			}
		}

		var n = Context.raw.projectType == ModelRoundedCube ? ".Cube" : "Tessellated";
		Data.getMesh("Scene", n, function(md: MeshData) {

			var current = @:privateAccess kha.graphics2.Graphics.current;
			if (current != null) current.end();

			#if is_paint
			Context.raw.pickerMaskHandle.position = MaskNone;
			#end

			Context.raw.paintObject.setData(md);
			Context.raw.paintObject.transform.scale.set(1, 1, 1);
			Context.raw.paintObject.transform.buildMatrix();
			Context.raw.paintObject.name = n;
			paintObjects = [Context.raw.paintObject];
			while (materials.length > 0) materials.pop().unload();
			Data.getMaterial("Scene", "Material", function(m: iron.data.MaterialData) {
				#if (is_paint || is_sculpt)
				materials.push(new MaterialSlot(m));
				#end
				#if is_lab
				materialData = m;
				#end
			});

			#if (is_paint || is_sculpt)
			Context.raw.material = materials[0];
			#end

			arm.ui.UINodes.inst.hwnd.redraws = 2;
			arm.ui.UINodes.inst.groupStack = [];
			materialGroups = [];

			#if (is_paint || is_sculpt)
			brushes = [new BrushSlot()];
			Context.raw.brush = brushes[0];

			fonts = [new FontSlot("default.ttf", App.font)];
			Context.raw.font = fonts[0];
			#end

			Project.setDefaultSwatches();
			Context.raw.swatch = Project.raw.swatches[0];

			Context.raw.pickedColor = Project.makeSwatch();
			Context.raw.colorPickerCallback = null;
			History.reset();

			MakeMaterial.parsePaintMaterial();

			#if (is_paint || is_sculpt)
			RenderUtil.makeMaterialPreview();
			#end

			for (a in assets) Data.deleteImage(a.file);
			assets = [];
			assetNames = [];
			assetMap = [];
			assetId = 0;
			Project.raw.packed_assets = [];
			Context.raw.ddirty = 4;

			#if (is_paint || is_sculpt)
			UIBase.inst.hwnds[TabSidebar0].redraws = 2;
			UIBase.inst.hwnds[TabSidebar1].redraws = 2;
			#end

			if (resetLayers) {

				#if (is_paint || is_sculpt)
				var aspectRatioChanged = layers[0].texpaint.width != Config.getTextureResX() || layers[0].texpaint.height != Config.getTextureResY();
				while (layers.length > 0) layers.pop().unload();
				var layer = new LayerSlot();
				layers.push(layer);
				Context.setLayer(layer);
				if (aspectRatioChanged) {
					iron.App.notifyOnInit(App.resizeLayers);
				}
				#end

				iron.App.notifyOnInit(App.initLayers);
			}

			if (current != null) current.begin(false);

			Context.raw.savedEnvmap = null;
			Context.raw.envmapLoaded = false;
			Scene.active.world.envmap = Context.raw.emptyEnvmap;
			Scene.active.world.raw.envmap = "World_radiance.k";
			Context.raw.showEnvmapHandle.selected = Context.raw.showEnvmap = false;
			Scene.active.world.probe.radiance = Context.raw.defaultRadiance;
			Scene.active.world.probe.radianceMipmaps = Context.raw.defaultRadianceMipmaps;
			Scene.active.world.probe.irradiance = Context.raw.defaultIrradiance;
			Scene.active.world.probe.raw.strength = 4.0;

			#if (is_paint || is_sculpt)
			Context.initTool();
			#end
		});

		#if (kha_direct3d12 || kha_vulkan || kha_metal)
		arm.render.RenderPathRaytrace.ready = false;
		#end
	}

	#if (is_paint || is_sculpt)
	public static function importMaterial() {
		UIFiles.show("arm,blend", false, true, function(path: String) {
			path.endsWith(".blend") ?
				ImportBlendMaterial.run(path) :
				ImportArm.runMaterial(path);
		});
	}

	public static function importBrush() {
		UIFiles.show("arm," + Path.textureFormats.join(","), false, true, function(path: String) {
			// Create brush from texture
			if (Path.isTexture(path)) {
				// Import texture
				ImportAsset.run(path);
				var assetIndex = 0;
				for (i in 0...Project.assets.length) {
					if (Project.assets[i].file == path) {
						assetIndex = i;
						break;
					}
				}

				// Create a new brush
				Context.raw.brush = new BrushSlot();
				Project.brushes.push(Context.raw.brush);

				// Create and link image node
				var n = NodesBrush.createNode("TEX_IMAGE");
				n.x = 83;
				n.y = 340;
				n.buttons[0].default_value = assetIndex;
				var links = Context.raw.brush.canvas.links;
				links.push({
					id: Context.raw.brush.nodes.getLinkId(links),
					from_id: n.id,
					from_socket: 0,
					to_id: 0,
					to_socket: 4
				});

				// Parse brush
				MakeMaterial.parseBrush();
				UINodes.inst.hwnd.redraws = 2;
				function _init() {
					RenderUtil.makeBrushPreview();
				}
				iron.App.notifyOnInit(_init);
			}
			// Import from project file
			else {
				ImportArm.runBrush(path);
			}
		});
	}
	#end

	public static function importMesh(replaceExisting = true, done: Void->Void = null) {
		UIFiles.show(Path.meshFormats.join(","), false, false, function(path: String) {
			importMeshBox(path, replaceExisting, true, done);
		});
	}

	public static function importMeshBox(path: String, replaceExisting = true, clearLayers = true, done: Void->Void = null) {

		#if krom_ios
		// Import immediately while access to resource is unlocked
		// Data.getBlob(path, function(b: kha.Blob) {});
		#end

		UIBox.showCustom(function(ui: Zui) {
			var tabVertical = Config.raw.touch_ui;
			if (ui.tab(Id.handle(), tr("Import Mesh"), tabVertical)) {
			
				//open file and check if the first 3 lines are obj8 format header, set variable to true if so
				var isObj8 = false;
				
				if (path.toLowerCase().endsWith(".obj")) {
					Data.getBlob(path, function(b) {	

						var input = new haxe.io.BytesInput(b.bytes);
						var char = input.readLine();
						if(char == "I" || char == "A"){
							char = input.readLine();
							if(char == "800"){
								char = input.readLine();
								if(char == "OBJ"){
									isObj8 = true;
								}
							}
						}
					});
					Data.deleteBlob(path);
					if(isObj8 == true){
						replaceExisting = !ui.check(Id.handle({selected: !Context.raw.parseTransform}), tr("Append")); //show "Append" clickbox if the mesh is obj8 format
						if (ui.isHovered) ui.tooltip(tr("Append new mesh to existing"));	
					}
					else{									  
						Context.raw.splitBy = ui.combo(Id.handle(), [
							tr("Object"),
							tr("Group"),
							tr("Material"),
							tr("UDIM Tile"),
						], tr("Split By"), true);
						if (ui.isHovered) ui.tooltip(tr("Split .obj mesh into objects"));
					}
				}

				if (path.toLowerCase().endsWith(".fbx")) {
					Context.raw.parseTransform = ui.check(Id.handle({ selected: Context.raw.parseTransform }), tr("Parse Transforms"));
					if (ui.isHovered) ui.tooltip(tr("Load per-object transforms from .fbx"));
				}

				#if (is_paint || is_sculpt)
				if (path.toLowerCase().endsWith(".fbx") || path.toLowerCase().endsWith(".blend")) {
					Context.raw.parseVCols = ui.check(Id.handle({ selected: Context.raw.parseVCols }), tr("Parse Vertex Colors"));
					if (ui.isHovered) ui.tooltip(tr("Import vertex color data"));
				}
				#end

				ui.row([0.45, 0.45, 0.1]);
				if (ui.button(tr("Cancel"))) {
					UIBox.hide();
				}
				if (ui.button(tr("Import")) || ui.isReturnDown) {
					UIBox.hide();
					function doImport() {
						#if (is_paint || is_sculpt)
						if(isObj8 == true)	ImportMesh.run(path, clearLayers, replaceExisting, isObj8);
						else ImportMesh.run(path, clearLayers, replaceExisting);
						#end
						#if is_lab
						if(isObj8 == true)	ImportMesh.run(path, replaceExisting, isObj8);
						else ImportMesh.run(path, replaceExisting);
						#end
						if (done != null) done();
					}
					#if (krom_android || krom_ios)
					arm.App.notifyOnNextFrame(function() {
						Console.toast(tr("Importing mesh"));
						arm.App.notifyOnNextFrame(doImport);
					});
					#else
					doImport();
					#end
				}
				if (ui.button(tr("?"))) {
					File.loadUrl("https://github.com/armory3d/armorpaint_docs/blob/master/faq.md");
				}
			}
		});
		UIBox.clickToHide = false; // Prevent closing when going back to window from file browser
	}

	public static function reimportMesh() {
		if (Project.meshAssets != null && Project.meshAssets.length > 0 && File.exists(Project.meshAssets[0])) {
			importMeshBox(Project.meshAssets[0], true, false);
		}
		else importAsset();
	}

	public static function unwrapMeshBox(mesh: Dynamic, done: Dynamic->Void, skipUI = false) {
		UIBox.showCustom(function(ui: Zui) {
			var tabVertical = Config.raw.touch_ui;
			if (ui.tab(Id.handle(), tr("Unwrap Mesh"), tabVertical)) {

				var unwrapPlugins = [];
				if (BoxPreferences.filesPlugin == null) {
					BoxPreferences.fetchPlugins();
				}
				for (f in BoxPreferences.filesPlugin) {
					if (f.indexOf("uv_unwrap") >= 0 && f.endsWith(".js")) {
						unwrapPlugins.push(f);
					}
				}
				unwrapPlugins.push("equirect");

				var unwrapBy = ui.combo(Id.handle(), unwrapPlugins, tr("Plugin"), true);

				ui.row([0.5, 0.5]);
				if (ui.button(tr("Cancel"))) {
					UIBox.hide();
				}
				if (ui.button(tr("Unwrap")) || ui.isReturnDown || skipUI) {
					UIBox.hide();
					function doUnwrap() {
						if (unwrapBy == unwrapPlugins.length - 1) {
							MeshUtil.equirectUnwrap(mesh);
						}
						else {
							var f = unwrapPlugins[unwrapBy];
							if (Config.raw.plugins.indexOf(f) == -1) {
								Config.enablePlugin(f);
								Console.info(f + " " + tr("plugin enabled"));
							}
							MeshUtil.unwrappers.get(f)(mesh);
						}
						done(mesh);
					}
					#if (krom_android || krom_ios)
					arm.App.notifyOnNextFrame(function() {
						Console.toast(tr("Unwrapping mesh"));
						arm.App.notifyOnNextFrame(doUnwrap);
					});
					#else
					doUnwrap();
					#end
				}
			}
		});
	}

	public static function importAsset(filters: String = null, hdrAsEnvmap = true) {
		if (filters == null) filters = Path.textureFormats.join(",") + "," + Path.meshFormats.join(",");
		UIFiles.show(filters, false, true, function(path: String) {
			ImportAsset.run(path, -1.0, -1.0, true, hdrAsEnvmap);
		});
	}

	public static function importSwatches(replaceExisting = false) {
		UIFiles.show("arm,gpl", false, false, function(path: String) {
			if (Path.isGimpColorPalette(path)) ImportGpl.run(path, replaceExisting);
			else ImportArm.runSwatches(path, replaceExisting);
		});
	}

	public static function reimportTextures() {
		for (asset in Project.assets) {
			reimportTexture(asset);
		}
	}

	public static function reimportTexture(asset: TAsset) {
		function load(path: String) {
			asset.file = path;
			var i = Project.assets.indexOf(asset);
			Data.deleteImage(asset.file);
			Project.assetMap.remove(asset.id);
			var oldAsset = Project.assets[i];
			Project.assets.splice(i, 1);
			Project.assetNames.splice(i, 1);
			ImportTexture.run(asset.file);
			Project.assets.insert(i, Project.assets.pop());
			Project.assetNames.insert(i, Project.assetNames.pop());

			#if (is_paint || is_sculpt)
			if (Context.raw.texture == oldAsset) Context.raw.texture = Project.assets[i];
			#end

			function _next() {
				MakeMaterial.parsePaintMaterial();

				#if (is_paint || is_sculpt)
				RenderUtil.makeMaterialPreview();
				UIBase.inst.hwnds[TabSidebar1].redraws = 2;
				#end
			}
			App.notifyOnNextFrame(_next);
		}
		if (!File.exists(asset.file)) {
			var filters = Path.textureFormats.join(",");
			UIFiles.show(filters, false, false, function(path: String) {
				load(path);
			});
		}
		else load(asset.file);
	}

	public static function getImage(asset: TAsset): Image {
		return asset != null ? Project.assetMap.get(asset.id) : null;
	}

	#if (is_paint || is_sculpt)
	public static function getUsedAtlases(): Array<String> {
		if (Project.atlasObjects == null) return null;
		var used: Array<Int> = [];
		for (i in Project.atlasObjects) if (used.indexOf(i) == -1) used.push(i);
		if (used.length > 1) {
			var res: Array<String> = [];
			for (i in used) res.push(Project.atlasNames[i]);
			return res;
		}
		else return null;
	}

	public static function isAtlasObject(p: MeshObject): Bool {
		if (Context.raw.layerFilter <= Project.paintObjects.length) return false;
		var atlasName = getUsedAtlases()[Context.raw.layerFilter - Project.paintObjects.length - 1];
		var atlasI = Project.atlasNames.indexOf(atlasName);
		return atlasI == Project.atlasObjects[Project.paintObjects.indexOf(p)];
	}

	public static function getAtlasObjects(objectMask: Int): Array<MeshObject> {
		var atlasName = Project.getUsedAtlases()[objectMask - Project.paintObjects.length - 1];
		var atlasI = Project.atlasNames.indexOf(atlasName);
		var visibles: Array<MeshObject> = [];
		for (i in 0...Project.paintObjects.length) if (Project.atlasObjects[i] == atlasI) visibles.push(Project.paintObjects[i]);
		return visibles;
	}
	#end

	public static function packedAssetExists(packed_assets: Array<TPackedAsset>, name: String): Bool {
		for (pa in packed_assets) if (pa.name == name) return true;
		return false;
	}

	public static function exportSwatches() {
		UIFiles.show("arm,gpl", true, false, function(path: String) {
			var f = UIFiles.filename;
			if (f == "") f = tr("untitled");
			if (Path.isGimpColorPalette(f)) ExportGpl.run(path + Path.sep + f, f.substring(0, f.lastIndexOf(".")), Project.raw.swatches);
			else ExportArm.runSwatches(path + Path.sep + f);
		});
	}

	public static function makeSwatch(base = 0xffffffff): TSwatchColor {
		return { base: base, opacity: 1.0, occlusion: 1.0, roughness: 0.0, metallic: 0.0, normal: 0xff8080ff, emission: 0.0, height: 0.0, subsurface: 0.0 };
	}

	public static function cloneSwatch(swatch: TSwatchColor): TSwatchColor {
		return { base: swatch.base, opacity: swatch.opacity, occlusion: swatch.occlusion, roughness: swatch.roughness, metallic: swatch.metallic, normal: swatch.normal, emission: swatch.emission, height: swatch.height, subsurface: swatch.subsurface };
	}

	public static function setDefaultSwatches() {
		// 32-Color Palette by Andrew Kensler
		// http://eastfarthing.com/blog/2016-05-06-palette/
		Project.raw.swatches = [];
		var colors = [0xffffffff, 0xff000000, 0xffd6a090, 0xffa12c32, 0xfffa2f7a, 0xfffb9fda, 0xffe61cf7, 0xff992f7c, 0xff47011f, 0xff051155, 0xff4f02ec, 0xff2d69cb, 0xff00a6ee, 0xff6febff, 0xff08a29a, 0xff2a666a, 0xff063619, 0xff4a4957, 0xff8e7ba4, 0xffb7c0ff, 0xffacbe9c, 0xff827c70, 0xff5a3b1c, 0xffae6507, 0xfff7aa30, 0xfff4ea5c, 0xff9b9500, 0xff566204, 0xff11963b, 0xff51e113, 0xff08fdcc];
		for (c in colors) Project.raw.swatches.push(Project.makeSwatch(c));
	}

	public static function getMaterialGroupByName(groupName: String): TNodeGroup {
		for (g in materialGroups) if (g.canvas.name == groupName) return g;
		return null;
	}

	#if (is_paint || is_sculpt)
	public static function isMaterialGroupInUse(group: TNodeGroup): Bool {
		var canvases: Array<TNodeCanvas> = [];
		for (m in materials) canvases.push(m.canvas);
		for (m in materialGroups) canvases.push(m.canvas);
		for (canvas in canvases) {
			for (n in canvas.nodes) {
				if (n.type == "GROUP" && n.name == group.canvas.name) {
					return true;
				}
			}
		}
		return false;
	}
	#end
}

typedef TNodeGroup = {
	public var nodes: Nodes;
	public var canvas: TNodeCanvas;
}
