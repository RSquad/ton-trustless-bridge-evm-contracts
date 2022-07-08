//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./types.sol";
import "./UtilsLib.sol";

contract TreeOfCellsAdapter {
        function get_tree_of_cells(bytes calldata boc, BagOfCellsInfo memory info) public view returns (CellData[50] memory cells) {
        uint[50] memory custom_index = get_indexes(boc, info);

        bytes calldata cells_slice = boc[info.data_offset: info.data_offset + info.data_size];
        
        uint idx;

        console.log("Cell count: %d", info.cell_count);
        for (uint i = 0; i < info.cell_count; i++) {
            idx = info.cell_count - 1 - i;
            console.log("Parse cell with idx: '%d'", idx);
            cells[i] = deserialize_cell(idx, cells_slice, custom_index, info.ref_byte_size, info.cell_count);
            // console.log("CELL bits:");
            // console.logBytes(cells[i].bits);
            console.log("CELL refs: %d %d", cells[i].refs[0], cells[i].refs[1]);
            console.log("CELL refs: %d %d", cells[i].refs[2], cells[i].refs[3]);
        }

        return cells;
    }

    function get_indexes(bytes calldata boc, BagOfCellsInfo memory info) public pure returns (uint[50] memory custom_index) {
        require(!info.has_index, "has index logic has not realised");
        
        bytes calldata cells_slice_for_indexes = boc[info.data_offset: info.data_offset + info.data_size];
        
        uint cur = 0;
        for (uint i = 0; i < info.cell_count; i++) {
            CellSerializationInfo memory cellInfo = init_cell_serialization_info(cells_slice_for_indexes, info.ref_byte_size);
            cells_slice_for_indexes = cells_slice_for_indexes[cellInfo.end_offset:];
            cur += cellInfo.end_offset;
            custom_index[i] = cur;
            // console.log("Custom index at %d : %d", i, cur);
        }

        return custom_index;
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
        
        cell = create_data_cell(cell_slice, refs, cell_info);
        
        return cell;
    }

    function get_cell_slice(uint idx, bytes calldata cells_slice, uint[50] memory custom_index) public pure returns(bytes calldata cell_slice) {
        uint offs = idx == 0 ? 0 : custom_index[idx - 1];
        uint offs_end = custom_index[idx];
        return cells_slice[offs: offs_end];
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
}