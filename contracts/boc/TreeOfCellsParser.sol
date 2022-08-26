//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/bag-of-cells-info.sol";
import "../types/cell-data.sol";
import "../types/CellSerializationInfo.sol";
import "./BitReader.sol";

// TODO: check has_index == true

contract TreeOfCellsParser {
    function get_tree_of_cells(bytes calldata boc, BagOfCellsInfo memory info)
        public
        pure
        returns (CellData[100] memory cells)
    {
        uint256[100] memory custom_index = get_indexes(boc, info);

        bytes calldata cells_slice = boc[info.data_offset:info.data_offset +
            info.data_size];

        uint256 idx;
        for (uint256 i = 0; i < info.cell_count; i++) {
            idx = info.cell_count - 1 - i;
            cells[i] = deserialize_cell(
                idx,
                cells_slice,
                custom_index,
                info.ref_byte_size,
                info.cell_count
            );
            cells[i].cursor += info.data_offset * 8;

            // bytes calldata cell_slice = get_cell_slice(
            //     idx,
            //     cells_slice,
            //     custom_index
            // );
            // CellSerializationInfo
            //     memory cell_info = init_cell_serialization_info(
            //         cell_slice,
            //         info.ref_byte_size
            //     );

            // cells[i].cellType = OrdinaryCell;

            // if (cells[i].special) {
            //     cells[i].cellType = readUint8(cells, i, 8);
            //     cells[i].cursor -= 8;
            // }

            // calcHashForRefs(cell_info, cells, i, cell_slice);
        }
        return cells;
    }

    function get_indexes(bytes calldata boc, BagOfCellsInfo memory info)
        public
        pure
        returns (uint256[100] memory custom_index)
    {
        require(!info.has_index, "has index logic has not realised");

        bytes calldata cells_slice_for_indexes = boc[info.data_offset:info
            .data_offset + info.data_size];

        uint256 cur = 0;
        for (uint256 i = 0; i < info.cell_count; i++) {
            CellSerializationInfo
                memory cellInfo = init_cell_serialization_info(
                    cells_slice_for_indexes,
                    info.ref_byte_size
                );
            cells_slice_for_indexes = cells_slice_for_indexes[cellInfo
                .end_offset:];
            cur += cellInfo.end_offset;
            custom_index[i] = cur;
        }

        return custom_index;
    }

    function init_cell_serialization_info(
        bytes calldata data,
        uint256 ref_byte_size
    ) public pure returns (CellSerializationInfo memory cellInfo) {
        require(!(data.length < 2), "Not enough bytes");
        uint8 d1 = uint8(data[0]);
        uint8 d2 = uint8(data[1]);

        cellInfo.refs_cnt = d1 & 7;
        cellInfo.level_mask = d1 >> 5;
        cellInfo.special = (d1 & 8) != 0;

        cellInfo.with_hashes = (d1 & 16) != 0;

        if (cellInfo.refs_cnt > 4) {
            require(
                !(cellInfo.refs_cnt != 7 || !cellInfo.with_hashes),
                "Invalid first byte"
            );
            cellInfo.refs_cnt = 0;
            require(false, "TODO: absent cells");
        }

        cellInfo.hashes_offset = 2;
        uint256 n = count_setbits(cellInfo.level_mask) + 1;
        cellInfo.depth_offset =
            cellInfo.hashes_offset +
            (cellInfo.with_hashes ? n * 32 : 0);
        cellInfo.data_offset =
            cellInfo.depth_offset +
            (cellInfo.with_hashes ? n * 2 : 0);
        cellInfo.data_len = (d2 >> 1) + (d2 & 1);
        cellInfo.data_with_bits = (d2 & 1) != 0;
        cellInfo.refs_offset = cellInfo.data_offset + cellInfo.data_len;
        cellInfo.end_offset =
            cellInfo.refs_offset +
            cellInfo.refs_cnt *
            ref_byte_size;

        require(!(data.length < cellInfo.end_offset), "Not enough bytes");
        return cellInfo;
    }

    // instead of get_hashes_count()
    function count_setbits(uint32 n) public pure returns (uint256 cnt) {
        cnt = 0;
        while (n > 0) {
            cnt += n & 1;
            n = n >> 1;
        }
        return cnt;
    }

    function deserialize_cell(
        uint256 idx,
        bytes calldata cells_slice,
        uint256[100] memory custom_index,
        uint256 ref_byte_size,
        uint256 cell_count
    ) public pure returns (CellData memory cell) {
        bytes calldata cell_slice = get_cell_slice(
            idx,
            cells_slice,
            custom_index
        );

        uint256[4] memory refs;
        for (uint256 i = 0; i < 4; i++) {
            refs[i] = 255;
        }
        CellSerializationInfo memory cell_info = init_cell_serialization_info(
            cell_slice,
            ref_byte_size
        );
        require(
            !(cell_info.end_offset != cell_slice.length),
            "unused space in cell"
        );

        for (uint256 k = 0; k < cell_info.refs_cnt; k++) {
            uint256 ref_idx = BitReader.readInt(
                cell_slice[cell_info.refs_offset + k * ref_byte_size:],
                ref_byte_size
            );
            require(!(ref_idx <= idx), "bag-of-cells error");
            require(!(ref_idx >= cell_count), "refIndex is bigger cell count");
            refs[k] = cell_count - ref_idx - 1;
        }

        cell = create_data_cell(refs, cell_info);
        cell.cursor = (cell_info.data_offset + (idx == 0 ? 0 : custom_index[idx - 1])) * 8;

        // cell.level_mask = cell_info.level_mask;
        return cell;
    }

    function get_cell_slice(
        uint256 idx,
        bytes calldata cells_slice,
        uint256[100] memory custom_index
    ) public pure returns (bytes calldata cell_slice) {
        uint256 offs = idx == 0 ? 0 : custom_index[idx - 1];
        uint256 offs_end = custom_index[idx];
        return cells_slice[offs:offs_end];
    }

    function create_data_cell(
        uint256[4] memory refs,
        CellSerializationInfo memory cell_info
    ) public pure returns (CellData memory cell) {
        cell.refs = refs;
        
        cell.special = cell_info.special;
        cell.cursorRef = 0;
        return cell;
    }
}
