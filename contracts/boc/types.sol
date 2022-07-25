//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

    struct BagOfCellsInfo {
        bytes4 magic;
        uint root_count;
        uint cell_count;
        uint absent_count;
        uint ref_byte_size;
        uint offset_byte_size;
        bool has_index;
        bool has_roots;
        bool has_crc32c;
        bool has_cache_bits;
        uint roots_offset;
        uint index_offset;
        uint data_offset;
        uint data_size;
        uint total_size;
    }

    struct CellData {
        bool special;
        bytes bits;
        uint[4] refs;
        uint cursor;
        uint8 cursorRef;
    }

    struct CellSerializationInfo {
        bool special;
        uint32 level_mask;
        bool with_hashes;
        uint hashes_offset;
        uint depth_offset;
        uint data_offset;
        uint data_len;
        bool data_with_bits;

        uint refs_offset;
        uint refs_cnt;
        uint end_offset;
    }