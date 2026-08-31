#include "sdf_native_kernel.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace godot {
namespace {

constexpr int kSampleHalo = 2;
constexpr float kMinimumEdgeDenominator = 0.0000001F;
constexpr float kMinimumVectorLengthSquared = 0.000001F;
constexpr float kMinimumContourTriangleQuality = 0.0F;
constexpr float kTriangulationQualityTieEpsilon = 0.0001F;
constexpr float kBoxShellIntersectionToleranceVoxels = 0.02F;

constexpr std::array<Vector3i, 8> kCornerOffsets = {
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)};
constexpr std::array<std::array<int, 2>, 12> kEdgeCorners = {{{0, 1}, {2, 3}, {4, 5}, {6, 7},
		{0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}}};
constexpr std::array<std::array<int, 4>, 6> kFaceCorners = {{{0, 1, 3, 2}, {4, 5, 7, 6},
		{0, 1, 5, 4}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 3, 7, 5}}};
constexpr std::array<std::array<int, 4>, 6> kFaceEdges = {{{0, 5, 1, 4}, {2, 7, 3, 6},
		{0, 9, 2, 8}, {1, 11, 3, 10}, {4, 10, 6, 8}, {5, 11, 7, 9}}};
constexpr std::array<std::array<Vector3i, 4>, 3> kAdjacentCells = {{
		{Vector3i(0, -1, -1), Vector3i(0, 0, -1), Vector3i(0, 0, 0), Vector3i(0, -1, 0)},
		{Vector3i(-1, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 0, -1)},
		{Vector3i(-1, -1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 0), Vector3i(-1, 0, 0)}}};
constexpr std::array<Vector3i, 3> kAxisDirections = {
		Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)};
constexpr std::array<std::array<int, 4>, 3> kAdjacentEdgeSlots = {{{3, 2, 0, 1},
		{7, 5, 4, 6}, {11, 10, 8, 9}}};
constexpr int kCellEdgeSlotCount = 12;
constexpr std::array<Vector3i, 6> kFaceNeighborOffsets = {
		Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0),
		Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)};
// Boundary packets use min-X,min-Y,min-Z,max-X,max-Y,max-Z; face-neighbor traversal uses
// -X,+X,-Y,+Y,-Z,+Z. Never index one ordering directly with the other.
constexpr std::array<std::size_t, 6> kFaceNeighborAnchorIndices = {0, 3, 1, 4, 2, 5};

int characteristic_cross_section_cells(int cell_count) {
	// Exact integer ceil(cell_count^(2/3)); this is authoritative, so avoid libm drift between
	// compilers/platforms and between the native and GDScript implementations.
	const int64_t target = static_cast<int64_t>(cell_count) * cell_count;
	int low = 0;
	int high = std::max(cell_count, 1);
	while (low < high) {
		const int middle = low + (high - low) / 2;
		const int64_t cube = static_cast<int64_t>(middle) * middle * middle;
		if (cube >= target) {
			high = middle;
		} else {
			low = middle + 1;
		}
	}
	return low;
}

Vector3 to_vector3(const Vector3i &value) {
	return Vector3(static_cast<real_t>(value.x), static_cast<real_t>(value.y), static_cast<real_t>(value.z));
}

uint8_t box_shell_mask(const Vector3 &point, const Vector3 &half_extents, real_t tolerance) {
	if (half_extents.length_squared() <= static_cast<real_t>(0.0)) {
		return 0U;
	}
	uint8_t mask = 0U;
	mask |= std::abs(point.x + half_extents.x) <= tolerance ? 1U << 0U : 0U;
	mask |= std::abs(point.x - half_extents.x) <= tolerance ? 1U << 1U : 0U;
	mask |= std::abs(point.y + half_extents.y) <= tolerance ? 1U << 2U : 0U;
	mask |= std::abs(point.y - half_extents.y) <= tolerance ? 1U << 3U : 0U;
	mask |= std::abs(point.z + half_extents.z) <= tolerance ? 1U << 4U : 0U;
	mask |= std::abs(point.z - half_extents.z) <= tolerance ? 1U << 5U : 0U;
	return mask;
}

Vector3 snap_to_box_shell(Vector3 vertex, const Vector3 &half_extents, uint8_t mask) {
	if ((mask & (1U << 0U)) != 0U) {
		vertex.x = -half_extents.x;
	} else if ((mask & (1U << 1U)) != 0U) {
		vertex.x = half_extents.x;
	}
	if ((mask & (1U << 2U)) != 0U) {
		vertex.y = -half_extents.y;
	} else if ((mask & (1U << 3U)) != 0U) {
		vertex.y = half_extents.y;
	}
	if ((mask & (1U << 4U)) != 0U) {
		vertex.z = -half_extents.z;
	} else if ((mask & (1U << 5U)) != 0U) {
		vertex.z = half_extents.z;
	}
	return vertex;
}

Dictionary empty_result(const Vector3i &coordinate) {
	Dictionary result;
	result[StringName("chunk_coordinate")] = coordinate;
	result[StringName("vertices")] = PackedVector3Array();
	result[StringName("normals")] = PackedVector3Array();
	result[StringName("shell_masks")] = PackedByteArray();
	result[StringName("indices")] = PackedInt32Array();
	result[StringName("triangle_count")] = 0;
	result[StringName("empty")] = true;
	result[StringName("native_backend")] = true;
	return result;
}

} // namespace

void SdfNativeKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_chunk_snapshot", "snapshot"), &SdfNativeKernel::build_chunk_snapshot);
	ClassDB::bind_method(
			D_METHOD(
					"capture_cached_chunk",
					"chunk_coordinate",
					"cells",
					"source_signature",
					"reuse_snapshot"),
			&SdfNativeKernel::capture_cached_chunk);
	ClassDB::bind_method(
			D_METHOD(
					"capture_cached_fragment_tile",
					"tile_origin",
					"cells",
					"component_minimum",
					"component_size",
					"membership",
					"reuse_snapshot"),
			&SdfNativeKernel::capture_cached_fragment_tile);
	ClassDB::bind_method(
			D_METHOD(
					"map_structural_components",
					"sample_distances",
					"cell_size",
					"boundary_anchors"),
			&SdfNativeKernel::map_structural_components);
	ClassDB::bind_method(
			D_METHOD(
					"map_cached_structural_components",
					"cell_minimum",
					"cell_size",
					"boundary_anchors"),
			&SdfNativeKernel::map_cached_structural_components);
	ClassDB::bind_method(
			D_METHOD(
					"map_load_bearing_components",
					"sample_distances",
					"cell_size",
					"boundary_anchors",
					"minimum_support_ratio"),
			&SdfNativeKernel::map_load_bearing_components);
	ClassDB::bind_method(
			D_METHOD(
					"map_cached_load_bearing_components",
					"cell_minimum",
					"cell_size",
					"boundary_anchors",
					"minimum_support_ratio"),
			&SdfNativeKernel::map_cached_load_bearing_components);
	ClassDB::bind_method(
			D_METHOD(
					"synchronize_dense_field",
					"brick_states",
					"half_extents",
					"voxel_size",
					"total_cells",
					"brick_cells",
					"narrow_band"),
			&SdfNativeKernel::synchronize_dense_field);
	ClassDB::bind_method(
			D_METHOD("update_cached_brick", "brick_state"),
			&SdfNativeKernel::update_cached_brick);
	ClassDB::bind_method(
			D_METHOD("erase_cached_cells", "cells", "brick_states"),
			&SdfNativeKernel::erase_cached_cells);
	ClassDB::bind_method(D_METHOD("begin_brush_union", "request"), &SdfNativeKernel::begin_brush_union);
	ClassDB::bind_method(
			D_METHOD("apply_brush_union_to_brick", "brick_state"),
			&SdfNativeKernel::apply_brush_union_to_brick);
	ClassDB::bind_method(D_METHOD("scratch_state"), &SdfNativeKernel::scratch_state);
	ClassDB::bind_method(D_METHOD("backend_version"), &SdfNativeKernel::backend_version);
}

String SdfNativeKernel::backend_version() const {
	return "scavange-sdf-native/8";
}

Dictionary SdfNativeKernel::scratch_state() const {
	Dictionary state;
	state[StringName("cell_index_capacity")] = static_cast<int64_t>(cell_indices_.capacity());
	state[StringName("remap_capacity")] = static_cast<int64_t>(remap_.capacity());
	state[StringName("vertex_capacity")] = static_cast<int64_t>(vertices_.capacity());
	state[StringName("normal_capacity")] = static_cast<int64_t>(normals_.capacity());
	state[StringName("shell_mask_capacity")] = static_cast<int64_t>(shell_masks_.capacity());
	state[StringName("index_capacity")] = static_cast<int64_t>(indices_.capacity());
	state[StringName("operation_capacity")] = static_cast<int64_t>(operations_.capacity());
	state[StringName("mutation_capacity")] = static_cast<int64_t>(mutations_.capacity());
	state[StringName("structural_solid_capacity")] = static_cast<int64_t>(structural_solid_.capacity());
	state[StringName("structural_core_capacity")] = static_cast<int64_t>(structural_core_.capacity());
	state[StringName("structural_label_capacity")] = static_cast<int64_t>(structural_labels_.capacity());
	state[StringName("structural_queue_capacity")] = static_cast<int64_t>(structural_queue_.capacity());
	state[StringName("structural_bond_capacity")] = static_cast<int64_t>(structural_bonds_.capacity());
	state[StringName("structural_bond_hash_capacity")] = static_cast<int64_t>(structural_bond_keys_.capacity());
	state[StringName("structural_sample_capacity")] = static_cast<int64_t>(structural_samples_.capacity());
	state[StringName("dense_sample_capacity")] = static_cast<int64_t>(dense_distances_.capacity());
	state[StringName("erase_stamp_capacity")] = static_cast<int64_t>(erase_sample_stamps_.capacity());
	return state;
}

Dictionary SdfNativeKernel::map_structural_components(
		const PackedFloat32Array &sample_distances,
		const Vector3i &cell_size,
		const PackedByteArray &boundary_anchors) {
	Dictionary result;
	result[StringName("valid")] = false;
	if (cell_size.x <= 0 || cell_size.y <= 0 || cell_size.z <= 0 || boundary_anchors.size() < 6) {
		return result;
	}
	const Vector3i sample_size = cell_size + Vector3i(1, 1, 1);
	const int64_t cell_count_64 = static_cast<int64_t>(cell_size.x) * cell_size.y * cell_size.z;
	const int64_t sample_count_64 = static_cast<int64_t>(sample_size.x) * sample_size.y * sample_size.z;
	if (cell_count_64 <= 0 || cell_count_64 > 262144 || sample_distances.size() != sample_count_64) {
		return result;
	}
	return map_structural_components_data(sample_distances.ptr(), cell_size, boundary_anchors, -1.0);
}

Dictionary SdfNativeKernel::map_cached_structural_components(
		const Vector3i &cell_minimum,
		const Vector3i &cell_size,
		const PackedByteArray &boundary_anchors) {
	Dictionary result;
	result[StringName("valid")] = false;
	if (!dense_ready_ || cell_minimum.x < 0 || cell_minimum.y < 0 || cell_minimum.z < 0
			|| cell_size.x <= 0 || cell_size.y <= 0 || cell_size.z <= 0
			|| cell_minimum.x + cell_size.x > dense_cell_size_.x
			|| cell_minimum.y + cell_size.y > dense_cell_size_.y
			|| cell_minimum.z + cell_size.z > dense_cell_size_.z
			|| boundary_anchors.size() < 6) {
		return result;
	}
	const Vector3i sample_size = cell_size + Vector3i(1, 1, 1);
	const int64_t sample_count = static_cast<int64_t>(sample_size.x) * sample_size.y * sample_size.z;
	const int64_t cell_count = static_cast<int64_t>(cell_size.x) * cell_size.y * cell_size.z;
	if (cell_count <= 0 || cell_count > 262144 || sample_count <= 0) {
		return result;
	}
	structural_samples_.resize(static_cast<std::size_t>(sample_count));
	std::size_t write_index = 0;
	for (int z = 0; z <= cell_size.z; ++z) {
		for (int y = 0; y <= cell_size.y; ++y) {
			const int source = dense_sample_index(
					cell_minimum.x,
					cell_minimum.y + y,
					cell_minimum.z + z);
			const float *row = dense_distances_.data() + source;
			std::copy(row, row + sample_size.x, structural_samples_.begin() + write_index);
			write_index += static_cast<std::size_t>(sample_size.x);
		}
	}
	return map_structural_components_data(structural_samples_.data(), cell_size, boundary_anchors, -1.0);
}

Dictionary SdfNativeKernel::map_load_bearing_components(
		const PackedFloat32Array &sample_distances,
		const Vector3i &cell_size,
		const PackedByteArray &boundary_anchors,
		double minimum_support_ratio) {
	Dictionary result;
	result[StringName("valid")] = false;
	if (cell_size.x <= 0 || cell_size.y <= 0 || cell_size.z <= 0 || boundary_anchors.size() < 6) {
		return result;
	}
	const Vector3i sample_size = cell_size + Vector3i(1, 1, 1);
	const int64_t cell_count = static_cast<int64_t>(cell_size.x) * cell_size.y * cell_size.z;
	const int64_t sample_count = static_cast<int64_t>(sample_size.x) * sample_size.y * sample_size.z;
	if (cell_count <= 0 || cell_count > 262144 || sample_distances.size() != sample_count) {
		return result;
	}
	return map_structural_components_data(
			sample_distances.ptr(),
			cell_size,
			boundary_anchors,
			std::clamp(minimum_support_ratio, 0.001, 1.0));
}

Dictionary SdfNativeKernel::map_cached_load_bearing_components(
		const Vector3i &cell_minimum,
		const Vector3i &cell_size,
		const PackedByteArray &boundary_anchors,
		double minimum_support_ratio) {
	Dictionary result;
	result[StringName("valid")] = false;
	if (!dense_ready_ || cell_minimum.x < 0 || cell_minimum.y < 0 || cell_minimum.z < 0
			|| cell_size.x <= 0 || cell_size.y <= 0 || cell_size.z <= 0
			|| cell_minimum.x + cell_size.x > dense_cell_size_.x
			|| cell_minimum.y + cell_size.y > dense_cell_size_.y
			|| cell_minimum.z + cell_size.z > dense_cell_size_.z
			|| boundary_anchors.size() < 6) {
		return result;
	}
	const Vector3i sample_size = cell_size + Vector3i(1, 1, 1);
	const int64_t sample_count = static_cast<int64_t>(sample_size.x) * sample_size.y * sample_size.z;
	const int64_t cell_count = static_cast<int64_t>(cell_size.x) * cell_size.y * cell_size.z;
	if (cell_count <= 0 || cell_count > 262144 || sample_count <= 0) {
		return result;
	}
	structural_samples_.resize(static_cast<std::size_t>(sample_count));
	std::size_t write_index = 0;
	for (int z = 0; z <= cell_size.z; ++z) {
		for (int y = 0; y <= cell_size.y; ++y) {
			const int source = dense_sample_index(
					cell_minimum.x,
					cell_minimum.y + y,
					cell_minimum.z + z);
			const float *row = dense_distances_.data() + source;
			std::copy(row, row + sample_size.x, structural_samples_.begin() + write_index);
			write_index += static_cast<std::size_t>(sample_size.x);
		}
	}
	return map_structural_components_data(
			structural_samples_.data(),
			cell_size,
			boundary_anchors,
			std::clamp(minimum_support_ratio, 0.001, 1.0));
}

Dictionary SdfNativeKernel::map_structural_components_data(
		const float *distances,
		const Vector3i &cell_size,
		const PackedByteArray &boundary_anchors,
		double minimum_support_ratio) {
	Dictionary result;
	result[StringName("valid")] = false;
	if (distances == nullptr || cell_size.x <= 0 || cell_size.y <= 0 || cell_size.z <= 0
			|| boundary_anchors.size() < 6) {
		return result;
	}
	const Vector3i sample_size = cell_size + Vector3i(1, 1, 1);
	const int64_t cell_count_64 = static_cast<int64_t>(cell_size.x) * cell_size.y * cell_size.z;
	if (cell_count_64 <= 0 || cell_count_64 > 262144) {
		return result;
	}
	const int cell_count = static_cast<int>(cell_count_64);
	structural_solid_.resize(cell_count);
	structural_labels_.resize(cell_count);
	structural_queue_.resize(cell_count);
	std::fill(structural_solid_.begin(), structural_solid_.end(), 0U);
	std::fill(structural_labels_.begin(), structural_labels_.end(), -1);

	const int sample_stride_y = sample_size.x;
	const int sample_stride_z = sample_size.x * sample_size.y;
	const int cell_stride_y = cell_size.x;
	const int cell_stride_z = cell_size.x * cell_size.y;
	for (int z = 0; z < cell_size.z; ++z) {
		for (int y = 0; y < cell_size.y; ++y) {
			int sample_index = y * sample_stride_y + z * sample_stride_z;
			int cell_index = y * cell_stride_y + z * cell_stride_z;
			for (int x = 0; x < cell_size.x; ++x, ++sample_index, ++cell_index) {
				const int next_y = sample_index + sample_stride_y;
				const int next_z = sample_index + sample_stride_z;
				// Structural occupancy must cover every cell that can contribute to the zero
				// contour. An average can be positive while one corner is negative, leaving a thin
				// rendered sheet absent from the connectivity graph after a large fracture.
				const float minimum = std::min({
						distances[sample_index],
						distances[sample_index + 1],
						distances[next_y],
						distances[next_y + 1],
						distances[next_z],
						distances[next_z + 1],
						distances[next_z + sample_stride_y],
						distances[next_z + sample_stride_y + 1]});
				structural_solid_[cell_index] = minimum < 0.0F ? 1U : 0U;
			}
		}
	}

	const uint8_t *anchors = boundary_anchors.ptr();
	int core_component_count = 0;
	if (minimum_support_ratio >= 0.0) {
		// Erode one face layer only for structural analysis. Narrow ligaments disappear from this
		// core, but the original occupied cells are assigned back below and remain in fragment meshes.
		structural_core_.resize(cell_count);
		std::fill(structural_core_.begin(), structural_core_.end(), 0U);
		for (int index = 0; index < cell_count; ++index) {
			if (structural_solid_[index] == 0U) {
				continue;
			}
			const int z = index / cell_stride_z;
			const int remainder = index - z * cell_stride_z;
			const int y = remainder / cell_size.x;
			const int x = remainder - y * cell_size.x;
			bool is_core = true;
			for (std::size_t offset_index = 0; offset_index < kFaceNeighborOffsets.size(); ++offset_index) {
				const Vector3i &offset = kFaceNeighborOffsets[offset_index];
				const int neighbor_x = x + offset.x;
				const int neighbor_y = y + offset.y;
				const int neighbor_z = z + offset.z;
				if (neighbor_x < 0 || neighbor_x >= cell_size.x
						|| neighbor_y < 0 || neighbor_y >= cell_size.y
						|| neighbor_z < 0 || neighbor_z >= cell_size.z) {
					if (anchors[kFaceNeighborAnchorIndices[offset_index]] == 0U) {
						is_core = false;
						break;
					}
					continue;
				}
				const int neighbor_index = neighbor_x
						+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
				if (structural_solid_[neighbor_index] == 0U) {
					is_core = false;
					break;
				}
			}
			structural_core_[index] = is_core ? 1U : 0U;
		}

		std::fill(structural_labels_.begin(), structural_labels_.end(), -1);
		for (int start = 0; start < cell_count; ++start) {
			if (structural_core_[start] == 0U || structural_labels_[start] >= 0) {
				continue;
			}
			int head = 0;
			int tail = 1;
			structural_queue_[0] = start;
			structural_labels_[start] = core_component_count;
			while (head < tail) {
				const int current_index = structural_queue_[head++];
				const int z = current_index / cell_stride_z;
				const int remainder = current_index - z * cell_stride_z;
				const int y = remainder / cell_size.x;
				const int x = remainder - y * cell_size.x;
				for (const Vector3i &offset : kFaceNeighborOffsets) {
					const int neighbor_x = x + offset.x;
					const int neighbor_y = y + offset.y;
					const int neighbor_z = z + offset.z;
					if (neighbor_x < 0 || neighbor_x >= cell_size.x
							|| neighbor_y < 0 || neighbor_y >= cell_size.y
							|| neighbor_z < 0 || neighbor_z >= cell_size.z) {
						continue;
					}
					const int neighbor_index = neighbor_x
							+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
					if (structural_core_[neighbor_index] == 0U
							|| structural_labels_[neighbor_index] >= 0) {
						continue;
					}
					structural_labels_[neighbor_index] = core_component_count;
					structural_queue_[tail++] = neighbor_index;
				}
			}
			++core_component_count;
		}

		if (core_component_count > 1) {
			// Stable multi-source flood assigns the original shell and ligament to the nearest core.
			int head = 0;
			int tail = 0;
			for (int index = 0; index < cell_count; ++index) {
				if (structural_core_[index] != 0U) {
					structural_queue_[tail++] = index;
				}
			}
			while (head < tail) {
				const int current_index = structural_queue_[head++];
				const int z = current_index / cell_stride_z;
				const int remainder = current_index - z * cell_stride_z;
				const int y = remainder / cell_size.x;
				const int x = remainder - y * cell_size.x;
				for (const Vector3i &offset : kFaceNeighborOffsets) {
					const int neighbor_x = x + offset.x;
					const int neighbor_y = y + offset.y;
					const int neighbor_z = z + offset.z;
					if (neighbor_x < 0 || neighbor_x >= cell_size.x
							|| neighbor_y < 0 || neighbor_y >= cell_size.y
							|| neighbor_z < 0 || neighbor_z >= cell_size.z) {
						continue;
					}
					const int neighbor_index = neighbor_x
							+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
					if (structural_solid_[neighbor_index] == 0U
							|| structural_labels_[neighbor_index] >= 0) {
						continue;
					}
					structural_labels_[neighbor_index] = structural_labels_[current_index];
					structural_queue_[tail++] = neighbor_index;
				}
			}

			int region_count = core_component_count;
			for (int start = 0; start < cell_count; ++start) {
				if (structural_solid_[start] == 0U || structural_labels_[start] >= 0) {
					continue;
				}
				head = 0;
				tail = 1;
				structural_queue_[0] = start;
				structural_labels_[start] = region_count;
				while (head < tail) {
					const int current_index = structural_queue_[head++];
					const int z = current_index / cell_stride_z;
					const int remainder = current_index - z * cell_stride_z;
					const int y = remainder / cell_size.x;
					const int x = remainder - y * cell_size.x;
					for (const Vector3i &offset : kFaceNeighborOffsets) {
						const int neighbor_x = x + offset.x;
						const int neighbor_y = y + offset.y;
						const int neighbor_z = z + offset.z;
						if (neighbor_x < 0 || neighbor_x >= cell_size.x
								|| neighbor_y < 0 || neighbor_y >= cell_size.y
								|| neighbor_z < 0 || neighbor_z >= cell_size.z) {
							continue;
						}
						const int neighbor_index = neighbor_x
								+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
						if (structural_solid_[neighbor_index] == 0U
								|| structural_labels_[neighbor_index] >= 0) {
							continue;
						}
						structural_labels_[neighbor_index] = region_count;
						structural_queue_[tail++] = neighbor_index;
					}
				}
				++region_count;
			}

			structural_cell_counts_.resize(region_count);
			structural_required_faces_.resize(region_count);
			structural_support_budget_.resize(region_count);
			structural_direct_supported_.resize(region_count);
			structural_supported_.resize(region_count);
			structural_minimums_.resize(region_count);
			structural_maximums_.resize(region_count);
			std::fill(structural_cell_counts_.begin(), structural_cell_counts_.end(), 0);
			std::fill(structural_required_faces_.begin(), structural_required_faces_.end(), 0);
			std::fill(structural_support_budget_.begin(), structural_support_budget_.end(), 0);
			std::fill(structural_direct_supported_.begin(), structural_direct_supported_.end(), 0U);
			std::fill(structural_supported_.begin(), structural_supported_.end(), 0U);
			std::fill(
					structural_minimums_.begin(),
					structural_minimums_.end(),
					cell_size - Vector3i(1, 1, 1));
			std::fill(structural_maximums_.begin(), structural_maximums_.end(), Vector3i());
			structural_bonds_.clear();
			std::size_t bond_hash_size = 8;
			const std::size_t desired_bond_hash_size = std::max(
					static_cast<std::size_t>(8),
					static_cast<std::size_t>(region_count) * 8U);
			while (bond_hash_size < desired_bond_hash_size) {
				bond_hash_size <<= 1U;
			}
			structural_bond_keys_.resize(bond_hash_size);
			structural_bond_indices_.resize(bond_hash_size);
			std::fill(structural_bond_keys_.begin(), structural_bond_keys_.end(), UINT64_MAX);
			std::fill(structural_bond_indices_.begin(), structural_bond_indices_.end(), -1);

			for (int index = 0; index < cell_count; ++index) {
				const int label = structural_labels_[index];
				if (label < 0) {
					continue;
				}
				const int z = index / cell_stride_z;
				const int remainder = index - z * cell_stride_z;
				const int y = remainder / cell_size.x;
				const int x = remainder - y * cell_size.x;
				++structural_cell_counts_[label];
				Vector3i &minimum = structural_minimums_[label];
				Vector3i &maximum = structural_maximums_[label];
				minimum.x = std::min(minimum.x, x);
				minimum.y = std::min(minimum.y, y);
				minimum.z = std::min(minimum.z, z);
				maximum.x = std::max(maximum.x, x);
				maximum.y = std::max(maximum.y, y);
				maximum.z = std::max(maximum.z, z);
				if ((x == 0 && anchors[0] != 0U)
						|| (y == 0 && anchors[1] != 0U)
						|| (z == 0 && anchors[2] != 0U)
						|| (x == cell_size.x - 1 && anchors[3] != 0U)
						|| (y == cell_size.y - 1 && anchors[4] != 0U)
						|| (z == cell_size.z - 1 && anchors[5] != 0U)) {
					structural_direct_supported_[label] = 1U;
				}
				for (const Vector3i &offset : kAxisDirections) {
					const int neighbor_x = x + offset.x;
					const int neighbor_y = y + offset.y;
					const int neighbor_z = z + offset.z;
					if (neighbor_x >= cell_size.x || neighbor_y >= cell_size.y || neighbor_z >= cell_size.z) {
						continue;
					}
					const int neighbor_index = neighbor_x
							+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
					const int neighbor_label = structural_labels_[neighbor_index];
					if (neighbor_label < 0 || neighbor_label == label) {
						continue;
					}
					const uint32_t first = static_cast<uint32_t>(std::min(label, neighbor_label));
					const uint32_t second = static_cast<uint32_t>(std::max(label, neighbor_label));
					const uint64_t key = (static_cast<uint64_t>(first) << 32U) | second;
					const std::size_t mask = structural_bond_keys_.size() - 1U;
					std::size_t slot = static_cast<std::size_t>(
							key * UINT64_C(11400714819323198485)) & mask;
					std::size_t probes = 0;
					while (structural_bond_keys_[slot] != UINT64_MAX
							&& structural_bond_keys_[slot] != key
							&& probes < structural_bond_keys_.size()) {
						slot = (slot + 1U) & mask;
						++probes;
					}
					if (probes >= structural_bond_keys_.size()) {
						auto found = std::find_if(
								structural_bonds_.begin(),
								structural_bonds_.end(),
								[first, second](const StructuralBond &bond) {
									return bond.first == static_cast<int32_t>(first)
											&& bond.second == static_cast<int32_t>(second);
								});
						if (found == structural_bonds_.end()) {
							structural_bonds_.push_back(
									{static_cast<int32_t>(first), static_cast<int32_t>(second), 1});
						} else {
							++found->faces;
						}
					} else if (structural_bond_keys_[slot] == UINT64_MAX) {
						const int32_t bond_index = static_cast<int32_t>(structural_bonds_.size());
						structural_bond_keys_[slot] = key;
						structural_bond_indices_[slot] = bond_index;
						structural_bonds_.push_back(
								{static_cast<int32_t>(first), static_cast<int32_t>(second), 1});
					} else {
						++structural_bonds_[structural_bond_indices_[slot]].faces;
					}
				}
			}

			int largest_component = -1;
			int largest_count = 0;
			bool has_direct_support = false;
			const int support_ratio_millionths = std::clamp(
					static_cast<int>(std::llround(minimum_support_ratio * 1000000.0)),
					1,
					1000000);
			for (int region = 0; region < region_count; ++region) {
				if (structural_cell_counts_[region] > largest_count) {
					largest_count = structural_cell_counts_[region];
					largest_component = region;
				}
				has_direct_support = has_direct_support || structural_direct_supported_[region] != 0U;
				const int characteristic_area = characteristic_cross_section_cells(
						structural_cell_counts_[region]);
				structural_required_faces_[region] = std::max(
						1,
						static_cast<int>((
								static_cast<int64_t>(characteristic_area) * support_ratio_millionths
								+ 999999) / 1000000));
			}
			if (!has_direct_support && largest_component >= 0) {
				structural_direct_supported_[largest_component] = 1U;
			}
			structural_supported_ = structural_direct_supported_;
			for (int region = 0; region < region_count; ++region) {
				if (structural_supported_[region] != 0U) {
					structural_support_budget_[region] = 0x3fffffff;
				}
			}
			for (int iteration = 0; iteration < region_count; ++iteration) {
				bool progressed = false;
				for (int region = 0; region < region_count; ++region) {
					if (structural_supported_[region] != 0U) {
						continue;
					}
					int available_faces = 0;
					for (const StructuralBond &bond : structural_bonds_) {
						const int neighbor = bond.first == region
								? bond.second
								: (bond.second == region ? bond.first : -1);
						if (neighbor < 0 || structural_supported_[neighbor] == 0U) {
							continue;
						}
						available_faces += std::min(bond.faces, structural_support_budget_[neighbor]);
					}
					if (available_faces < structural_required_faces_[region]) {
						continue;
					}
					structural_supported_[region] = 1U;
					structural_support_budget_[region] = std::max(
							available_faces - structural_required_faces_[region], 0);
					progressed = true;
				}
				if (!progressed) {
					break;
				}
			}

			int weak_bond_count = 0;
			for (const StructuralBond &bond : structural_bonds_) {
				if (bond.faces < std::min(
						structural_required_faces_[bond.first],
						structural_required_faces_[bond.second])) {
					++weak_bond_count;
				}
			}
			Array components;
			for (int region = 0; region < region_count; ++region) {
				Dictionary component;
				component[StringName("id")] = region;
				component[StringName("cell_count")] = structural_cell_counts_[region];
				component[StringName("connects_outside")] = structural_supported_[region] != 0U;
				component[StringName("directly_anchored")] = structural_direct_supported_[region] != 0U;
				component[StringName("required_support_faces")] = structural_required_faces_[region];
				component[StringName("minimum")] = structural_minimums_[region];
				component[StringName("maximum")] = structural_maximums_[region];
				components.push_back(component);
			}
			PackedInt32Array labels;
			labels.resize(cell_count);
			std::copy(structural_labels_.begin(), structural_labels_.end(), labels.ptrw());
			result[StringName("valid")] = true;
			result[StringName("labels")] = labels;
			result[StringName("components")] = components;
			result[StringName("largest_component")] = largest_component;
			result[StringName("support_refined")] = true;
			result[StringName("weak_bond_count")] = weak_bond_count;
			result[StringName("core_component_count")] = core_component_count;
			return result;
		}
		std::fill(structural_labels_.begin(), structural_labels_.end(), -1);
	}

	Array components;
	int largest_component = -1;
	int largest_count = 0;
	for (int start = 0; start < cell_count; ++start) {
		if (structural_solid_[start] == 0U || structural_labels_[start] >= 0) {
			continue;
		}
		const int component_id = components.size();
		int head = 0;
		int tail = 1;
		structural_queue_[0] = start;
		structural_labels_[start] = component_id;
		int count = 0;
		bool connects_outside = false;
		Vector3i minimum = cell_size - Vector3i(1, 1, 1);
		Vector3i maximum;
		while (head < tail) {
			const int current_index = structural_queue_[head++];
			const int z = current_index / cell_stride_z;
			const int remainder = current_index - z * cell_stride_z;
			const int y = remainder / cell_size.x;
			const int x = remainder - y * cell_size.x;
			connects_outside = connects_outside
					|| (x == 0 && anchors[0] != 0U)
					|| (y == 0 && anchors[1] != 0U)
					|| (z == 0 && anchors[2] != 0U)
					|| (x == cell_size.x - 1 && anchors[3] != 0U)
					|| (y == cell_size.y - 1 && anchors[4] != 0U)
					|| (z == cell_size.z - 1 && anchors[5] != 0U);
			minimum.x = std::min(minimum.x, x);
			minimum.y = std::min(minimum.y, y);
			minimum.z = std::min(minimum.z, z);
			maximum.x = std::max(maximum.x, x);
			maximum.y = std::max(maximum.y, y);
			maximum.z = std::max(maximum.z, z);
			++count;
			for (const Vector3i &offset : kFaceNeighborOffsets) {
				const int neighbor_x = x + offset.x;
				const int neighbor_y = y + offset.y;
				const int neighbor_z = z + offset.z;
				if (neighbor_x < 0 || neighbor_x >= cell_size.x
						|| neighbor_y < 0 || neighbor_y >= cell_size.y
						|| neighbor_z < 0 || neighbor_z >= cell_size.z) {
					continue;
				}
				const int neighbor_index = neighbor_x
						+ neighbor_y * cell_stride_y + neighbor_z * cell_stride_z;
				if (structural_solid_[neighbor_index] == 0U
						|| structural_labels_[neighbor_index] >= 0) {
					continue;
				}
				structural_labels_[neighbor_index] = component_id;
				structural_queue_[tail++] = neighbor_index;
			}
		}
		Dictionary component;
		component[StringName("id")] = component_id;
		component[StringName("cell_count")] = count;
		component[StringName("connects_outside")] = connects_outside;
		component[StringName("minimum")] = minimum;
		component[StringName("maximum")] = maximum;
		components.push_back(component);
		if (count > largest_count) {
			largest_count = count;
			largest_component = component_id;
		}
	}

	PackedInt32Array labels;
	labels.resize(cell_count);
	int32_t *label_output = labels.ptrw();
	std::copy(structural_labels_.begin(), structural_labels_.end(), label_output);
	result[StringName("valid")] = true;
	result[StringName("labels")] = labels;
	result[StringName("components")] = components;
	result[StringName("largest_component")] = largest_component;
	if (minimum_support_ratio >= 0.0) {
		result[StringName("support_refined")] = false;
		result[StringName("weak_bond_count")] = 0;
		result[StringName("core_component_count")] = core_component_count;
	}
	return result;
}

int SdfNativeKernel::dense_sample_index(int x, int y, int z) const {
	const int stride_y = dense_cell_size_.x + 1;
	const int stride_z = stride_y * (dense_cell_size_.y + 1);
	return x + y * stride_y + z * stride_z;
}

bool SdfNativeKernel::synchronize_dense_field(
		const Array &brick_states,
		const Vector3 &half_extents,
		double voxel_size,
		const Vector3i &total_cells,
		int brick_cells,
		double narrow_band) {
	dense_ready_ = false;
	if (voxel_size <= 0.0 || narrow_band <= 0.0 || brick_cells < 2 || brick_cells > 64
			|| total_cells.x <= 0 || total_cells.y <= 0 || total_cells.z <= 0) {
		return false;
	}
	const int64_t sample_count = static_cast<int64_t>(total_cells.x + 1)
			* (total_cells.y + 1) * (total_cells.z + 1);
	if (sample_count <= 0 || sample_count > 16777216) {
		return false;
	}
	dense_half_extents_ = half_extents;
	dense_voxel_size_ = voxel_size;
	dense_cell_size_ = total_cells;
	dense_brick_cells_ = brick_cells;
	dense_narrow_band_ = narrow_band;
	dense_distances_.resize(static_cast<std::size_t>(sample_count));
	const real_t dense_voxel = static_cast<real_t>(voxel_size);
	for (int z = 0; z <= total_cells.z; ++z) {
		const real_t position_z = -half_extents.z + static_cast<real_t>(z) * dense_voxel;
		for (int y = 0; y <= total_cells.y; ++y) {
			const real_t position_y = -half_extents.y + static_cast<real_t>(y) * dense_voxel;
			for (int x = 0; x <= total_cells.x; ++x) {
				const real_t position_x = -half_extents.x + static_cast<real_t>(x) * dense_voxel;
				const Vector3 point(position_x, position_y, position_z);
				const Vector3 absolute(std::abs(point.x), std::abs(point.y), std::abs(point.z));
				const Vector3 q = absolute - half_extents;
				const Vector3 outside(
						std::max(q.x, static_cast<real_t>(0.0)),
						std::max(q.y, static_cast<real_t>(0.0)),
						std::max(q.z, static_cast<real_t>(0.0)));
				dense_distances_[dense_sample_index(x, y, z)] = static_cast<float>(
						outside.length() + std::min(
								std::max(q.x, std::max(q.y, q.z)), static_cast<real_t>(0.0)));
			}
		}
	}
	for (int state_index = 0; state_index < brick_states.size(); ++state_index) {
		const Variant value = brick_states[state_index];
		if (value.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary state = value;
		const Vector3i coordinate = state.get(StringName("coordinate"), Vector3i());
		const bool uniform = state.get(StringName("uniform"), true);
		const int16_t uniform_raw = static_cast<int16_t>(std::clamp(
				static_cast<int64_t>(state.get(StringName("uniform_raw"), 32767)),
				static_cast<int64_t>(-32767), static_cast<int64_t>(32767)));
		const PackedByteArray bytes = state.get(StringName("distance_bytes"), PackedByteArray());
		if (!uniform) {
			const int side = brick_cells + 1;
			if (bytes.size() != side * side * side * 2) {
				return false;
			}
		}
		update_dense_brick(coordinate, uniform, uniform_raw, bytes);
	}
	dense_ready_ = true;
	return true;
}

bool SdfNativeKernel::update_cached_brick(const Dictionary &brick_state) {
	if (!dense_ready_) {
		return false;
	}
	const Vector3i coordinate = brick_state.get(StringName("coordinate"), Vector3i(-1, -1, -1));
	const bool uniform = brick_state.get(StringName("uniform"), true);
	const int16_t uniform_raw = static_cast<int16_t>(std::clamp(
			static_cast<int64_t>(brick_state.get(StringName("uniform_raw"), 32767)),
			static_cast<int64_t>(-32767), static_cast<int64_t>(32767)));
	const PackedByteArray bytes = brick_state.get(
			StringName("distance_bytes"), PackedByteArray());
	const Vector3i brick_counts(
			(dense_cell_size_.x + dense_brick_cells_ - 1) / dense_brick_cells_,
			(dense_cell_size_.y + dense_brick_cells_ - 1) / dense_brick_cells_,
			(dense_cell_size_.z + dense_brick_cells_ - 1) / dense_brick_cells_);
	if (coordinate.x < 0 || coordinate.y < 0 || coordinate.z < 0
			|| coordinate.x >= brick_counts.x || coordinate.y >= brick_counts.y
			|| coordinate.z >= brick_counts.z) {
		return false;
	}
	const int side = dense_brick_cells_ + 1;
	if (!uniform && bytes.size() != side * side * side * 2) {
		return false;
	}
	update_dense_brick(coordinate, uniform, uniform_raw, bytes);
	return true;
}

Dictionary SdfNativeKernel::erase_cached_cells(const Array &cells, const Array &brick_states) {
	Dictionary result;
	result[StringName("valid")] = false;
	result[StringName("changed_samples")] = 0;
	result[StringName("bricks")] = Array();
	if (!dense_ready_ || cells.is_empty() || dense_brick_cells_ <= 0) {
		return result;
	}
	const Vector3i sample_size = dense_cell_size_ + Vector3i(1, 1, 1);
	const int64_t sample_count_64 = static_cast<int64_t>(sample_size.x)
			* sample_size.y * sample_size.z;
	const Vector3i brick_counts(
			dense_cell_size_.x / dense_brick_cells_,
			dense_cell_size_.y / dense_brick_cells_,
			dense_cell_size_.z / dense_brick_cells_);
	const int brick_count = brick_counts.x * brick_counts.y * brick_counts.z;
	if (sample_count_64 <= 0 || sample_count_64 > 16777216 || brick_count <= 0) {
		return result;
	}
	std::vector<Dictionary> previous_brick_states(static_cast<std::size_t>(brick_count));
	for (int state_index = 0; state_index < brick_states.size(); ++state_index) {
		const Variant value = brick_states[state_index];
		if (value.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary state = value;
		const Vector3i coordinate = state.get(StringName("coordinate"), Vector3i(-1, -1, -1));
		if (coordinate.x < 0 || coordinate.y < 0 || coordinate.z < 0
				|| coordinate.x >= brick_counts.x || coordinate.y >= brick_counts.y
				|| coordinate.z >= brick_counts.z) {
			continue;
		}
		const int index = coordinate.x + brick_counts.x
				* (coordinate.y + brick_counts.y * coordinate.z);
		previous_brick_states[index] = state;
	}
	const std::size_t sample_count = static_cast<std::size_t>(sample_count_64);
	if (erase_sample_stamps_.size() != sample_count) {
		erase_sample_stamps_.assign(sample_count, 0U);
		erase_sample_stamp_ = 0;
	}
	++erase_sample_stamp_;
	if (erase_sample_stamp_ == 0U) {
		std::fill(erase_sample_stamps_.begin(), erase_sample_stamps_.end(), 0U);
		erase_sample_stamp_ = 1U;
	}
	if (erase_brick_sample_indices_.size() != static_cast<std::size_t>(brick_count)) {
		erase_brick_sample_indices_.clear();
		erase_brick_sample_indices_.resize(static_cast<std::size_t>(brick_count));
	}
	for (const int32_t brick_index : erase_touched_bricks_) {
		erase_brick_sample_indices_[brick_index].clear();
	}
	erase_touched_bricks_.clear();
	bool has_bounds = false;
	Vector3i changed_minimum;
	Vector3i changed_maximum;
	int changed_samples = 0;
	const int sample_plane = sample_size.x * sample_size.y;
	for (int cell_index = 0; cell_index < cells.size(); ++cell_index) {
		const Variant value = cells[cell_index];
		if (value.get_type() != Variant::VECTOR3I) {
			continue;
		}
		const Vector3i cell = value;
		for (int offset_z = 0; offset_z <= 1; ++offset_z) {
			const int sample_z = cell.z + offset_z;
			if (sample_z < 0 || sample_z >= sample_size.z) {
				continue;
			}
			for (int offset_y = 0; offset_y <= 1; ++offset_y) {
				const int sample_y = cell.y + offset_y;
				if (sample_y < 0 || sample_y >= sample_size.y) {
					continue;
				}
				for (int offset_x = 0; offset_x <= 1; ++offset_x) {
					const int sample_x = cell.x + offset_x;
					if (sample_x < 0 || sample_x >= sample_size.x) {
						continue;
					}
					const int global_index = sample_x + sample_size.x * sample_y
							+ sample_plane * sample_z;
					if (erase_sample_stamps_[global_index] == erase_sample_stamp_) {
						continue;
					}
					erase_sample_stamps_[global_index] = erase_sample_stamp_;
					if (dense_distances_[global_index] >= static_cast<float>(dense_narrow_band_)) {
						continue;
					}
					dense_distances_[global_index] = static_cast<float>(dense_narrow_band_);
					const Vector3i brick_coordinate(
							std::min(sample_x / dense_brick_cells_, brick_counts.x - 1),
							std::min(sample_y / dense_brick_cells_, brick_counts.y - 1),
							std::min(sample_z / dense_brick_cells_, brick_counts.z - 1));
					const int brick_index = brick_coordinate.x + brick_counts.x
							* (brick_coordinate.y + brick_counts.y * brick_coordinate.z);
					auto &brick_samples = erase_brick_sample_indices_[brick_index];
					if (brick_samples.empty()) {
						erase_touched_bricks_.push_back(brick_index);
					}
					const Vector3i local = Vector3i(sample_x, sample_y, sample_z)
							- brick_coordinate * dense_brick_cells_;
					const int side = dense_brick_cells_ + 1;
					brick_samples.push_back(local.x + side * (local.y + side * local.z));
					const Vector3i sample(sample_x, sample_y, sample_z);
					if (!has_bounds) {
						has_bounds = true;
						changed_minimum = sample;
						changed_maximum = sample;
					} else {
						changed_minimum = Vector3i(
								std::min(changed_minimum.x, sample_x),
								std::min(changed_minimum.y, sample_y),
								std::min(changed_minimum.z, sample_z));
						changed_maximum = Vector3i(
								std::max(changed_maximum.x, sample_x),
								std::max(changed_maximum.y, sample_y),
								std::max(changed_maximum.z, sample_z));
					}
					++changed_samples;
				}
			}
		}
	}
	Array brick_packets;
	brick_packets.resize(static_cast<int64_t>(erase_touched_bricks_.size()));
	for (std::size_t packet_index = 0; packet_index < erase_touched_bricks_.size(); ++packet_index) {
		const int brick_index = erase_touched_bricks_[packet_index];
		const int brick_z = brick_index / (brick_counts.x * brick_counts.y);
		const int plane_index = brick_index - brick_z * brick_counts.x * brick_counts.y;
		const int brick_y = plane_index / brick_counts.x;
		const int brick_x = plane_index - brick_y * brick_counts.x;
		const auto &source = erase_brick_sample_indices_[brick_index];
		const Vector3i brick_coordinate(brick_x, brick_y, brick_z);
		const int side = dense_brick_cells_ + 1;
		const int brick_sample_count = side * side * side;
		const Dictionary previous = previous_brick_states[brick_index];
		const bool previous_uniform = previous.get(StringName("uniform"), true);
		const int16_t previous_uniform_raw = static_cast<int16_t>(std::clamp(
				static_cast<int64_t>(previous.get(StringName("uniform_raw"), 32767)),
				static_cast<int64_t>(-32767), static_cast<int64_t>(32767)));
		const PackedByteArray previous_bytes = previous.get(
				StringName("distance_bytes"), PackedByteArray());
		int16_t storage_uniform_raw = previous_uniform_raw;
		PackedByteArray distance_bytes;
		distance_bytes.resize(brick_sample_count * 2);
		uint8_t *output = distance_bytes.ptrw();
		if (!previous.is_empty() && !previous_uniform
				&& previous_bytes.size() == brick_sample_count * 2) {
			std::copy(previous_bytes.ptr(), previous_bytes.ptr() + previous_bytes.size(), output);
		} else if (!previous.is_empty()) {
			for (int sample_index = 0; sample_index < brick_sample_count; ++sample_index) {
				write_raw(output, sample_index, previous_uniform_raw);
			}
		} else {
			int sample_index = 0;
			const Vector3i global_origin = brick_coordinate * dense_brick_cells_;
			for (int local_z = 0; local_z < side; ++local_z) {
				const real_t position_z = -dense_half_extents_.z
						+ static_cast<real_t>(global_origin.z + local_z) * dense_voxel_size_;
				for (int local_y = 0; local_y < side; ++local_y) {
					const real_t position_y = -dense_half_extents_.y
							+ static_cast<real_t>(global_origin.y + local_y) * dense_voxel_size_;
					for (int local_x = 0; local_x < side; ++local_x, ++sample_index) {
						const real_t position_x = -dense_half_extents_.x
								+ static_cast<real_t>(global_origin.x + local_x) * dense_voxel_size_;
						const Vector3 point(position_x, position_y, position_z);
						const Vector3 absolute(std::abs(point.x), std::abs(point.y), std::abs(point.z));
						const Vector3 q = absolute - dense_half_extents_;
						const Vector3 outside(
								std::max(q.x, static_cast<real_t>(0.0)),
								std::max(q.y, static_cast<real_t>(0.0)),
								std::max(q.z, static_cast<real_t>(0.0)));
						const double distance = outside.length() + std::min(
								std::max(q.x, std::max(q.y, q.z)), static_cast<real_t>(0.0));
						const int16_t raw = static_cast<int16_t>(std::clamp(
								std::lround(distance / dense_narrow_band_ * 32767.0),
								-32767L, 32767L));
						write_raw(output, sample_index, raw);
					}
				}
			}
			storage_uniform_raw = read_raw(output, 0);
		}
		for (const int32_t sample_index : source) {
			write_raw(output, sample_index, 32767);
		}
		Dictionary packet;
		packet[StringName("coordinate")] = brick_coordinate;
		// SparseSdfBrick materializes permanently after its first changed sample. Keep that exact
		// storage/checksum contract even when an erasure happens to make every byte equal again.
		packet[StringName("uniform")] = false;
		packet[StringName("uniform_raw")] = storage_uniform_raw;
		packet[StringName("distance_bytes")] = distance_bytes;
		packet[StringName("changed_samples")] = static_cast<int64_t>(source.size());
		brick_packets[static_cast<int64_t>(packet_index)] = packet;
	}
	result[StringName("valid")] = true;
	result[StringName("changed_samples")] = changed_samples;
	result[StringName("bricks")] = brick_packets;
	result[StringName("has_changed_sample_bounds")] = has_bounds;
	result[StringName("changed_sample_minimum")] = changed_minimum;
	result[StringName("changed_sample_maximum")] = changed_maximum;
	return result;
}

void SdfNativeKernel::update_dense_brick(
		const Vector3i &coordinate,
		bool uniform,
		int16_t uniform_raw,
		const PackedByteArray &distance_bytes) {
	if (dense_distances_.empty() || dense_brick_cells_ <= 0 || dense_narrow_band_ <= 0.0) {
		return;
	}
	const int side = dense_brick_cells_ + 1;
	const uint8_t *bytes = distance_bytes.is_empty() ? nullptr : distance_bytes.ptr();
	const Vector3i global_origin = coordinate * dense_brick_cells_;
	for (int z = 0; z < side; ++z) {
		const int global_z = global_origin.z + z;
		if (global_z < 0 || global_z > dense_cell_size_.z) {
			continue;
		}
		if (z == side - 1 && global_z < dense_cell_size_.z) {
			continue;
		}
		for (int y = 0; y < side; ++y) {
			const int global_y = global_origin.y + y;
			if (global_y < 0 || global_y > dense_cell_size_.y) {
				continue;
			}
			if (y == side - 1 && global_y < dense_cell_size_.y) {
				continue;
			}
			for (int x = 0; x < side; ++x) {
				const int global_x = global_origin.x + x;
				if (global_x < 0 || global_x > dense_cell_size_.x) {
					continue;
				}
				if (x == side - 1 && global_x < dense_cell_size_.x) {
					continue;
				}
				const int local = x + side * (y + side * z);
				const int16_t raw = uniform ? uniform_raw : read_raw(bytes, local);
				dense_distances_[dense_sample_index(global_x, global_y, global_z)] =
						static_cast<float>(static_cast<double>(raw) / 32767.0 * dense_narrow_band_);
			}
		}
	}
}

Dictionary SdfNativeKernel::capture_cached_chunk(
		const Vector3i &chunk_coordinate,
		int cells,
		int source_signature,
		const Dictionary &reuse_snapshot) {
	Dictionary result = reuse_snapshot.duplicate(false);
	result[StringName("valid")] = false;
	if (!dense_ready_ || cells <= 0 || cells > 64 || cells != dense_brick_cells_) {
		return result;
	}
	const int sample_grid_size = cells + kSampleHalo * 2;
	const int sample_count = sample_grid_size * sample_grid_size * sample_grid_size;
	PackedFloat32Array distances = result.get(
			StringName("sample_distances"), PackedFloat32Array());
	distances.resize(sample_count);
	float *output = distances.ptrw();
	const Vector3i chunk_origin = chunk_coordinate * cells;
	const real_t dense_voxel = static_cast<real_t>(dense_voxel_size_);
	int write_index = 0;
	for (int local_z = -kSampleHalo; local_z < cells + kSampleHalo; ++local_z) {
		const int global_z = chunk_origin.z + local_z;
		for (int local_y = -kSampleHalo; local_y < cells + kSampleHalo; ++local_y) {
			const int global_y = chunk_origin.y + local_y;
			for (int local_x = -kSampleHalo; local_x < cells + kSampleHalo; ++local_x) {
				const int global_x = chunk_origin.x + local_x;
				if (global_x >= 0 && global_y >= 0 && global_z >= 0
						&& global_x <= dense_cell_size_.x
						&& global_y <= dense_cell_size_.y
						&& global_z <= dense_cell_size_.z) {
					output[write_index++] = dense_distances_[dense_sample_index(
							global_x, global_y, global_z)];
					continue;
				}
				const Vector3 point(
						-dense_half_extents_.x + static_cast<real_t>(global_x) * dense_voxel,
						-dense_half_extents_.y + static_cast<real_t>(global_y) * dense_voxel,
						-dense_half_extents_.z + static_cast<real_t>(global_z) * dense_voxel);
				const Vector3 absolute(std::abs(point.x), std::abs(point.y), std::abs(point.z));
				const Vector3 q = absolute - dense_half_extents_;
				const Vector3 outside(
						std::max(q.x, static_cast<real_t>(0.0)),
						std::max(q.y, static_cast<real_t>(0.0)),
						std::max(q.z, static_cast<real_t>(0.0)));
				output[write_index++] = static_cast<float>(outside.length() + std::min(
						std::max(q.x, std::max(q.y, q.z)), static_cast<real_t>(0.0)));
			}
		}
	}
	result[StringName("chunk_coordinate")] = chunk_coordinate;
	result[StringName("cells")] = cells;
	result[StringName("voxel_size")] = dense_voxel_size_;
	result[StringName("field_origin")] = -dense_half_extents_;
	result[StringName("field_half_extents")] = dense_half_extents_;
	result[StringName("chunk_global_cell_origin")] = chunk_origin;
	result[StringName("sample_grid_size")] = sample_grid_size;
	result[StringName("sample_distances")] = distances;
	result[StringName("source_signature")] = source_signature;
	result[StringName("valid")] = true;
	return result;
}

Dictionary SdfNativeKernel::capture_cached_fragment_tile(
		const Vector3i &tile_origin,
		int cells,
		const Vector3i &component_minimum,
		const Vector3i &component_size,
		const PackedByteArray &membership,
		const Dictionary &reuse_snapshot) {
	Dictionary result = reuse_snapshot.duplicate(false);
	result[StringName("valid")] = false;
	const int64_t component_cell_count = static_cast<int64_t>(component_size.x)
			* component_size.y * component_size.z;
	if (!dense_ready_ || cells <= 0 || cells > 64
			|| component_size.x <= 0 || component_size.y <= 0 || component_size.z <= 0
			|| component_cell_count <= 0 || membership.size() != component_cell_count) {
		return result;
	}
	const int sample_grid_size = cells + kSampleHalo * 2;
	const int sample_count = sample_grid_size * sample_grid_size * sample_grid_size;
	PackedFloat32Array distances = result.get(
			StringName("sample_distances"), PackedFloat32Array());
	distances.resize(sample_count);
	float *output = distances.ptrw();
	const uint8_t *member = membership.ptr();
	const real_t voxel = static_cast<real_t>(dense_voxel_size_);
	int write_index = 0;
	for (int local_z = -kSampleHalo; local_z < cells + kSampleHalo; ++local_z) {
		const int global_z = tile_origin.z + local_z;
		for (int local_y = -kSampleHalo; local_y < cells + kSampleHalo; ++local_y) {
			const int global_y = tile_origin.y + local_y;
			for (int local_x = -kSampleHalo; local_x < cells + kSampleHalo; ++local_x) {
				const int global_x = tile_origin.x + local_x;
				bool touches_component = false;
				for (int offset_z = 0; offset_z <= 1 && !touches_component; ++offset_z) {
					const int component_z = global_z - offset_z - component_minimum.z;
					if (component_z < 0 || component_z >= component_size.z) {
						continue;
					}
					for (int offset_y = 0; offset_y <= 1 && !touches_component; ++offset_y) {
						const int component_y = global_y - offset_y - component_minimum.y;
						if (component_y < 0 || component_y >= component_size.y) {
							continue;
						}
						for (int offset_x = 0; offset_x <= 1; ++offset_x) {
							const int component_x = global_x - offset_x - component_minimum.x;
							if (component_x < 0 || component_x >= component_size.x) {
								continue;
							}
							const int member_index = component_x + component_size.x
									* (component_y + component_size.y * component_z);
							if (member[member_index] != 0U) {
								touches_component = true;
								break;
							}
						}
					}
				}
				if (!touches_component) {
					output[write_index++] = static_cast<float>(dense_narrow_band_);
					continue;
				}
				if (global_x >= 0 && global_y >= 0 && global_z >= 0
						&& global_x <= dense_cell_size_.x
						&& global_y <= dense_cell_size_.y
						&& global_z <= dense_cell_size_.z) {
					output[write_index++] = dense_distances_[dense_sample_index(
							global_x, global_y, global_z)];
					continue;
				}
				const Vector3 point(
						-dense_half_extents_.x + static_cast<real_t>(global_x) * voxel,
						-dense_half_extents_.y + static_cast<real_t>(global_y) * voxel,
						-dense_half_extents_.z + static_cast<real_t>(global_z) * voxel);
				const Vector3 q(std::abs(point.x), std::abs(point.y), std::abs(point.z));
				const Vector3 relative = q - dense_half_extents_;
				const Vector3 outside(
						std::max(relative.x, static_cast<real_t>(0.0)),
						std::max(relative.y, static_cast<real_t>(0.0)),
						std::max(relative.z, static_cast<real_t>(0.0)));
				output[write_index++] = static_cast<float>(outside.length() + std::min(
						std::max(relative.x, std::max(relative.y, relative.z)),
						static_cast<real_t>(0.0)));
			}
		}
	}
	result[StringName("chunk_coordinate")] = Vector3i();
	result[StringName("cells")] = cells;
	result[StringName("voxel_size")] = dense_voxel_size_;
	result[StringName("field_origin")] = -dense_half_extents_;
	result[StringName("field_half_extents")] = dense_half_extents_;
	result[StringName("chunk_global_cell_origin")] = tile_origin;
	result[StringName("sample_grid_size")] = sample_grid_size;
	result[StringName("sample_distances")] = distances;
	result[StringName("source_signature")] = 0;
	result[StringName("valid")] = true;
	return result;
}

bool SdfNativeKernel::begin_brush_union(const Dictionary &request) {
	mutation_ready_ = false;
	operations_.clear();
	mutation_half_extents_ = request.get(StringName("half_extents"), Vector3());
	mutation_combined_minimum_ = request.get(StringName("combined_minimum"), Vector3());
	mutation_combined_maximum_ = request.get(StringName("combined_maximum"), Vector3());
	mutation_voxel_size_ = static_cast<double>(request.get(StringName("voxel_size"), 0.0));
	mutation_narrow_band_ = static_cast<double>(request.get(StringName("narrow_band"), 0.0));
	mutation_maximum_radius_ = static_cast<double>(request.get(StringName("maximum_radius"), 0.0));
	mutation_spatial_warp_ = static_cast<double>(request.get(StringName("spatial_warp"), 0.0));
	noise_frequency_ = static_cast<double>(request.get(StringName("noise_frequency"), 1.0));
	mutation_brick_cells_ = static_cast<int64_t>(request.get(StringName("brick_cells"), 0));
	noise_origin_ = request.get(StringName("noise_origin"), Vector3i());
	noise_size_ = request.get(StringName("noise_size"), Vector3i());
	noise_values_ = request.get(StringName("noise_values"), PackedFloat32Array());

	const int operation_count = static_cast<int64_t>(request.get(StringName("operation_count"), 0));
	const PackedByteArray kinds = request.get(StringName("operation_kinds"), PackedByteArray());
	const PackedVector3Array starts = request.get(StringName("operation_starts"), PackedVector3Array());
	const PackedVector3Array ends = request.get(StringName("operation_ends"), PackedVector3Array());
	const PackedFloat32Array first_radii = request.get(
			StringName("operation_first_radii"), PackedFloat32Array());
	const PackedFloat32Array second_radii = request.get(
			StringName("operation_second_radii"), PackedFloat32Array());
	if (operation_count <= 0 || mutation_brick_cells_ < 2 || mutation_brick_cells_ > 64
			|| mutation_voxel_size_ <= 0.0F || mutation_narrow_band_ <= 0.0F
			|| kinds.size() < operation_count || starts.size() < operation_count
			|| ends.size() < operation_count || first_radii.size() < operation_count
			|| second_radii.size() < operation_count) {
		return false;
	}
	if (mutation_spatial_warp_ > 0.0F) {
		const int64_t noise_count = static_cast<int64_t>(noise_size_.x) * noise_size_.y * noise_size_.z;
		if (noise_size_.x < 2 || noise_size_.y < 2 || noise_size_.z < 2
				|| noise_values_.size() < noise_count || noise_frequency_ <= 0.0F) {
			return false;
		}
	}

	operations_.reserve(operation_count);
	const uint8_t *kind_data = kinds.ptr();
	const Vector3 *start_data = starts.ptr();
	const Vector3 *end_data = ends.ptr();
	const float *first_radius_data = first_radii.ptr();
	const float *second_radius_data = second_radii.ptr();
	const double grow = mutation_narrow_band_ + mutation_voxel_size_;
	for (int index = 0; index < operation_count; ++index) {
		BrushOperation operation;
		operation.kind = kind_data[index];
		operation.start = start_data[index];
		operation.end = end_data[index];
		operation.first_radius = std::max(first_radius_data[index], 0.0F);
		operation.second_radius = std::max(second_radius_data[index], 0.0F);
		const double radius = std::max(operation.first_radius, operation.second_radius) + grow;
		operation.bounds_minimum = Vector3(
				std::min(operation.start.x, operation.end.x) - radius,
				std::min(operation.start.y, operation.end.y) - radius,
				std::min(operation.start.z, operation.end.z) - radius);
		operation.bounds_maximum = Vector3(
				std::max(operation.start.x, operation.end.x) + radius,
				std::max(operation.start.y, operation.end.y) + radius,
				std::max(operation.start.z, operation.end.z) + radius);
		operations_.push_back(operation);
	}
	mutation_ready_ = true;
	return true;
}

double SdfNativeKernel::box_distance(const Vector3 &point) const {
	const Vector3 absolute(std::abs(point.x), std::abs(point.y), std::abs(point.z));
	const Vector3 q = absolute - mutation_half_extents_;
	const Vector3 outside(
			std::max(q.x, static_cast<real_t>(0.0)),
			std::max(q.y, static_cast<real_t>(0.0)),
			std::max(q.z, static_cast<real_t>(0.0)));
	return static_cast<double>(outside.length())
			+ static_cast<double>(std::min(
					std::max(q.x, std::max(q.y, q.z)), static_cast<real_t>(0.0)));
}

double SdfNativeKernel::brush_distance(const BrushOperation &operation, const Vector3 &point) const {
	if (operation.kind == 0) {
		return (point - operation.start).length() - operation.first_radius;
	}
	const Vector3 segment = operation.end - operation.start;
	const double segment_length_squared = segment.length_squared();
	if (segment_length_squared <= static_cast<real_t>(0.000001)) {
		return (point - operation.start).length()
				- std::max(operation.first_radius, operation.second_radius);
	}
	const double interpolation = std::clamp(
			static_cast<double>((point - operation.start).dot(segment)) / segment_length_squared,
			0.0,
			1.0);
	const double radius = operation.kind == 2
			? operation.first_radius
					+ (operation.second_radius - operation.first_radius) * interpolation
			: operation.first_radius;
	return static_cast<double>((
			point - (operation.start + segment * static_cast<real_t>(interpolation))).length()) - radius;
}

double SdfNativeKernel::sample_cached_noise(const Vector3 &point) const {
	if (mutation_spatial_warp_ <= 0.0F || noise_values_.is_empty()) {
		return 0.0F;
	}
	const Vector3 scaled = point * noise_frequency_;
	const int lattice_x = static_cast<int>(std::floor(scaled.x));
	const int lattice_y = static_cast<int>(std::floor(scaled.y));
	const int lattice_z = static_cast<int>(std::floor(scaled.z));
	const int local_x = lattice_x - noise_origin_.x;
	const int local_y = lattice_y - noise_origin_.y;
	const int local_z = lattice_z - noise_origin_.z;
	if (local_x < 0 || local_y < 0 || local_z < 0 || local_x + 1 >= noise_size_.x
			|| local_y + 1 >= noise_size_.y || local_z + 1 >= noise_size_.z) {
		return 0.0F;
	}
	auto fade = [](double value) {
		const double clamped = std::clamp(value, 0.0, 1.0);
		return clamped * clamped * clamped * (clamped * (clamped * 6.0 - 15.0) + 10.0);
	};
	const double tx = fade(scaled.x - lattice_x);
	const double ty = fade(scaled.y - lattice_y);
	const double tz = fade(scaled.z - lattice_z);
	const int stride_y = noise_size_.x;
	const int stride_z = stride_y * noise_size_.y;
	const int base = local_x + stride_y * local_y + stride_z * local_z;
	const float *values = noise_values_.ptr();
	auto lerp = [](double from, double to, double weight) { return from + (to - from) * weight; };
	const double x00 = lerp(values[base], values[base + 1], tx);
	const double x10 = lerp(values[base + stride_y], values[base + stride_y + 1], tx);
	const double x01 = lerp(values[base + stride_z], values[base + stride_z + 1], tx);
	const double x11 = lerp(
			values[base + stride_z + stride_y], values[base + stride_z + stride_y + 1], tx);
	return lerp(lerp(x00, x10, ty), lerp(x01, x11, ty), tz);
}

int16_t SdfNativeKernel::quantize_distance(double value) const {
	const double clamped = std::clamp(value, -mutation_narrow_band_, mutation_narrow_band_);
	const long raw = std::lround(clamped / mutation_narrow_band_ * 32767.0);
	return static_cast<int16_t>(std::clamp(raw, -32767L, 32767L));
}

double SdfNativeKernel::dequantize_distance(int16_t value) const {
	return static_cast<double>(value) / 32767.0 * mutation_narrow_band_;
}

int16_t SdfNativeKernel::read_raw(const uint8_t *bytes, int index) {
	const uint16_t encoded = static_cast<uint16_t>(bytes[index * 2])
			| static_cast<uint16_t>(static_cast<uint16_t>(bytes[index * 2 + 1]) << 8U);
	return encoded >= 32768U
			? static_cast<int16_t>(static_cast<int32_t>(encoded) - 65536)
			: static_cast<int16_t>(encoded);
}

void SdfNativeKernel::write_raw(uint8_t *bytes, int index, int16_t value) {
	const uint16_t encoded = static_cast<uint16_t>(value);
	bytes[index * 2] = static_cast<uint8_t>(encoded & 0xffU);
	bytes[index * 2 + 1] = static_cast<uint8_t>((encoded >> 8U) & 0xffU);
}

Dictionary SdfNativeKernel::apply_brush_union_to_brick(const Dictionary &brick_state) {
	Dictionary result;
	result[StringName("valid")] = false;
	result[StringName("changed")] = false;
	result[StringName("changed_samples")] = 0;
	if (!mutation_ready_) {
		return result;
	}
	const Vector3i coordinate = brick_state.get(StringName("coordinate"), Vector3i());
	const bool exists = brick_state.get(StringName("exists"), false);
	const bool uniform = brick_state.get(StringName("uniform"), true);
	const int16_t uniform_raw = static_cast<int16_t>(std::clamp(
			static_cast<int64_t>(brick_state.get(StringName("uniform_raw"), 32767)),
			static_cast<int64_t>(-32767),
			static_cast<int64_t>(32767)));
	const PackedByteArray input_bytes = brick_state.get(
			StringName("distance_bytes"), PackedByteArray());
	const int samples_per_axis = mutation_brick_cells_ + 1;
	const int sample_count = samples_per_axis * samples_per_axis * samples_per_axis;
	if (exists && !uniform && input_bytes.size() != sample_count * 2) {
		return result;
	}
	result[StringName("valid")] = true;

	const Vector3i global_origin = coordinate * mutation_brick_cells_;
	auto local_grid_coordinate = [&](real_t position, real_t half_extent, int origin, bool maximum) {
		const double sample = (static_cast<double>(position) + half_extent) / mutation_voxel_size_;
		const int grid = maximum ? static_cast<int>(std::floor(sample)) : static_cast<int>(std::ceil(sample));
		return std::clamp(grid - origin, 0, samples_per_axis - 1);
	};
	const Vector3i grid_minimum(
			local_grid_coordinate(mutation_combined_minimum_.x, mutation_half_extents_.x, global_origin.x, false),
			local_grid_coordinate(mutation_combined_minimum_.y, mutation_half_extents_.y, global_origin.y, false),
			local_grid_coordinate(mutation_combined_minimum_.z, mutation_half_extents_.z, global_origin.z, false));
	const Vector3i grid_maximum(
			local_grid_coordinate(mutation_combined_maximum_.x, mutation_half_extents_.x, global_origin.x, true),
			local_grid_coordinate(mutation_combined_maximum_.y, mutation_half_extents_.y, global_origin.y, true),
			local_grid_coordinate(mutation_combined_maximum_.z, mutation_half_extents_.z, global_origin.z, true));
	const uint8_t *input = input_bytes.is_empty() ? nullptr : input_bytes.ptr();
	mutations_.clear();
	const std::size_t affected_count = static_cast<std::size_t>(grid_maximum.x - grid_minimum.x + 1)
			* (grid_maximum.y - grid_minimum.y + 1) * (grid_maximum.z - grid_minimum.z + 1);
	mutations_.reserve(affected_count);
	bool has_surface_bounds = false;
	Vector3i changed_minimum;
	Vector3i changed_maximum;
	const double mesh_influence_band = mutation_voxel_size_ * 2.5;

	for (int sample_z = grid_minimum.z; sample_z <= grid_maximum.z; ++sample_z) {
		const int global_z = global_origin.z + sample_z;
		const double position_z = -static_cast<double>(mutation_half_extents_.z)
				+ global_z * mutation_voxel_size_;
		for (int sample_y = grid_minimum.y; sample_y <= grid_maximum.y; ++sample_y) {
			const int global_y = global_origin.y + sample_y;
			const double position_y = -static_cast<double>(mutation_half_extents_.y)
					+ global_y * mutation_voxel_size_;
			int linear_index = grid_minimum.x + samples_per_axis * (sample_y + samples_per_axis * sample_z);
			double position_x = -static_cast<double>(mutation_half_extents_.x)
					+ (global_origin.x + grid_minimum.x) * mutation_voxel_size_;
			for (int sample_x = grid_minimum.x; sample_x <= grid_maximum.x; ++sample_x, ++linear_index) {
				const int global_x = global_origin.x + sample_x;
				const Vector3 position(
						static_cast<real_t>(position_x),
						static_cast<real_t>(position_y),
						static_cast<real_t>(position_z));
				position_x += mutation_voxel_size_;
				const int16_t previous_raw = exists
						? (uniform ? uniform_raw : read_raw(input, linear_index))
						: quantize_distance(box_distance(position));
				const double previous = exists
						? dequantize_distance(previous_raw)
						: box_distance(position);
				if (previous >= mutation_maximum_radius_) {
					continue;
				}
				const double warp_noise = mutation_spatial_warp_ > 0.0
						? sample_cached_noise(position) * mutation_spatial_warp_
						: 0.0F;
				double cutter = std::numeric_limits<double>::infinity();
				for (const BrushOperation &operation : operations_) {
					if (position.x < operation.bounds_minimum.x || position.y < operation.bounds_minimum.y
							|| position.z < operation.bounds_minimum.z || position.x > operation.bounds_maximum.x
							|| position.y > operation.bounds_maximum.y || position.z > operation.bounds_maximum.z) {
						continue;
					}
					double distance = brush_distance(operation, position);
					const double characteristic_radius = std::max(
							operation.first_radius, operation.second_radius);
					if (warp_noise != 0.0F && characteristic_radius > 0.0F) {
						distance -= warp_noise * characteristic_radius;
					}
					cutter = std::min(cutter, distance);
				}
				if (cutter > mutation_narrow_band_) {
					continue;
				}
				const double next = std::max(previous, -cutter);
				const int16_t next_raw = quantize_distance(next);
				if (next_raw == previous_raw) {
					continue;
				}
				mutations_.push_back({linear_index, next_raw});
				if ((previous < 0.0F) != (next < 0.0F)
						|| std::min(std::abs(previous), std::abs(next)) <= mesh_influence_band) {
					const Vector3i global_sample(global_x, global_y, global_z);
					if (!has_surface_bounds) {
						has_surface_bounds = true;
						changed_minimum = global_sample;
						changed_maximum = global_sample;
					} else {
						changed_minimum = Vector3i(
								std::min(changed_minimum.x, global_x),
								std::min(changed_minimum.y, global_y),
								std::min(changed_minimum.z, global_z));
						changed_maximum = Vector3i(
								std::max(changed_maximum.x, global_x),
								std::max(changed_maximum.y, global_y),
								std::max(changed_maximum.z, global_z));
					}
				}
			}
		}
	}
	if (mutations_.empty()) {
		return result;
	}

	PackedByteArray output;
	int16_t output_uniform_raw = uniform_raw;
	if (exists && !uniform) {
		output = input_bytes.duplicate();
	} else {
		output.resize(sample_count * 2);
		uint8_t *bytes = output.ptrw();
		if (exists) {
			for (int index = 0; index < sample_count; ++index) {
				write_raw(bytes, index, uniform_raw);
			}
		} else {
			int index = 0;
			for (int z = 0; z < samples_per_axis; ++z) {
				const double position_z = -static_cast<double>(mutation_half_extents_.z)
						+ (global_origin.z + z) * mutation_voxel_size_;
				for (int y = 0; y < samples_per_axis; ++y) {
					const double position_y = -static_cast<double>(mutation_half_extents_.y)
							+ (global_origin.y + y) * mutation_voxel_size_;
					for (int x = 0; x < samples_per_axis; ++x, ++index) {
						const double position_x = -static_cast<double>(mutation_half_extents_.x)
								+ (global_origin.x + x) * mutation_voxel_size_;
						const int16_t baseline_raw = quantize_distance(box_distance(
								Vector3(
										static_cast<real_t>(position_x),
										static_cast<real_t>(position_y),
										static_cast<real_t>(position_z))));
						if (index == 0) {
							output_uniform_raw = baseline_raw;
						}
						write_raw(bytes, index, baseline_raw);
					}
				}
			}
		}
	}
	uint8_t *output_bytes = output.ptrw();
	for (const SampleMutation &mutation : mutations_) {
		write_raw(output_bytes, mutation.index, mutation.raw_distance);
	}
	if (dense_ready_
			&& dense_brick_cells_ == mutation_brick_cells_
			&& std::abs(dense_voxel_size_ - mutation_voxel_size_) <= 0.0000001
			&& std::abs(dense_narrow_band_ - mutation_narrow_band_) <= 0.0000001
			&& dense_half_extents_.is_equal_approx(mutation_half_extents_)) {
		update_dense_brick(coordinate, false, output_uniform_raw, output);
	}
	result[StringName("changed")] = true;
	result[StringName("changed_samples")] = static_cast<int64_t>(mutations_.size());
	result[StringName("distance_bytes")] = output;
	result[StringName("uniform_raw")] = output_uniform_raw;
	result[StringName("has_changed_sample_bounds")] = has_surface_bounds;
	result[StringName("changed_sample_minimum")] = changed_minimum;
	result[StringName("changed_sample_maximum")] = changed_maximum;
	return result;
}

int SdfNativeKernel::sample_index(int x, int y, int z, int size) const {
	return x + kSampleHalo + size * (y + kSampleHalo + size * (z + kSampleHalo));
}

float SdfNativeKernel::sample(const float *distances, int x, int y, int z, int size) const {
	return distances[sample_index(x, y, z, size)];
}

Vector3 SdfNativeKernel::gradient(const float *distances, int x, int y, int z, int size) const {
	const Vector3 value(
			sample(distances, x + 1, y, z, size) - sample(distances, x - 1, y, z, size),
			sample(distances, x, y + 1, z, size) - sample(distances, x, y - 1, z, size),
			sample(distances, x, y, z + 1, size) - sample(distances, x, y, z - 1, size));
	return value.length_squared() > kMinimumVectorLengthSquared ? value.normalized() : Vector3();
}

int SdfNativeKernel::extended_index(int x, int y, int z, int size) const {
	return x + size * (y + size * z);
}

float SdfNativeKernel::triangle_alignment(int32_t a, int32_t b, int32_t c) const {
	const Vector3 face = (vertices_[b] - vertices_[a]).cross(vertices_[c] - vertices_[a]);
	const Vector3 authored = normals_[a] + normals_[b] + normals_[c];
	const real_t denominator_squared = face.length_squared() * authored.length_squared();
	if (denominator_squared <= static_cast<real_t>(0.000000001)) {
		return 0.0F;
	}
	return static_cast<float>(std::clamp(
			-face.dot(authored) / std::sqrt(denominator_squared),
			static_cast<real_t>(-1.0),
			static_cast<real_t>(1.0)));
}

float SdfNativeKernel::triangle_quality(int32_t a, int32_t b, int32_t c) const {
	const Vector3 first_edge = vertices_[b] - vertices_[a];
	const Vector3 second_edge = vertices_[c] - vertices_[b];
	const Vector3 third_edge = vertices_[a] - vertices_[c];
	const real_t edge_sum = first_edge.length_squared()
			+ second_edge.length_squared() + third_edge.length_squared();
	if (edge_sum <= static_cast<real_t>(0.000000001)) {
		return 0.0F;
	}
	return static_cast<float>(std::clamp(
			static_cast<real_t>(2.0 * std::sqrt(3.0))
					* first_edge.cross(-third_edge).length() / edge_sum,
			static_cast<real_t>(0.0),
			static_cast<real_t>(1.0)));
}

void SdfNativeKernel::append_triangle(int32_t a, int32_t b, int32_t c) {
	const Vector3 face = (vertices_[b] - vertices_[a]).cross(vertices_[c] - vertices_[a]);
	const Vector3 authored = normals_[a] + normals_[b] + normals_[c];
	if (triangle_quality(a, b, c) < kMinimumContourTriangleQuality) {
		return;
	}
	if (face.dot(authored) >= 0.0F) {
		std::swap(b, c);
	}
	indices_.push_back(a);
	indices_.push_back(b);
	indices_.push_back(c);
}

void SdfNativeKernel::append_owned_edge_quad(
		const float *distances,
		int sample_grid_size,
		int extended_size,
		int local_x,
		int local_y,
		int local_z,
		int axis) {
	const Vector3i direction = kAxisDirections[axis];
	const float first_distance = sample(distances, local_x, local_y, local_z, sample_grid_size);
	const float second_distance = sample(
			distances,
			local_x + direction.x,
			local_y + direction.y,
			local_z + direction.z,
			sample_grid_size);
	if ((first_distance < 0.0F) == (second_distance < 0.0F)) {
		return;
	}

	std::array<int32_t, 4> quad = {-1, -1, -1, -1};
	for (int corner = 0; corner < 4; ++corner) {
		const Vector3i offset = kAdjacentCells[axis][corner];
		const int cell_lookup = extended_index(
				local_x + offset.x + 1,
				local_y + offset.y + 1,
				local_z + offset.z + 1,
				extended_size);
		const int lookup = cell_lookup * kCellEdgeSlotCount + kAdjacentEdgeSlots[axis][corner];
		if (lookup < 0 || static_cast<std::size_t>(lookup) >= cell_indices_.size()) {
			return;
		}
		quad[corner] = cell_indices_[lookup];
		if (quad[corner] < 0) {
			return;
		}
	}

	const real_t zero_two_length = (vertices_[quad[0]] - vertices_[quad[2]]).length_squared();
	const real_t one_three_length = (vertices_[quad[1]] - vertices_[quad[3]]).length_squared();
	const real_t tie_epsilon = std::max(
			std::max(zero_two_length, one_three_length), static_cast<real_t>(0.00000001))
			* static_cast<real_t>(0.00001);
	bool use_zero_two = zero_two_length <= one_three_length + tie_epsilon;
	const float zero_two_quality = std::min(
			triangle_quality(quad[0], quad[2], quad[3]),
			triangle_quality(quad[0], quad[1], quad[2]));
	const float one_three_quality = std::min(
			triangle_quality(quad[0], quad[1], quad[3]),
			triangle_quality(quad[1], quad[2], quad[3]));
	if (std::abs(zero_two_quality - one_three_quality) > kTriangulationQualityTieEpsilon) {
		use_zero_two = zero_two_quality > one_three_quality;
	}

	if (first_distance < 0.0F) {
		if (use_zero_two) {
			append_triangle(quad[0], quad[3], quad[2]);
			append_triangle(quad[0], quad[2], quad[1]);
		} else {
			append_triangle(quad[0], quad[3], quad[1]);
			append_triangle(quad[3], quad[2], quad[1]);
		}
	} else if (use_zero_two) {
		append_triangle(quad[0], quad[1], quad[2]);
		append_triangle(quad[0], quad[2], quad[3]);
	} else {
		append_triangle(quad[0], quad[1], quad[3]);
		append_triangle(quad[1], quad[2], quad[3]);
	}
}

void SdfNativeKernel::compact_geometry() {
	if (vertices_.empty() || indices_.empty()) {
		vertices_.clear();
		normals_.clear();
		shell_masks_.clear();
		indices_.clear();
		return;
	}
	remap_.assign(vertices_.size(), -1);
	for (const int32_t source : indices_) {
		remap_[source] = 0;
	}
	int32_t write_index = 0;
	for (std::size_t source = 0; source < vertices_.size(); ++source) {
		if (remap_[source] < 0) {
			continue;
		}
		remap_[source] = write_index;
		if (static_cast<std::size_t>(write_index) != source) {
			vertices_[write_index] = vertices_[source];
			normals_[write_index] = normals_[source];
			shell_masks_[write_index] = shell_masks_[source];
		}
		++write_index;
	}
	for (int32_t &index : indices_) {
		index = remap_[index];
	}
	vertices_.resize(write_index);
	normals_.resize(write_index);
	shell_masks_.resize(write_index);
}

Dictionary SdfNativeKernel::build_chunk_snapshot(const Dictionary &snapshot) {
	const Vector3i chunk_coordinate = snapshot.get(StringName("chunk_coordinate"), Vector3i());
	const int cells = static_cast<int64_t>(snapshot.get(StringName("cells"), 0));
	const float voxel_size = static_cast<double>(snapshot.get(StringName("voxel_size"), 0.0));
	const Vector3 field_origin = snapshot.get(StringName("field_origin"), Vector3());
	const Vector3 field_half_extents = snapshot.get(StringName("field_half_extents"), Vector3());
	const Vector3i chunk_global_cell_origin = snapshot.get(
			StringName("chunk_global_cell_origin"), Vector3i());
	const int sample_grid_size = static_cast<int64_t>(
			snapshot.get(StringName("sample_grid_size"), 0));
	const PackedFloat32Array sample_distances = snapshot.get(
			StringName("sample_distances"), PackedFloat32Array());
	const int64_t expected_samples = static_cast<int64_t>(sample_grid_size) * sample_grid_size * sample_grid_size;
	if (cells <= 0 || cells > 64 || voxel_size <= 0.0F || sample_grid_size != cells + 4
			|| sample_distances.size() < expected_samples) {
		return empty_result(chunk_coordinate);
	}

	const float *distances = sample_distances.ptr();
	const int extended_size = cells + 1;
	const std::size_t cell_slot_count = static_cast<std::size_t>(extended_size) * extended_size * extended_size;
	const std::size_t maximum_vertices = cell_slot_count * kCellEdgeSlotCount;
	const std::size_t maximum_indices = static_cast<std::size_t>(cells) * cells * cells * 18U;
	cell_indices_.assign(cell_slot_count * kCellEdgeSlotCount, -1);
	vertices_.clear();
	normals_.clear();
	shell_masks_.clear();
	indices_.clear();
	vertices_.reserve(maximum_vertices);
	normals_.reserve(maximum_vertices);
	shell_masks_.reserve(maximum_vertices);
	indices_.reserve(maximum_indices);

	std::array<float, 8> corner_distances{};
	std::array<int, kCellEdgeSlotCount> edge_parents{};
	std::array<int, kCellEdgeSlotCount> edge_groups{};
	std::array<int, kCellEdgeSlotCount> group_roots{};
	std::array<int, kCellEdgeSlotCount> group_counts{};
	std::array<Vector3, kCellEdgeSlotCount> group_point_sums{};
	std::array<Vector3, kCellEdgeSlotCount> group_normal_sums{};
	std::array<uint8_t, kCellEdgeSlotCount> group_shell_masks{};
	std::array<int32_t, kCellEdgeSlotCount> group_vertex_indices{};
	for (int local_z = -1; local_z < cells; ++local_z) {
		for (int local_y = -1; local_y < cells; ++local_y) {
			for (int local_x = -1; local_x < cells; ++local_x) {
				int negative_count = 0;
				for (int corner = 0; corner < 8; ++corner) {
					const Vector3i offset = kCornerOffsets[corner];
					const float distance = sample(
							distances,
							local_x + offset.x,
							local_y + offset.y,
							local_z + offset.z,
							sample_grid_size);
					corner_distances[corner] = distance;
					negative_count += distance < 0.0F ? 1 : 0;
				}
				if (negative_count == 0 || negative_count == 8) {
					continue;
				}

				for (int edge = 0; edge < kCellEdgeSlotCount; ++edge) {
					edge_parents[edge] = edge;
				}
				auto component_root = [&edge_parents](int edge) {
					int root = edge;
					while (edge_parents[root] != root) {
						root = edge_parents[root];
					}
					while (edge_parents[edge] != edge) {
						const int parent = edge_parents[edge];
						edge_parents[edge] = root;
						edge = parent;
					}
					return root;
				};
				auto unite_edges = [&edge_parents, &component_root](int first, int second) {
					const int first_root = component_root(first);
					const int second_root = component_root(second);
					if (first_root == second_root) {
						return;
					}
					if (first_root < second_root) {
						edge_parents[second_root] = first_root;
					} else {
						edge_parents[first_root] = second_root;
					}
				};
				for (int face = 0; face < 6; ++face) {
					int first_crossing = -1;
					int second_crossing = -1;
					int crossing_count = 0;
					for (int face_edge = 0; face_edge < 4; ++face_edge) {
						const int edge_index = kFaceEdges[face][face_edge];
						const auto &edge = kEdgeCorners[edge_index];
						if ((corner_distances[edge[0]] < 0.0F)
								== (corner_distances[edge[1]] < 0.0F)) {
							continue;
						}
						if (crossing_count == 0) {
							first_crossing = edge_index;
						} else if (crossing_count == 1) {
							second_crossing = edge_index;
						}
						++crossing_count;
					}
					if (crossing_count == 2) {
						unite_edges(first_crossing, second_crossing);
					} else if (crossing_count == 4) {
						const auto &corners = kFaceCorners[face];
						const auto &edges = kFaceEdges[face];
						const double determinant = static_cast<double>(corner_distances[corners[0]])
								* static_cast<double>(corner_distances[corners[2]])
								- static_cast<double>(corner_distances[corners[1]])
										* static_cast<double>(corner_distances[corners[3]]);
						if (determinant >= 0.0F) {
							unite_edges(edges[0], edges[1]);
							unite_edges(edges[2], edges[3]);
						} else {
							unite_edges(edges[0], edges[3]);
							unite_edges(edges[1], edges[2]);
						}
					}
				}
				edge_groups.fill(-1);
				int group_count = 0;
				const Vector3i local_cell(local_x, local_y, local_z);
				const Vector3i global_cell = chunk_global_cell_origin + local_cell;
				for (int edge_index = 0; edge_index < kCellEdgeSlotCount; ++edge_index) {
					const auto &edge = kEdgeCorners[edge_index];
					const float first_distance = corner_distances[edge[0]];
					const float second_distance = corner_distances[edge[1]];
					if ((first_distance < 0.0F) == (second_distance < 0.0F)) {
						continue;
					}
					const int root = component_root(edge_index);
					int group = -1;
					for (int candidate = 0; candidate < group_count; ++candidate) {
						if (group_roots[candidate] == root) {
							group = candidate;
							break;
						}
					}
					if (group < 0) {
						group = group_count++;
						group_roots[group] = root;
						group_counts[group] = 0;
						group_point_sums[group] = Vector3();
						group_normal_sums[group] = Vector3();
						group_shell_masks[group] = 0U;
					}
					edge_groups[edge_index] = group;
					const float denominator = first_distance - second_distance;
					const float interpolation = std::abs(denominator) > kMinimumEdgeDenominator
							? std::clamp(first_distance / denominator, 0.0F, 1.0F)
							: 0.5F;
					const Vector3i first_corner = kCornerOffsets[edge[0]];
					const Vector3i second_corner = kCornerOffsets[edge[1]];
					const Vector3 first_position = field_origin
							+ to_vector3(global_cell + first_corner) * voxel_size;
					const Vector3 second_position = field_origin
							+ to_vector3(global_cell + second_corner) * voxel_size;
					const Vector3 point = first_position.lerp(second_position, interpolation);
					group_shell_masks[group] |= box_shell_mask(
							point,
							field_half_extents,
							voxel_size * kBoxShellIntersectionToleranceVoxels);
					Vector3 normal = gradient(
							distances,
							local_x + first_corner.x,
							local_y + first_corner.y,
							local_z + first_corner.z,
							sample_grid_size)
							.lerp(
									gradient(
											distances,
											local_x + second_corner.x,
											local_y + second_corner.y,
											local_z + second_corner.z,
											sample_grid_size),
									interpolation);
					normal = normal.length_squared() > kMinimumVectorLengthSquared
							? normal.normalized()
							: Vector3(0.0F, 1.0F, 0.0F);
					group_point_sums[group] += point;
					group_normal_sums[group] += normal;
					++group_counts[group];
				}
				for (int group = 0; group < group_count; ++group) {
					const int count = group_counts[group];
					if (count <= 0) {
						continue;
					}
					Vector3 vertex = group_point_sums[group] / static_cast<real_t>(count);
					vertex = snap_to_box_shell(vertex, field_half_extents, group_shell_masks[group]);
					const Vector3 normal_sum = group_normal_sums[group];
					const Vector3 vertex_normal = normal_sum.length_squared() > kMinimumVectorLengthSquared
							? normal_sum.normalized()
							: Vector3(0.0F, 1.0F, 0.0F);
					group_vertex_indices[group] = static_cast<int32_t>(vertices_.size());
					vertices_.push_back(vertex);
					normals_.push_back(vertex_normal);
					shell_masks_.push_back(group_shell_masks[group]);
				}
				const int cell_lookup = extended_index(
						local_x + 1, local_y + 1, local_z + 1, extended_size)
						* kCellEdgeSlotCount;
				for (int edge = 0; edge < kCellEdgeSlotCount; ++edge) {
					const int group = edge_groups[edge];
					if (group >= 0) {
						cell_indices_[cell_lookup + edge] = group_vertex_indices[group];
					}
				}
			}
		}
	}

	for (int local_z = 0; local_z < cells; ++local_z) {
		for (int local_y = 0; local_y < cells; ++local_y) {
			for (int local_x = 0; local_x < cells; ++local_x) {
				append_owned_edge_quad(
						distances, sample_grid_size, extended_size, local_x, local_y, local_z, 0);
				append_owned_edge_quad(
						distances, sample_grid_size, extended_size, local_x, local_y, local_z, 1);
				append_owned_edge_quad(
						distances, sample_grid_size, extended_size, local_x, local_y, local_z, 2);
			}
		}
	}
	compact_geometry();

	PackedVector3Array packed_vertices;
	PackedVector3Array packed_normals;
	PackedInt32Array packed_indices;
	PackedByteArray packed_shell_masks;
	packed_vertices.resize(static_cast<int64_t>(vertices_.size()));
	packed_normals.resize(static_cast<int64_t>(normals_.size()));
	packed_indices.resize(static_cast<int64_t>(indices_.size()));
	packed_shell_masks.resize(static_cast<int64_t>(shell_masks_.size()));
	Vector3 *vertex_output = packed_vertices.ptrw();
	Vector3 *normal_output = packed_normals.ptrw();
	int32_t *index_output = packed_indices.ptrw();
	uint8_t *shell_mask_output = packed_shell_masks.ptrw();
	for (std::size_t index = 0; index < vertices_.size(); ++index) {
		vertex_output[index] = vertices_[index];
		normal_output[index] = normals_[index];
		shell_mask_output[index] = shell_masks_[index];
	}
	std::copy(indices_.begin(), indices_.end(), index_output);

	Dictionary result;
	result[StringName("chunk_coordinate")] = chunk_coordinate;
	result[StringName("vertices")] = packed_vertices;
	result[StringName("normals")] = packed_normals;
	result[StringName("indices")] = packed_indices;
	result[StringName("shell_masks")] = packed_shell_masks;
	result[StringName("triangle_count")] = static_cast<int64_t>(indices_.size() / 3U);
	result[StringName("empty")] = indices_.empty();
	result[StringName("native_backend")] = true;
	return result;
}

} // namespace godot
