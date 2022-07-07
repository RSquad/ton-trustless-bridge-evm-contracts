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

contract BocHeaderAdapter {
    bytes4 public boc_idx = 0x68ff65f3; 
    bytes4 public boc_idx_crc32c = 0xacc3a728; 
    bytes4 public boc_generic = 0xb5ee9c72;

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

        /////////////
        bytes calldata cells_slice_for_indexes = boc[info.data_offset: info.data_offset + info.data_size];
        uint[50] memory custom_index;
        uint cur = 0;
        for (uint i = 0; i < info.cell_count; i++) {
            CellSerializationInfo memory cellInfo = init_cell_serialization_info(cells_slice_for_indexes, info.ref_byte_size);
            cells_slice_for_indexes = cells_slice_for_indexes[cellInfo.end_offset:];
            cur += cellInfo.end_offset;
            custom_index[i] = cur;
            console.log("Custom index at %d : %d", i, cur);
        }
        ///////////


        bytes calldata cells_slice = boc[info.data_offset: info.data_offset + info.data_size];

        for (uint i = 0; i < parsedBoc.cell_count; i++) {
            uint idx = parsedBoc.cell_count - 1 - i;
            console.log("Parse cell with idx: '%d'", idx);
            deserialize_cell(idx, cells_slice, custom_index, info.ref_byte_size, info.cell_count);
        }
    }

    function init_cell_serialization_info(bytes calldata data, uint ref_byte_size) public  pure returns (CellSerializationInfo memory cellInfo) {
        require(!(data.length < 2), "Not enough bytes");
        uint8 d1 = uint8(data[0]);
        uint8 d2 = uint8(data[1]);
        // cellInfo = init_cell_serialization_info2(uint8(data[0]), uint8(data[1]), ref_byte_size);
        cellInfo.refs_cnt = d1 & 7;
        cellInfo.level_mask = d1 >> 5;
        cellInfo.special = (d1 & 8) != 0;

        cellInfo.with_hashes = (d1 & 16) != 0;

        if (cellInfo.refs_cnt > 4) {
            require(!(cellInfo.refs_cnt != 7 || !cellInfo.with_hashes), "Invalid first byte");
            cellInfo.refs_cnt = 0;
            require(false, "TODO: absent cells");
        }

        cellInfo.hashes_offset = 2;
        uint n = count_setbits(cellInfo.level_mask) + 1;
        cellInfo.depth_offset = cellInfo.hashes_offset + (cellInfo.with_hashes ? n * 32 : 0);
        cellInfo.data_offset = cellInfo.depth_offset + (cellInfo.with_hashes ? n * 2 : 0);
        cellInfo.data_len = (d2 >> 1) + (d2 & 1);
        cellInfo.data_with_bits = (d2 & 1) != 0;
        cellInfo.refs_offset = cellInfo.data_offset + cellInfo.data_len;
        cellInfo.end_offset = cellInfo.refs_offset + cellInfo.refs_cnt * ref_byte_size;
        // return cellInfo;
        require(!(data.length < cellInfo.end_offset), "Not enough bytes");
        return cellInfo;
    }

    // instead of get_hashes_count()
    function count_setbits(uint32 n) public pure returns (uint cnt) {
        cnt = 0;
        while (n > 0) {
            cnt += n & 1;
            n = n >> 1;
        }
        return cnt;
    }


    function get_idx_entry_raw(uint index, uint[50] memory custom_index) public pure returns(uint value) {
          if (index < 0) {
                return 0;
            }
            // if (!has_index) {
            return custom_index[index];
            // } else if (index < info.cell_count && index_ptr) {
            //     return info.read_offset(index_ptr + index * info.offset_byte_size);
            // } else {
            //     // throw ?
            //     return 0;
            // }
    }

    function get_idx_entry(uint index, uint[50] memory custom_index) public pure returns(uint raw) {
        raw = get_idx_entry_raw(index, custom_index);
        // if (info.has_cache_bits) {
        //     raw /= 2;
        // }
        return raw;
    }

    function get_cell_slice(uint idx, bytes calldata cells_slice, uint[50] memory custom_index) public pure returns(bytes calldata cell_slice) {
        // uint offs = get_idx_entry(idx - 1, custom_index);
        // uint offs_end = get_idx_entry(idx, custom_index);
        
        uint offs = idx == 0 ? 0 : custom_index[idx - 1];
        uint offs_end = custom_index[idx];
        return cells_slice[offs: offs_end];
    }

    function deserialize_cell(uint idx, bytes calldata cells_slice, uint[50] memory custom_index, uint ref_byte_size, uint cell_count) public view {
        // bytes calldata cell_slice = get_cell_slice(idx, cells_slice, custom_index);
        // uint[4] memory refs;
        // CellSerializationInfo memory cell_info = init_cell_serialization_info(cell_slice, ref_byte_size);
        // require(!(cell_info.end_offset != cell_slice.length), "unused space in cell serialization");
        // auto refs = td::MutableSpan<td::Ref<Cell>>(refs_buf).substr(0, cell_info.refs_cnt);
        // for (uint k = 0; k < cell_info.refs_cnt; k++) {
        //     uint ref_idx = read_int(cell_slice[cell_info.refs_offset + k * ref_byte_size:], ref_byte_size);
        //     console.log("Read ref idx: %s", ref_idx);
        //     require(!(ref_idx <= idx), "bag-of-cells error: reference # of cell # is to cell # with smaller index");
        //     require(!(ref_idx >= cell_count), "refIndex is bigger then cell count");
        //     refs[k] = cell_count - ref_idx - 1;
        // }
        // return create_data_cell(cell_slice, refs);
    }

    function create_data_cell(bytes calldata cell_slice, uint[4] memory refs, CellSerializationInfo calldata cell_info) public {
        uint bits = get_bits(cell_slice, cell_info);

    }

    function get_bits(bytes calldata cell, CellSerializationInfo calldata cell_info) public pure returns (uint){
        if(cell_info.data_with_bits) {
            require((cell_info.data_len !=0), "no data in cell");
            uint32 last = uint8(cell[cell_info.data_offset + cell_info.data_len - 1]);
            // require(!(!(last & 0x7f)), "overlong encoding");
            return ((cell_info.data_len - 1) * 8 + 7 - count_trailing_zeroes_non_zero32(last));
        } else {
            return cell_info.data_len * 8;
        }
    }

    function count_trailing_zeroes_non_zero32(uint32 n) public pure returns (uint) {
        uint bits = 0;
        uint x = n;

        if (x > 0) {
            while((x & 1) == 0) {
                ++bits;
                x >>= 1;
            }
        }

        return bits;
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