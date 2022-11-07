//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct CellSerializationInfo {
    uint8 d1;
    uint8 d2;
    bool special;
    uint32 level_mask;
    bool with_hashes;
    uint256 hashes_offset;
    uint256 depth_offset;
    uint256 data_offset;
    uint256 data_len;
    bool data_with_bits;
    uint256 refs_offset;
    uint256 refs_cnt;
    uint256 end_offset;
}
