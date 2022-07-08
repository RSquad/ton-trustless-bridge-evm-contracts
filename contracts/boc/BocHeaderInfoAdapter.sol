//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./UtilsLib.sol";

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

contract BocHeaderInfoAdapter {
    bytes4 public boc_idx = 0x68ff65f3; 
    bytes4 public boc_idx_crc32c = 0xacc3a728; 
    bytes4 public boc_generic = 0xb5ee9c72;

    function parse_serialized_header(bytes calldata boc) public view returns (BagOfCellsInfo memory header) {
        uint sz = boc.length;
        require(!(sz < 4), "Not enough bytes");

        uint ptr = 0;
        header = BagOfCellsInfo(
            bytes4(boc[0:4]), // magic
            0, // root_count
            0, // cell_count
            0, // absent_count
            0, // ref_byte_size
            0,     // offset_byte_size
            false, // has_index
            false, // has_roots
            false, // has_crc32c
            false,  // has_cache_bits
            0, // roots_offset
            0, // index_offset
            0, // data_offset
            0, // data_size
            0 // total_size
        );

        require(!(header.magic != boc_generic && 
            header.magic != boc_idx && 
            header.magic != boc_idx_crc32c), "wrong boc type");

        uint8 flags_byte = uint8(boc[4]);

        if (header.magic == boc_generic) {
            header.has_index = (flags_byte >> 7) % 2 == 1;
            header.has_crc32c = (flags_byte >> 6) % 2 == 1;
            header.has_cache_bits = (flags_byte >> 5) % 2 == 1;
        } else {
            header.has_index = true;
            header.has_crc32c = header.magic == boc_idx_crc32c;
        }
        
        require(!(header.has_cache_bits && !header.has_index));
        
        header.ref_byte_size = flags_byte & 7;
        require(!(header.ref_byte_size > 4 || header.ref_byte_size < 1));
        require(!(sz < 6));
        
        header.offset_byte_size = uint8(boc[5]);
        require(!(header.offset_byte_size > 8 || header.offset_byte_size < 1));
        header.roots_offset = 6 + 3 * header.ref_byte_size + header.offset_byte_size;
        ptr += 6;
        sz -= 6;
        require(!(sz < header.ref_byte_size));
        
        header.cell_count = UtilsLib.read_int(boc[ptr:], header.ref_byte_size);
        require(!(header.cell_count <= 0));
        require(!(sz < 2 * header.ref_byte_size));
        header.root_count = UtilsLib.read_int(boc[ptr + header.ref_byte_size:], header.ref_byte_size);
        require(!(header.root_count <= 0));
        header.index_offset = header.roots_offset;
        if (header.magic == boc_generic) {
            header.index_offset += header.root_count * header.ref_byte_size;
            header.has_roots = true;
        } else {
            require(!(header.root_count != 1));
        }
        header.data_offset = header.index_offset;
        if(header.has_index) {
            header.data_offset += header.cell_count * header.offset_byte_size;
        }
        require(!(sz < 3 * header.ref_byte_size));
        header.absent_count = UtilsLib.read_int(boc[ptr + 2 * header.ref_byte_size:], header.ref_byte_size);
        require(!(header.absent_count < 0 || header.absent_count > header.cell_count));
        require(!(sz < 3 * header.ref_byte_size + header.offset_byte_size));
        header.data_size = UtilsLib.read_int(boc[ptr + 3 * header.ref_byte_size:], header.offset_byte_size);
        require(!(header.data_size > header.cell_count << 10));
        
        header.total_size = header.data_offset + header.data_size + (header.has_crc32c ? 4 : 0);
        return header;
    }
}