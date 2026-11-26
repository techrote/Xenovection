extends SceneTree
const Source = preload("res://core/source_model.gd")
func _initialize() -> void:
 var output := "user://source-f64.bin"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):
   output = arg.trim_prefix("--output=")
 var source := Source.new()
 var result: Dictionary = source.load_json("res://data/synthetic_foundry.json")
 if not result.ok:
  push_error(result.error)
  quit(1)
  return
 var dataset: Dictionary = source.get_dataset()
 var bytes := PackedByteArray()
 bytes.resize((48 + dataset.edges.size()) * 8)
 for i in range(48):
  bytes.encode_double(i * 8, float(dataset.nodes[i].value))
 for i in range(dataset.edges.size()):
  bytes.encode_double((48 + i) * 8, float(dataset.edges[i].weight))
 var file := FileAccess.open(output, FileAccess.WRITE)
 if file == null:
  quit(2)
  return
 file.store_buffer(bytes)
 file.close()
 print(JSON.stringify({"source_revision":dataset.manifest.revision,"binary64_values":48 + dataset.edges.size(),"file":output}))
 quit(0)
