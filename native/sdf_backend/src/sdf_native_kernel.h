#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class SdfNativeKernel final : public RefCounted {
	GDCLASS(SdfNativeKernel, RefCounted)

public:
	Dictionary build_chunk_snapshot(const Dictionary &snapshot);
	Dictionary capture_cached_chunk(
			const Vector3i &chunk_coordinate,
			int cells,
			int source_signature,
			const Dictionary &reuse_snapshot);
	Dictionary capture_cached_fragment_tile(
			const Vector3i &tile_origin,
			int cells,
			const Vector3i &component_minimum,
			const Vector3i &component_size,
			const PackedByteArray &membership,
			const Dictionary &reuse_snapshot);
	Dictionary map_structural_components(
			const PackedFloat32Array &sample_distances,
			const Vector3i &cell_size,
			const PackedByteArray &boundary_anchors);
	Dictionary map_cached_structural_components(
			const Vector3i &cell_minimum,
			const Vector3i &cell_size,
			const PackedByteArray &boundary_anchors);
	Dictionary map_load_bearing_components(
			const PackedFloat32Array &sample_distances,
			const Vector3i &cell_size,
			const PackedByteArray &boundary_anchors,
			double minimum_support_ratio);
	Dictionary map_cached_load_bearing_components(
			const Vector3i &cell_minimum,
			const Vector3i &cell_size,
			const PackedByteArray &boundary_anchors,
			double minimum_support_ratio);
	bool synchronize_dense_field(
			const Array &brick_states,
			const Vector3 &half_extents,
			double voxel_size,
			const Vector3i &total_cells,
			int brick_cells,
			double narrow_band);
	bool update_cached_brick(const Dictionary &brick_state);
	Dictionary erase_cached_cells(const Array &cells, const Array &brick_states);
	bool begin_brush_union(const Dictionary &request);
	Dictionary apply_brush_union_to_brick(const Dictionary &brick_state);
	Dictionary scratch_state() const;
	String backend_version() const;

protected:
	static void _bind_methods();

private:
	struct BrushOperation {
		uint8_t kind = 0;
		Vector3 start;
		Vector3 end;
		double first_radius = 0.0;
		double second_radius = 0.0;
		Vector3 bounds_minimum;
		Vector3 bounds_maximum;
	};

	struct SampleMutation {
		int32_t index = 0;
		int16_t raw_distance = 0;
	};

	struct StructuralBond {
		int32_t first = -1;
		int32_t second = -1;
		int32_t faces = 0;
	};

	std::vector<int32_t> cell_indices_;
	std::vector<int32_t> remap_;
	std::vector<Vector3> vertices_;
	std::vector<Vector3> normals_;
	std::vector<uint8_t> shell_masks_;
	std::vector<int32_t> indices_;
	std::vector<BrushOperation> operations_;
	std::vector<SampleMutation> mutations_;
	std::vector<uint8_t> structural_solid_;
	std::vector<uint8_t> structural_core_;
	std::vector<uint8_t> structural_direct_supported_;
	std::vector<uint8_t> structural_supported_;
	std::vector<int32_t> structural_labels_;
	std::vector<int32_t> structural_queue_;
	std::vector<int32_t> structural_cell_counts_;
	std::vector<int32_t> structural_required_faces_;
	std::vector<int32_t> structural_support_budget_;
	std::vector<Vector3i> structural_minimums_;
	std::vector<Vector3i> structural_maximums_;
	std::vector<StructuralBond> structural_bonds_;
	std::vector<uint64_t> structural_bond_keys_;
	std::vector<int32_t> structural_bond_indices_;
	std::vector<float> structural_samples_;
	std::vector<float> dense_distances_;
	std::vector<uint32_t> erase_sample_stamps_;
	std::vector<std::vector<int32_t>> erase_brick_sample_indices_;
	std::vector<int32_t> erase_touched_bricks_;
	uint32_t erase_sample_stamp_ = 0;

	Vector3 mutation_half_extents_;
	Vector3 mutation_combined_minimum_;
	Vector3 mutation_combined_maximum_;
	Vector3i noise_origin_;
	Vector3i noise_size_;
	PackedFloat32Array noise_values_;
	double mutation_voxel_size_ = 0.0;
	double mutation_narrow_band_ = 0.0;
	double mutation_maximum_radius_ = 0.0;
	double mutation_spatial_warp_ = 0.0;
	double noise_frequency_ = 1.0;
	int mutation_brick_cells_ = 0;
	bool mutation_ready_ = false;
	Vector3 dense_half_extents_;
	Vector3i dense_cell_size_;
	double dense_voxel_size_ = 0.0;
	double dense_narrow_band_ = 0.0;
	int dense_brick_cells_ = 0;
	bool dense_ready_ = false;

	int sample_index(int x, int y, int z, int size) const;
	float sample(const float *distances, int x, int y, int z, int size) const;
	Vector3 gradient(const float *distances, int x, int y, int z, int size) const;
	int extended_index(int x, int y, int z, int size) const;
	float triangle_alignment(int32_t a, int32_t b, int32_t c) const;
	float triangle_quality(int32_t a, int32_t b, int32_t c) const;
	void append_triangle(int32_t a, int32_t b, int32_t c);
	void append_owned_edge_quad(
			const float *distances,
			int sample_grid_size,
			int extended_size,
			int local_x,
			int local_y,
			int local_z,
			int axis);
	void compact_geometry();
	Dictionary map_structural_components_data(
			const float *sample_distances,
			const Vector3i &cell_size,
			const PackedByteArray &boundary_anchors,
			double minimum_support_ratio);
	int dense_sample_index(int x, int y, int z) const;
	void update_dense_brick(
			const Vector3i &coordinate,
			bool uniform,
			int16_t uniform_raw,
			const PackedByteArray &distance_bytes);
	double box_distance(const Vector3 &point) const;
	double brush_distance(const BrushOperation &operation, const Vector3 &point) const;
	double sample_cached_noise(const Vector3 &point) const;
	int16_t quantize_distance(double value) const;
	double dequantize_distance(int16_t value) const;
	static int16_t read_raw(const uint8_t *bytes, int index);
	static void write_raw(uint8_t *bytes, int index, int16_t value);
};

} // namespace godot
