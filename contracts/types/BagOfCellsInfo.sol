//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct BagOfCellsInfo {
    bytes4 magic;
    uint256 root_count;
    uint256 cell_count;
    uint256 absent_count;
    uint256 ref_byte_size;
    uint256 offset_byte_size;
    bool has_index;
    bool has_roots;
    bool has_crc32c;
    bool has_cache_bits;
    uint256 roots_offset;
    uint256 index_offset;
    uint256 data_offset;
    uint256 data_size;
    uint256 total_size;
}