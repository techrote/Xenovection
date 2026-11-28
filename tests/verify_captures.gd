extends SceneTree
## Conservative image-content audit for source and independently extracted runs.
## This detects missing/undecodable/uniform-dark images; visual review remains required.
const MAX_CAPTURES := 512
const MAX_SAMPLES := 131072
const BRIGHT_THRESHOLD := 0.06
var directory := ""
var output := ""
var failures: Array[String] = []
var captures: Array[Dictionary] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-directory="):
			directory = argument.trim_prefix("--capture-directory=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	_run.call_deferred()

func _run() -> void:
	var files: Array[String] = []
	if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
		failures.append("Capture directory is missing or inaccessible")
	else:
		_scan(directory,files,0)
	files.sort()
	if files.is_empty():
		failures.append("No PNG captures were found")
	if files.size() > MAX_CAPTURES:
		failures.append("Capture count exceeds the declared audit bound of %d" % MAX_CAPTURES)
	else:
		for path in files:
			captures.append(_inspect(path))
	var duplicate_pixels: Dictionary = {}
	for capture in captures:
		var digest: String = str(capture.get("pixel_sha256",""))
		if digest.is_empty():
			continue
		if not duplicate_pixels.has(digest):
			duplicate_pixels[digest] = []
		duplicate_pixels[digest].append(capture.file)
	var identical: Array = []
	for digest in duplicate_pixels:
		if duplicate_pixels[digest].size() > 1:
			identical.append({"pixel_sha256":digest,"files":duplicate_pixels[digest]})
	var receipt := {"schema":"xenovection.capture-audit.v1",
		"status":"PASS" if failures.is_empty() else "FAIL","captures_checked":captures.size(),
		"capture_directory":directory,"captures":captures,"failures":failures,
		"identical_pixel_groups":identical,"visual_review_required":true,
		"policy":{"minimum_bright_samples":51,"bright_channel_threshold":BRIGHT_THRESHOLD,
			"minimum_rgb_range":1.0/255.0,"maximum_samples_per_image":MAX_SAMPLES,
			"note":"Conservative corruption/black-frame gate. UI pixels can satisfy coverage; central-scene statistics and independent visual inspection remain necessary. No aesthetic acceptance is implied."}}
	if output.is_empty():
		failures.append("Output receipt path is required")
		receipt.status = "FAIL"
	else:
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file == null:
			failures.append("Cannot write image-audit receipt: "+output)
			receipt.status = "FAIL"
		else:
			file.store_string(JSON.stringify(receipt,"\t"))
			file.close()
	print("XENOVECTION_CAPTURE_AUDIT ",JSON.stringify({"status":receipt.status,"captures_checked":captures.size(),"failures":failures,"receipt":output,"visual_review_required":true}))
	quit(0 if failures.is_empty() else 1)

func _scan(path: String, files: Array[String], depth: int) -> void:
	if depth > 8:
		failures.append("Capture directory nesting exceeds audit bound")
		return
	for name in DirAccess.get_files_at(path):
		if name.get_extension().to_lower() == "png":
			files.append(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_scan(path.path_join(name),files,depth+1)

func _inspect(path: String) -> Dictionary:
	var relative := path.trim_prefix(directory).trim_prefix("/").trim_prefix("\\")
	var result := {"file":relative,"sha256":FileAccess.get_sha256(path),"status":"FAIL"}
	var image := Image.new()
	var error := image.load(path)
	if error != OK or image.is_empty():
		failures.append("PNG failed actual image decoding: "+relative)
		result.decode_error = error
		return result
	var width := image.get_width()
	var height := image.get_height()
	result.dimensions = [width,height]
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(image.get_data())
	result.pixel_sha256 = hasher.finish().hex_encode()
	if width < 32 or height < 32:
		failures.append("Capture has implausibly small dimensions: "+relative)
		return result
	var stride := maxi(4,ceili(sqrt(float(width)*float(height)/MAX_SAMPLES)))
	var count := 0
	var bright := 0
	var luma_lit := 0
	var central_count := 0
	var central_bright := 0
	var rgb_sum := Vector3.ZERO
	var rgb_min := Vector3.ONE
	var rgb_max := Vector3.ZERO
	var luma_min := 1.0
	var luma_max := 0.0
	var luma_sum := 0.0
	var luma_squared_sum := 0.0
	var central := Rect2(Vector2(width*0.20,height*0.20),Vector2(width*0.55,height*0.50))
	for y in range(0,height,stride):
		for x in range(0,width,stride):
			var colour := image.get_pixel(x,y)
			var rgb := Vector3(colour.r,colour.g,colour.b)*colour.a
			var luma := rgb.dot(Vector3(0.2126,0.7152,0.0722))
			var is_bright := maxf(rgb.x,maxf(rgb.y,rgb.z)) > BRIGHT_THRESHOLD
			rgb_sum += rgb
			rgb_min = Vector3(minf(rgb_min.x,rgb.x),minf(rgb_min.y,rgb.y),minf(rgb_min.z,rgb.z))
			rgb_max = Vector3(maxf(rgb_max.x,rgb.x),maxf(rgb_max.y,rgb.y),maxf(rgb_max.z,rgb.z))
			luma_min = minf(luma_min,luma)
			luma_max = maxf(luma_max,luma)
			luma_sum += luma
			luma_squared_sum += luma*luma
			count += 1
			bright += int(is_bright)
			luma_lit += int(luma > BRIGHT_THRESHOLD)
			if central.has_point(Vector2(x,y)):
				central_count += 1
				central_bright += int(is_bright)
	var rgb_mean := rgb_sum/maxi(1,count)
	var luma_mean := luma_sum/maxi(1,count)
	var rgb_range := rgb_max-rgb_min
	var variation := maxf(rgb_range.x,maxf(rgb_range.y,rgb_range.z))
	result.merge({"samples":count,"stride":stride,"bright_samples":bright,
		"lit_fraction":float(bright)/maxi(1,count),"luminance_lit_fraction":float(luma_lit)/maxi(1,count),
		"rgb_mean":[rgb_mean.x,rgb_mean.y,rgb_mean.z],"rgb_min":[rgb_min.x,rgb_min.y,rgb_min.z],
		"rgb_max":[rgb_max.x,rgb_max.y,rgb_max.z],"maximum_channel_range":variation,
		"luminance_mean":luma_mean,"luminance_min":luma_min,"luminance_max":luma_max,
		"luminance_stddev":sqrt(maxf(0.0,luma_squared_sum/maxi(1,count)-luma_mean*luma_mean)),
		"central_scene_samples":central_count,"central_scene_lit_fraction":float(central_bright)/maxi(1,central_count)})
	if bright <= 50 or variation < 1.0/255.0:
		failures.append("Capture is black, empty or effectively uniform: "+relative)
	else:
		result.status = "PASS"
	return result
