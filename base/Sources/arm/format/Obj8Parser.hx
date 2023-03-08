package arm.format;

import iron.math.Vec4;
import iron.math.Vec3;
import iron.math.Vec2;
import iron.math.Quat;
import iron.math.Mat4;

class Obj8_vtx {
	public var vtx: iron.math.Vec3 = null;
	public var nor: iron.math.Vec3 = null;
	public var tex: iron.math.Vec2 = null;
	public var name: String = null;
	
	public function new(vtx:Vec3, nor:Vec3, tex:Vec2) {
		this.vtx = vtx;
		this.nor = nor;
		this.tex = tex;
	}
	
	public function clone(){
		return new Obj8_vtx(this.vtx.clone(), this.nor.clone(), this.tex.clone());
	}
}

typedef RotateKey = { value : Float, angle : Float }
typedef TransKey = { value : Float, vector : Vec4 }

class Obj8_Anim {
	public var animData : Array<Dynamic> = null;
	public var transTable : Array<TransKey> = null;
	public var rotateTable : Array<RotateKey> = null;
	public var helper_vec : iron.math.Vec4 = null; 
	public var animOpen: Bool ;
	public var lineNumber : Int;
	public var animTransOpen: Bool = false;
	public var animRotateOpen: Bool = false;
	
	public var parent :  Obj8_Anim = null;
	
	public function new(parent: Obj8_Anim, lineNumber : Int) {
			this.parent = parent;
			this.animOpen = true;
			this.lineNumber = lineNumber;
			this.animData = new Array<Dynamic>();
	}		
}

class Obj8Parser {

	public var posa: kha.arrays.Int16Array = null;
	public var nora: kha.arrays.Int16Array = null;
	public var texa: kha.arrays.Int16Array = null;
	public var inda: kha.arrays.Uint32Array = null;
	public var scalePos = 1.0;
	public var scaleTex = 1.0;
	public var name = "";
	public var curObj = 0;
	public var curObjName = "";
	
	var vtxTable: Array<Obj8_vtx> = [];
	var idxTable: Array<Int> = [];
	var objTable: Array<Array<Obj8_vtx>> = [];


	public function new(blob: kha.Blob) {

		var input = new haxe.io.BytesInput(blob.bytes);
		var lineNumber:Int = 0;
		while (input.position < input.length){
			
			var line = trimstr(input.readLine());
			
			var str = line.split(" ");
			lineNumber = lineNumber + 1;
			if (str[0] == "VT"){
			var vtx  = new Obj8_vtx(new Vec3(Std.parseFloat(str[1]), -Std.parseFloat(str[3]), Std.parseFloat(str[2])), new Vec3(Std.parseFloat(str[4]), -Std.parseFloat(str[6]), Std.parseFloat(str[5])), new Vec2(Std.parseFloat(str[7]), 1 - Std.parseFloat(str[8])));
				vtxTable.push(vtx);
			}
			else if (str[0] == "IDX10"){
				for(i in 1...11){
					idxTable.push(Std.parseInt(str[i]));
				}
			}
			else if (str[0] == "IDX"){
				idxTable.push(Std.parseInt(str[1]));
			}
			else if (str[0] == "ANIM_begin"){
					var anim = new Obj8_Anim(null, lineNumber);
					parseAnim(input, lineNumber, anim);
					if(anim.animOpen == true){
						trace("Obj8Parser: Animation parsing error. Animation at line %i not closed", anim.lineNumber);
					}
			}
			else if (str[0] == "TRIS"){
				var startIdx = Std.parseInt(str[1]);
				var offsetIdx = Std.parseInt(str[2]);
				var endIdx = startIdx + offsetIdx;
				var tmpObj = new Array<Obj8_vtx>(); 
				var name = new String("TRIS_"+str[1]+"_"+str[2]);	
				//Unoptimize	
				for (i in startIdx...endIdx) {
					var vtx = vtxTable[idxTable[i]].clone();
					tmpObj.push(vtx);
				}
				tmpObj[0].name = name;
				objTable.push(tmpObj);
			}
		}

		next();
	}
	
	public function next(): Bool {
		
		if(curObj >= objTable.length) return false;
		
		posa = new kha.arrays.Int16Array(objTable[curObj].length * 4);
		inda = new kha.arrays.Uint32Array(objTable[curObj].length);
		nora = new kha.arrays.Int16Array(objTable[curObj].length * 2);
		texa = new kha.arrays.Int16Array(objTable[curObj].length * 2);

		curObjName = objTable[curObj][0].name;
		// Pack positions to (-1, 1) range
		scalePos = 0.0;		
		for(v in objTable[curObj]){
				var f = Math.abs(v.vtx.x);
				if (scalePos < f) scalePos = f;
				f = Math.abs(v.vtx.y);
				if (scalePos < f) scalePos = f;
				f = Math.abs(v.vtx.z);
				if (scalePos < f) scalePos = f;
		}
		var inv = 32767 * (1 / scalePos);
		
		var idx = 0;
		var ind = objTable[curObj].length - 1;
		while(ind >= 0 ){
			posa[idx * 4	] = Std.int( objTable[curObj][ind].vtx.x*inv);
			posa[idx * 4 + 1] = Std.int( objTable[curObj][ind].vtx.y*inv);
			posa[idx * 4 + 2] = Std.int( objTable[curObj][ind].vtx.z*inv);
			
			nora[idx * 2    ] = Std.int( objTable[curObj][ind].nor.x * 32767);
			nora[idx * 2 + 1] = Std.int( objTable[curObj][ind].nor.y * 32767);
			posa[idx * 4 + 3] = Std.int( objTable[curObj][ind].nor.z * 32767);

			texa[idx * 2    ] = Std.int( objTable[curObj][ind].tex.x  * 32767);
			texa[idx * 2 + 1] = Std.int( (objTable[curObj][ind].tex.y) * 32767);
				
			
			inda[idx] = idx;
			idx++;
			ind--;
		}
		curObj++;
		return true;
	}
	
	function parseAnim(input: haxe.io.BytesInput, lineNumber: Int, anim_obj : Obj8_Anim){

		while (input.position < input.length){
			
			var line = trimstr(input.readLine());
			
			var str = line.split(" ");
			lineNumber = lineNumber + 1;
			if (str[0] == "ANIM_begin"){
					var anim = new Obj8_Anim(anim_obj, lineNumber);
					parseAnim(input, lineNumber, anim);
					if(anim.animOpen == true){
						trace("Obj8Parser: Animation parsing error. Animation beginig at line %i not closed", anim.lineNumber);
					}
			}		
			if (str[0] == "ANIM_rotate_begin"){
					anim_obj.helper_vec = new Vec4(Std.parseFloat(str[1]), -Std.parseFloat(str[3]), Std.parseFloat(str[2]));
					anim_obj.animRotateOpen = true;
					anim_obj.rotateTable = new Array<RotateKey>();
			}	
 			if (str[0] == "ANIM_trans_begin"){
					anim_obj.animTransOpen = true;
					anim_obj.transTable = new Array<TransKey>();
			}
			else if (str[0] == "ANIM_rotate_key"){
				var angle = Std.parseFloat(str[2]);
				var rot:RotateKey = {value: Std.parseFloat(str[1]), angle: angle};
				anim_obj.rotateTable.push(rot);
			}
			else if (str[0] == "ANIM_trans_key"){
				var vec = new Vec4(Std.parseFloat(str[2]), -Std.parseFloat(str[4]), Std.parseFloat(str[3]));
				var trans:TransKey = {value:Std.parseFloat(str[1]), vector:vec};
				anim_obj.transTable.push(trans); 
			}
			else if (str[0] == "ANIM_trans"){
				//Find the position coresponding to datafef value 0
				var trans = new Vec4(Std.parseFloat(str[1]), -Std.parseFloat(str[3]), Std.parseFloat(str[2]));
				var trans2 = new Vec4(Std.parseFloat(str[4]), -Std.parseFloat(str[6]), Std.parseFloat(str[5]));
				if(trans.equals(trans2)){

					anim_obj.animData.push(trans);
				}
				else{
					var dr1 = Std.parseFloat(str[7]);
					var dr2 = Std.parseFloat(str[8]);
					if(dr1 == 0){
						anim_obj.animData.push(trans);
					}
					else if(dr2 == 0){
						anim_obj.animData.push(trans2);
					}
					else{
						var range = Math.abs(dr1 - dr2);
						var diff =  Math.abs(0 - dr1);
						var ratio = diff/range;
						var interp = new Vec4();
						interp.lerp(trans, trans2, ratio);
						anim_obj.animData.push(interp);
					}
				}
			}
			else if (str[0] == "ANIM_rotate"){
				//Find the angle coresponding to datafef value 0
				var angle = Std.parseFloat(str[4]);
				var angle2 = Std.parseFloat(str[5]);
				var axis = new Vec4(Std.parseFloat(str[1]), -Std.parseFloat(str[3]), Std.parseFloat(str[2]));
				if(angle == angle2){

					var q = new Quat();
					q.fromAxisAngle(axis.normalize(), angle*(Math.PI/180));
					anim_obj.animData.push(q.normalize());
				}

				else{
					var dr1 = Std.parseFloat(str[6]);
					var dr2 = Std.parseFloat(str[7]);
					if(dr1 == 0){

						var q = new Quat();
						q.fromAxisAngle(axis.normalize(), angle*(Math.PI/180));
						anim_obj.animData.push(q.normalize());
					}
					else if(dr2 == 0){

						var q = new Quat();
						q.fromAxisAngle(axis.normalize(), angle2*(Math.PI/180));
						anim_obj.animData.push(q.normalize());
					}
					else{
						var range = Math.abs(dr1 - dr2);
						var diff =  Math.abs(0 - dr1);
						var ratio = diff/range;

							var angle = (angle + (angle2 - angle) * ratio);
							var q = new Quat();
							q.fromAxisAngle(axis.normalize(), angle*(Math.PI/180));
							anim_obj.animData.push(q);							
						
					}
				}								
			}
			else if (str[0] == "TRIS"){
				var startIdx = Std.parseInt(str[1]);
				var offsetIdx = Std.parseInt(str[2]);
				var endIdx = startIdx + offsetIdx;
				var tmpObj = new Array<Obj8_vtx>(); 
				var name = new String("TRIS_"+str[1]+"_"+str[2]);
					
				//Unoptimize	
				for (i in startIdx...endIdx) {
					var vtx = vtxTable[idxTable[i]].clone();
					
 					var obj = anim_obj;
					while(true){
						//Apply transforms in backwards order
						var index = obj.animData.length - 1;
						while(index >= 0){
							if(Std.isOfType(obj.animData[index], iron.math.Vec4)){
								vtx.vtx.add(obj.animData[index]);
							}else{
								var mat = Mat4.identity();
								mat.fromQuat(obj.animData[index]);
								vtx.vtx.applymat(mat);
								vtx.nor.applymat(mat);
								vtx.nor.normalize();
							}
							index = index - 1;
						}
						if(obj.parent == null) break;
						obj = obj.parent;
					}  				
					tmpObj.push(vtx);
				}
		
				tmpObj[0].name = name;			
				objTable.push(tmpObj);							
			}
 			else if (str[0] == "ANIM_trans_end"){
				if(anim_obj.animTransOpen == false){
					trace("Obj8Parser: Missing ANIM_trans_begin error at line %i", lineNumber);
					continue;
				}
				anim_obj.animTransOpen = false;
				
				//Try to find keyframe 0. If does not exist interpolate.
				var key1:Float = anim_obj.transTable[0].value;
				var key2:Float = anim_obj.transTable[anim_obj.transTable.length-1].value;
				
				if(key1 == 0){
					anim_obj.animData.push(anim_obj.transTable[0].vector);
				}
				else if(key2 == 0){
					anim_obj.animData.push(anim_obj.transTable[anim_obj.transTable.length-1].vector);
				}
				else if((0 - key1) * key2 > 0){//0 is in range
					for(i in 0 ... anim_obj.transTable.length - 1){
						key1 = anim_obj.transTable[i].value;
						key2 = anim_obj.transTable[i+1].value;
						if((0 - key1) * key2 > 0){
							var range = Math.abs(key1 - key2);
							var diff =  Math.abs(0 - key1);
							var ratio = diff/range;
							var interp = new Vec4();
							interp.lerp(anim_obj.transTable[i].vector, anim_obj.transTable[i+1].vector, ratio);
							anim_obj.animData.push(interp);
							break;
						}
					}					
				}			
				else{//0 is not in range
					var ind1:Int = 0;
					var ind2:Int = 1;
					if(0 < key1){
						key2 = anim_obj.transTable[1].value;
					}
					else if (0 > key2){
						key1 = anim_obj.transTable[anim_obj.transTable.length-2].value;
						ind1 = anim_obj.transTable.length-2;
						ind2 = anim_obj.transTable.length-1;
					}
					
					var range = Math.abs(key1 - key2);
					var diff =  Math.abs(0 - key1);
					var ratio = diff/range;
					var interp = new Vec4();
					interp.lerp(anim_obj.transTable[ind1].vector, anim_obj.transTable[ind2].vector, ratio);
					anim_obj.animData.push(interp);		
				}
			}
 			else if (str[0] == "ANIM_rotate_end"){
				if(anim_obj.animRotateOpen == false){
					trace("Obj8Parser: Missing ANIM_rotate_begin error at line %i", lineNumber);
					continue;
				}
				anim_obj.animRotateOpen = false;
				
				//Try to find keyframe 0. If does not exist interpolate.
				var key1:Float = anim_obj.rotateTable[0].value;
				var key2:Float = anim_obj.rotateTable[anim_obj.rotateTable.length-1].value;
				
				if(key1 == 0){
				var q = new Quat();
				q.fromAxisAngle(anim_obj.helper_vec.normalize(), anim_obj.rotateTable[0].angle*(Math.PI/180));
					anim_obj.animData.push(q);
				}
				else if(key2 == 0){
				var q = new Quat();
				q.fromAxisAngle(anim_obj.helper_vec.normalize(), anim_obj.rotateTable[anim_obj.rotateTable.length-1].angle*(Math.PI/180));
					anim_obj.animData.push(q);
				}
				else if((0 - key1) * key2 > 0){//0 is in range
					for(i in 0 ... anim_obj.rotateTable.length - 1){
						key1 = anim_obj.rotateTable[i].value;
						key2 = anim_obj.rotateTable[i+1].value;
						if(key1 == 0){//Keyframe 0 exists in the table
							var q = new Quat();
							q.fromAxisAngle(anim_obj.helper_vec.normalize(), anim_obj.rotateTable[i].angle*(Math.PI/180));
							anim_obj.animData.push(q);	
							break;
						}
						if((0 - key1) * key2 > 0){
							var range = Math.abs(key1 - key2);
							var diff =  0 - key1;
							var ratio = diff/range;					
							
							var angle = (anim_obj.rotateTable[i].angle + (anim_obj.rotateTable[i+1].angle - anim_obj.rotateTable[i].angle) * ratio);
							var q = new Quat();
							q.fromAxisAngle(anim_obj.helper_vec.normalize(), angle*(Math.PI/180));
							anim_obj.animData.push(q);				
							
							break;
						}
					}					
				}			
				else{//0 is not in range
					var ind1:Int = 0;
					var ind2:Int = 1;
					if(0 < key1){
						key2 = anim_obj.rotateTable[1].value;
					}
					else if (0 > key2){
						key1 = anim_obj.rotateTable[anim_obj.rotateTable.length-2].value;
						ind1 = anim_obj.rotateTable.length-2;
						ind2 = anim_obj.rotateTable.length-1;
					}
					
					var range = Math.abs(key1 - key2);
					var diff =  (0 - key1);
					var ratio = diff/range;
					
					var angle = (anim_obj.rotateTable[ind1].angle + (anim_obj.rotateTable[ind2].angle - anim_obj.rotateTable[ind1].angle) * ratio);
					var q = new Quat();
					q.fromAxisAngle(anim_obj.helper_vec.normalize(), angle*(Math.PI/180));
					anim_obj.animData.push(q);	
				}
			}
			else if (str[0] == "ANIM_end"){
				if(anim_obj.animRotateOpen == true){
					trace("Obj8Parser: ANIM_rotate_begin not closed. Line %i", lineNumber);
				}	
				if(anim_obj.animTransOpen == true){
					trace("Obj8Parser: ANIM_trans_begin not closed. Line %i", lineNumber);
				}				
				anim_obj.animOpen = false;
				break;
			}
		}	
	}
	
	function trimstr(str: String) : String{
	//different exporters add white spaces and tabs all over the place.
      if (str.length == 0)
          return str;

      var sb = new String("");
      var needWhiteSpace = false;
      for (pos in 0...str.length) {
         if (str.isSpace(pos)) {
            if (sb.length > 0)
               needWhiteSpace = true;
            continue;
         } else if (needWhiteSpace && pos < str.length) {
            sb = sb + " ";
            needWhiteSpace = false;
         }
         sb += str.charAt(pos);
      }
      return sb;
		
	}
}
