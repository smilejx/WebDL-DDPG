package webdl.core;
import haxe.ds.Vector;
import webdl.core.backend.Backend;
import webdl.core.graph.Node;
//import webdl.core.backend.gpu.GpuAtomicOperation;

/**
 * N-dimensional tensor.
 */
class Tensor {
	/**
	 * The number of indices required to access each element of the tensor.
	 * `0` for a scalar, `1` for a vector, `2` for a matrix, and so on.
	 */
	public var rank(default, null):Int;

	/**
	 * The number of elements of the tensor. `-1` if the size is undetermined.
	 */
	public var size(default, null):Int;

	/**
	 * The shape of the tensor, representing the size of each dimension.
	 * `-1` for variable dimension size.
	 */
	public var shape(default, null):Vector<Int>;

	/**
	 * Whether the tensor is trainable.
	 */
	public var trainable:Bool;

	/**
	 * TODO: write doc
	 */
	public var shouldBeSaved:Bool;

	/**
	 * Whether to apply normalizations to the tensor.
	 */
	public var doNotDecay:Bool;

	@:allow(webdl.core)
	var node:Node;

	@:allow(webdl.core)
	var actualSize:Int;
	@:allow(webdl.core)
	var actualShape:Vector<Int>;
	@:allow(webdl.core)
	var data:TensorData;

	@:allow(webdl.core)
	var backend:Backend;

	/**
	 * Creates a tensor of `shape`.
	 */
	public function new(backend:Backend, shape:Array<Int>) {
		this.backend = backend;
		this.shape = Vector.fromArrayCopy(shape);
		this.rank = shape.length;
		if (rank > 4) throw "rank too high";
		size = 1;
		for (i in 0...rank) {
			if (shape[i] == -1) {
				size = -1;
				break;
			}
			size *= shape[i];
		}

		actualSize = size;
		actualShape = this.shape.copy();

		if (size != -1) {
			data = backend.requestTensorData(size);
			data.clearValue(0);
			data.clearDiff(0);
		}

		node = new Node(this);

		trainable = false;
		shouldBeSaved = false;
		doNotDecay = false;
	}

	/**
	 * Assigns the value. `value` should be `Float` or float `Array` of proper dimension.
	 */
	public function set(value:Any):Void {
		switch (rank) {
			case 0: return set0D(cast value);
			case 1: return set1D(cast value);
			case 2: return set2D(cast value);
			case 3: return set3D(cast value);
			case _: return set4D(cast value);
		}
	}

	/**
	 * Assigns the 0-D value (scalar).
	 */
	public function set0D(value:Float):Void {
		if (rank != 0) throw "ranks mismatch";
		assignShape([]);
		data.setValue([value]);
	}

	/**
	 * Assigns the 1-D value (vector).
	 */
	public function set1D(value:Array<Float>):Void {
		if (rank != 1) throw "ranks mismatch";
		assignShape([value.length]);
		sizeCheck();
		data.setValue(value);
	}

	/**
	 * Assigns the 2-D value (matrix).
	 */
	public function set2D(value:Array<Array<Float>>):Void {
		if (rank != 2) throw "ranks mismatch";
		assignShape([value.length, value[0].length]);
		data.setValue(flatten(value));
	}

	/**
	 * Assigns the 3-D value.
	 */
	public function set3D(value:Array<Array<Array<Float>>>):Void {
		if (rank != 3) throw "ranks mismatch";
		assignShape([value.length, value[0].length, value[0][0].length]);
		data.setValue(flatten(flatten(value)));
	}

	/**
	 * Assigns the 4-D value.
	 */
	public function set4D(value:Array<Array<Array<Array<Float>>>>):Void {
		if (rank != 4) throw "ranks mismatch";
		assignShape([value.length, value[0].length, value[0][0].length, value[0][0][0].length]);
		data.setValue(flatten(flatten(flatten(value))));
	}

	/**
	 * Assigns the flattened data `array` to the tensor. This method can be used regardless of the rank, but
	 * the length of the array must match the total number of elements of the tensor.
	 */
	public function setArray(array:Array<Float>):Void {
		if (actualSize == -1) throw "cannot assign flattened data to a tensor of ambiguous shape";
		if (actualSize != array.length) throw "data sizes mismatch";
		data.setValue(array);
	}

	/**
	 * Sets all elements to `value`.
	 */
	public function fill(value:Float):Void {
		if (actualSize == -1) throw "cannot fill a tensor of ambiguous shape";
		data.clearValue(value);
	}

	/**
	 * Sets all values to a value generated by `valueGen`.
	 */
	public function fillByGenerator(valueGen:Void -> Float):Void {
		if (actualSize == -1) throw "cannot fill a tensor of ambiguous shape";
		data.setValue([for (i in 0...actualSize) valueGen()]);
	}

	@:allow(webdl.core)
	function fillDiff(diff:Float):Void {
		if (actualSize == -1) throw "cannot fill a tensor of ambiguous shape";
		data.clearDiff(diff);
	}

	/**
	 * Returns the value as an array of proper dimension.
	 */
	public function get():Any {
		switch (rank) {
			case 0: return get0D();
			case 1: return get1D();
			case 2: return get2D();
			case 3: return get3D();
			case _: return get4D();
		}
	}

	/**
	 * Returns the 0-D value (scalar).
	 */
	public function get0D():Float {
		if (rank != 0) throw "dimensions mismatch";
		if (actualSize == -1) throw "no data assigned";
		return reshape0D(data.getValue(actualSize));
	}

	/**
	 * Returns the 1-D value (vector).
	 */
	public function get1D():Array<Float> {
		if (rank != 1) throw "dimensions mismatch";
		if (actualSize == -1) throw "no data assigned";
		return reshape1D(data.getValue(actualSize));
	}

	/**
	 * Returns the 2-D value (matrix).
	 */
	public function get2D():Array<Array<Float>> {
		if (rank != 2) throw "dimensions mismatch";
		if (actualSize == -1) throw "no data assigned";
		return reshape2D(data.getValue(actualSize));
	}

	/**
	 * Returns the 3-D value.
	 */
	public function get3D():Array<Array<Array<Float>>> {
		if (rank != 3) throw "dimensions mismatch";
		if (actualSize == -1) throw "no data assigned";
		return reshape3D(data.getValue(actualSize));
	}

	/**
	 * Returns the 4-D value.
	 */
	public function get4D():Array<Array<Array<Array<Float>>>> {
		if (rank != 4) throw "dimensions mismatch";
		if (actualSize == -1) throw "no data assigned";
		return reshape4D(data.getValue(actualSize));
	}

	/**
	 * Returns the flattened data of the tensor. This method can be used regardless of the rank, and
	 * the length of the returned array is equal to the total number of elements of the tensor.
	 */
	public function getArray():Array<Float> {
		if (actualSize == -1) throw "no data assigned";
		return data.getValue(actualSize);
	}

	/**
	 * Returns the string representation of the value.
	 */
	public function print():String {
		switch (rank) {
		case 0:
			var v = get0D();
			return "" + v;
		case 1:
			var v = get1D();
			return
				"[" + v.join(", ") + "]"
			;
		case 2:
			var v = get2D();
			return
				"[\n" + v.map((a) ->
					"  [" + a.join(", ") + "]"
				).join(",\n") + "\n]"
			;
		case 3:
			var v = get3D();
			return
				"[\n" + v.map((b) ->
					"  [\n" + b.map((a) ->
						"    [" + a.join(", ") + "]"
						).join(",\n") + "\n  ]"
				).join(",\n") + "\n]"
			;
		case _:
			var v = get4D();
			return
				"[\n" + v.map((c) ->
					"  [\n" + c.map((b) ->
						"    [\n" + b.map((a) ->
							"      [" + a.join(", ") + "]"
						).join(",\n") + "\n    ]"
					).join(",\n") + "\n  ]"
				).join(",\n") + "\n]"
			;
		}
	}

	function printDiff():String {
		switch (rank) {
		case 0:
			var v = reshape0D(data.getDiff(actualSize));
			return "" + v;
		case 1:
			var v = reshape1D(data.getDiff(actualSize));
			return
				"[" + v.join(", ") + "]"
			;
		case 2:
			var v = reshape2D(data.getDiff(actualSize));
			return
				"[\n" + v.map((a) ->
					"  [" + a.join(", ") + "]"
				).join(",\n") + "\n]"
			;
		case 3:
			var v = reshape3D(data.getDiff(actualSize));
			return
				"[\n" + v.map((b) ->
					"  [\n" + b.map((a) ->
						"    [" + a.join(", ") + "]"
						).join(",\n") + "\n  ]"
				).join(",\n") + "\n]"
			;
		case _:
			var v = reshape4D(data.getDiff(actualSize));
			return
				"[\n" + v.map((c) ->
					"  [\n" + c.map((b) ->
						"    [\n" + b.map((a) ->
							"      [" + a.join(", ") + "]"
						).join(",\n") + "\n    ]"
					).join(",\n") + "\n  ]"
				).join(",\n") + "\n]"
			;
		}
	}

	@:allow(webdl.core)
	@:overload(function(rhs:Array<Int>):Void {}) // just works as like vectors
	function assignShape(rhs:Vector<Int>):Void {
		if (rank != rhs.length) throw "ranks mismatch";
		for (i in 0...rank) {
			if (shape[i] != -1 && shape[i] != rhs[i]) throw "dimension size mismatch";
			if (rhs[i] == -1) throw "no data assigned";
			this.actualShape[i] = rhs[i];
		}
		sizeCheck();
	}

	function sizeCheck():Void {
		// compute actual size
		actualSize = 1;
		for (s in actualShape) {
			actualSize *= s;
		}
		if (data == null || !data.isPreferableSize(actualSize)) {
			// expand or shrink if needed
			if (data != null) backend.disposeTensorData(data);
			data = backend.requestTensorData(actualSize);
		}
	}

	function flatten<T>(array:Array<Array<T>>):Array<T> {
		var flattened:Array<T> = [];
		for (a in array) {
			if (a.length != array[0].length) throw "inconsistent array size";
			for (b in a) {
				flattened.push(b);
			}
		}
		return flattened;
	}

	function reshape0D(value:Array<Float>):Float {
		if (rank != 0) throw "!?";
		if (actualSize != value.length) throw "!?";
		return value[0];
	}

	function reshape1D(value:Array<Float>):Array<Float> {
		if (rank != 1) throw "!?";
		if (actualSize != value.length) throw "!?";
		return value.copy();
	}

	function reshape2D(value:Array<Float>):Array<Array<Float>> {
		if (rank != 2) throw "!?";
		if (actualSize != value.length) throw "!?";
		var idx:Int = 0;
		return
			[for (i in 0...actualShape[0]) {
				[for (j in 0...actualShape[1]) {
					value[idx++];
				}];
			}]
		;
	}

	function reshape3D(value:Array<Float>):Array<Array<Array<Float>>> {
		if (rank != 3) throw "!?";
		if (actualSize != value.length) throw "!?";
		var idx:Int = 0;
		return
			[for (i in 0...actualShape[0]) {
				[for (j in 0...actualShape[1]) {
					[for (k in 0...actualShape[2]) {
						value[idx++];
					}];
				}];
			}]
		;
	}

	function reshape4D(value:Array<Float>):Array<Array<Array<Array<Float>>>> {
		if (rank != 4) throw "!?";
		if (actualSize != value.length) throw "!?";
		var idx:Int = 0;
		return
			[for (i in 0...actualShape[0]) {
				[for (j in 0...actualShape[1]) {
					[for (k in 0...actualShape[2]) {
						[for (l in 0...actualShape[3]) {
							value[idx++];
						}];
					}];
				}];
			}]
		;
	}

}
