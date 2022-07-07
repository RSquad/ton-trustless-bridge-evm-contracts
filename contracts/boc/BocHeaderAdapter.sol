//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";

struct BagOfCellsInfo {
    bytes4 magic;
    uint root_count;
    uint cell_count;
    uint absent_count;
    uint ref_byte_size;
    uint offset_byte_size;
    // bool valid;
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

struct BagOfCells {
    uint cell_count;    
}


struct RootInfo {
    uint idx;
}

contract BocHeaderAdapter {
    bytes4 boc_idx = 0x68ff65f3; 
    bytes4 boc_idx_crc32c = 0xacc3a728; 
    bytes4 boc_generic = 0xb5ee9c72;

    function stdBocDeserialize(bytes calldata boc) public {
        require(boc.length == 0, "BOC is empty");

        // BagOfCells boc;
        // auto res = boc.deserialize(data, 1);
        deserialize(boc);
        // if (res.is_error()) {
        //     return res.move_as_error();
        // }
        // if (boc.get_root_count() != 1) {
        //     return td::Status::Error("bag of cells is expected to have exactly one root");
        // }
        // auto root = boc.get_root_cell();
        // if (root.is_null()) {
        //     return td::Status::Error("bag of cells has null root cell (?)");
        // }
        // if (root->get_level() != 0) {
        //     return td::Status::Error("bag of cells has a root with non-zero level");
        // }
        // return std::move(root);
    }

    function deserialize(bytes calldata boc) public {
        BagOfCellsInfo memory info = parse_serialized_header(boc);
        
        if (info.has_crc32c) {
            // TODO
        }

        BagOfCells memory parsedBoc = BagOfCells(
            info.cell_count // cell_count
        );

        bytes calldata roots_ptr = boc[info.roots_offset:];

        require(info.root_count == 1, "Should have only 1 root");
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");
        uint rootIdx = info.cell_count - read_int(boc[info.roots_offset:], info.ref_byte_size) - 1;
        require(!info.has_index, "has index logic has not realised");

        bytes calldata cells_slice = boc[info.data_offset: info.data_offset + info.data_size];

        for (uint i = 0; i < parsedBoc.cell_count; i++) {
            uint idx = parsedBoc.cell_count - 1 - i;
            console.log("Parse cell with idx: '%d'", idx);
            deserialize_cell(idx, cells_slice);
        }
    }

    // function get_idx_entry(uint index) public pure returns (uint value) {
    //     value = get_idx_entry_raw(index);
    //     return value;
    // }

    // function get_idx_entry_raw(uint index, BagOfCellsInfo calldata info, BagOfCells calldata parsedBoc) public pure returns (uint value) {
    //     if (index < 0) {
    //         return 0;
    //     }
    //     if (!info.has_index) {
    //         return parsedBoc.custom_index.at(index);
    //     } else if (index < info.cell_count && parsedBoc.index_ptr) {
    //         return info.read_offset(parsedBoc.index_ptr + index * info.offset_byte_size);
    //     } else {
    //         // throw ?
    //         return 0;
    //     }
    // }

    function deserialize_cell(uint idx, bytes calldata cells_slice) public view {
        uint offs = get_idx_entry(idx - 1);
        uint offs_end = get_idx_entry(idx);
        bytes calldata cell_slice = cells_slice[offs: offs_end];
    }

    function parse_serialized_header(bytes calldata boc) public view returns (BagOfCellsInfo memory header) {
        // TODO: valid = false
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

        require(!(header.magic != boc_generic), "wrong boc type");

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
        
        header.cell_count = read_int(boc[ptr:], header.ref_byte_size);
        require(!(header.cell_count <= 0));
        require(!(sz < 2 * header.ref_byte_size));
        header.root_count = read_int(boc[ptr + header.ref_byte_size:], header.ref_byte_size);
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
        header.absent_count = read_int(boc[ptr + 2 * header.ref_byte_size:], header.ref_byte_size);
        require(!(header.absent_count < 0 || header.absent_count > header.cell_count));
        require(!(sz < 3 * header.ref_byte_size + header.offset_byte_size));
        header.data_size = read_int(boc[ptr + 3 * header.ref_byte_size:], header.offset_byte_size);
        require(!(header.data_size > header.cell_count << 10));
        // TODO: check max sizes
        // valid true
        header.total_size = header.data_offset + header.data_size + (header.has_crc32c ? 4 : 0);
        return header;
    }

    function read_int(bytes calldata data, uint size) public pure returns(uint value) {
        uint res = 0;
        uint cursor = 0;
        while (size > 0) {
            res = (res << 8) + uint8(data[cursor]);
            cursor++;
            --size;
        }
        return res;
    }
}