package arm.io;

import kha.Blob;
import iron.data.Data;
import arm.format.Obj8Parser;
import arm.ui.UISidebar;

class ImportObj8 {

	public static function run(path: String, replaceExisting = true) {

		Data.getBlob(path, function(b: Blob) {

			var obj = new Obj8Parser(b);
			var filename = path.split("\\").pop().split("/").pop().split(".").shift();
			obj.name = filename  + "." + obj.curObj;
			replaceExisting ? ImportMesh.makeMesh(obj, path) : ImportMesh.addMesh(obj);
			while (obj.next()) {
				obj.name = filename + "." + obj.curObj;
				ImportMesh.addMesh(obj);
			}
			Data.deleteBlob(path);
		});
	}
}
