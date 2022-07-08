//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./BocHeaderInfoAdapter.sol";
import "./UtilsLib.sol";

struct BagOfCells {
    uint cell_count;    
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

struct CellData {
    bytes bits;
    uint[4] refs;
}

struct RootInfo {
    uint idx;
    CellData root;
}

contract BocHeaderAdapter is BocHeaderInfoAdapter {
    function stdBocDeserialize(bytes calldata boc) public view {
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

    function deserialize(bytes calldata boc) public view {
        BagOfCellsInfo memory info = parse_serialized_header(boc);
        
        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[50] memory cell_should_cache;
        // if (info.has_cache_bits) {
        //     cell_should_cache.resize(cell_count, 0);
        // }
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        // uint rootIdx = info.cell_count - UtilsLib.read_int(boc[info.roots_offset:], info.ref_byte_size) - 1;
        // console.log("Root idx: %d",rootIdx);
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
        CellData[50] memory cells;
        uint idx;

        console.log("Cell count: %d", info.cell_count);
        for (uint i = 0; i < info.cell_count; i++) {
            idx = info.cell_count - 1 - i;
            console.log("Parse cell with idx: '%d'", idx);
            cells[i] = deserialize_cell(idx, cells_slice, custom_index, info.ref_byte_size, info.cell_count);
            console.log("CELL bits:");
            console.logBytes(cells[i].bits);
            console.log("CELL refs: %d %d", cells[i].refs[0], cells[i].refs[1]);
            console.log("CELL refs: %d %d", cells[i].refs[2], cells[i].refs[3]);
        }

        
        uint data;
        data = read_int_memory(cells[5].bits, 1, 0) >> 4;
        console.log("prefix: %d", data);
        // addressHash
        data = read_int_memory(cells[5].bits, 32, 1) >> 4; // взять 4 бита из 0-го байта и дописать в начало
        console.log("addressHash: %d", data);
        // lt
        data = read_int_memory(cells[5].bits, 10, 31) << 256 - 64 + 4 >> 256 - 64 + 8;
        console.log("lt: %d", data);

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

    function deserialize_cell(uint idx, bytes calldata cells_slice, uint[50] memory custom_index, uint ref_byte_size, uint cell_count) public view returns (CellData memory cell) {
        console.log("Start deserialize");
        bytes calldata cell_slice = get_cell_slice(idx, cells_slice, custom_index);
        uint[4] memory refs;
        for(uint i = 0; i < 4; i++) {
            refs[i] = 255;
        }
        CellSerializationInfo memory cell_info = init_cell_serialization_info(cell_slice, ref_byte_size);
        console.log("got cell info");
        require(!(cell_info.end_offset != cell_slice.length), "unused space in cell serialization");
        // auto refs = td::MutableSpan<td::Ref<Cell>>(refs_buf).substr(0, cell_info.refs_cnt);
        for (uint k = 0; k < cell_info.refs_cnt; k++) {
            uint ref_idx = UtilsLib.read_int(cell_slice[cell_info.refs_offset + k * ref_byte_size:], ref_byte_size);
            console.log("Read ref idx: %s", ref_idx);
            require(!(ref_idx <= idx), "bag-of-cells error: reference # of cell # is to cell # with smaller index");
            require(!(ref_idx >= cell_count), "refIndex is bigger then cell count");
            refs[k] = cell_count - ref_idx - 1;
        }
        console.log("before call create_data_cell");
        cell = create_data_cell(cell_slice, refs, cell_info);
        console.log("after call create_data_cell");
        return cell;
    }

    function create_data_cell(bytes calldata cell_slice, uint[4] memory refs, CellSerializationInfo memory cell_info) public view returns (CellData memory cell) {
        uint bits = get_bits(cell_slice, cell_info);
        console.logBytes(cell_slice);
        console.log("data_offset: %d, bits: %d", cell_info.data_offset, bits);
        console.log("cell slice length (bytes): %d", cell_slice.length);
        // bytes calldata bits_slice = cell_slice[cell_info.data_offset: cell_info.data_offset + bits];
        bytes calldata bits_slice = cell_slice[cell_info.data_offset:];
        cell.bits = bits_slice;
        cell.refs = refs;
        return cell;
    }

    function get_bits(bytes calldata cell, CellSerializationInfo memory cell_info) public pure returns (uint){
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

    

    

    function read_int_memory(bytes memory data, uint size, uint start) public pure returns(uint value) {
        uint res = 0;
        uint cursor = 0;
        while (size > 0) {
            res = (res << 8) + uint8(data[start + cursor]);
            cursor++;
            --size;
        }
        return res;
    }
}