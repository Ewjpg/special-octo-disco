--!strict
-- Rebuilds the Blender stadium in Studio from tools/stadium/export_studio.py output.
-- Run through the Studio MCP's execute_luau in EDIT mode while serve.py is running.
--
-- Meshes and textures are created with AssetService (EditableMesh / EditableImage), so this needs
-- no upload, but the result is SESSION-LOCAL: it disappears when Studio closes and it does not
-- survive saving. For a permanent stadium import build/stadium/Stadium.glb with File > Import 3D.

local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")

local BASE = "http://127.0.0.1:48901/"
local MODEL_NAME = "StadiumMesh"

local function fetch(name: string): buffer
	return buffer.fromstring(HttpService:GetAsync(BASE .. name))
end

local function u32(b: buffer, o: number): number
	return buffer.readu32(b, o)
end

local function buildMesh(name: string): (MeshPart, number)
	local b = fetch(name .. ".mesh.bin")
	assert(buffer.readstring(b, 0, 4) == "RMSH", "bad mesh blob " .. name)
	local nv, nuv, nt = u32(b, 8), u32(b, 12), u32(b, 16)
	local pOff = 20
	local uOff = pOff + nv * 12
	local tOff = uOff + nuv * 8
	local qOff = tOff + nt * 12

	local em = AssetService:CreateEditableMesh()
	local vid, uid = table.create(nv), table.create(nuv)
	for i = 0, nv - 1 do
		local o = pOff + i * 12
		vid[i + 1] = em:AddVertex(Vector3.new(buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)))
	end
	for i = 0, nuv - 1 do
		local o = uOff + i * 8
		uid[i + 1] = em:AddUV(Vector2.new(buffer.readf32(b, o), buffer.readf32(b, o + 4)))
	end
	for i = 0, nt - 1 do
		local o, q = tOff + i * 12, qOff + i * 12
		local f = em:AddTriangle(vid[u32(b, o) + 1], vid[u32(b, o + 4) + 1], vid[u32(b, o + 8) + 1])
		em:SetFaceUVs(f, { uid[u32(b, q) + 1], uid[u32(b, q + 4) + 1], uid[u32(b, q + 8) + 1] })
	end
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	return part, nt
end

local images: { [string]: Content } = {}
local function texture(name: string): Content
	local cached = images[name]
	if cached then
		return cached
	end
	local raw = fetch(name .. ".tex.bin")
	assert(buffer.readstring(raw, 0, 4) == "RTEX", "bad texture blob " .. name)
	local n = u32(raw, 4)
	local px = buffer.create(n * n * 4)
	buffer.copy(px, 0, raw, 8, n * n * 4)
	local ei = AssetService:CreateEditableImage({ Size = Vector2.new(n, n) })
	ei:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), px)
	local content = Content.fromObject(ei)
	images[name] = content
	return content
end

local PROPS = {
	color = "ColorMapContent",
	normal = "NormalMapContent",
	roughness = "RoughnessMapContent",
	metalness = "MetalnessMapContent",
}

local manifest = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "manifest.json"))

local old = workspace:FindFirstChild(MODEL_NAME)
if old then
	old:Destroy()
end
local model = Instance.new("Model")
model.Name = MODEL_NAME

local totalTris, count = 0, 0
for _, chunk in ipairs(manifest.chunks) do
	local part, tris = buildMesh(chunk.name)
	part.Name = chunk.name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = chunk.material ~= "led"
	part.CFrame = CFrame.new(chunk.center[1], chunk.center[2], chunk.center[3])
	local mat = manifest.materials[chunk.material]
	if mat.neon then
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(mat.neon[1], mat.neon[2], mat.neon[3])
	else
		local sa = Instance.new("SurfaceAppearance")
		for _, map in ipairs(mat.maps) do
			(sa :: any)[PROPS[map]] = texture(chunk.material .. "_" .. map)
		end
		sa.Parent = part
	end
	part.Parent = model
	totalTris += tris
	count += 1
	task.wait() -- keep Studio responsive between chunks
end
model.Parent = workspace
return string.format("%d chunks, %d triangles", count, totalTris)
