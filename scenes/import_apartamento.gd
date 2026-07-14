@tool
extends EditorScenePostImport
## Pós-import do APARTAMENTO.blend: objetos pequenos (tecidos enrugados,
## decoração) ficam com GI dinâmica — o bake do LightmapGI os exclui do
## lightmap (onde viram manchas, por causa das micro-ilhas de UV2) e eles
## passam a ser iluminados pelas probes geradas no próprio bake.

## Maior dimensão (em metros, no espaço local) abaixo da qual o objeto
## usa probes em vez de lightmap.
const DIMENSAO_PROBE := 2.0


func _post_import(cena: Node) -> Object:
	_marcar(cena)
	return cena


func _marcar(no: Node) -> void:
	for filho in no.get_children():
		_marcar(filho)
	var mi := no as MeshInstance3D
	if mi and mi.mesh:
		var tamanho := mi.mesh.get_aabb().size * mi.transform.basis.get_scale()
		var maior := maxf(tamanho.x, maxf(tamanho.y, tamanho.z))
		if maior < DIMENSAO_PROBE:
			mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
