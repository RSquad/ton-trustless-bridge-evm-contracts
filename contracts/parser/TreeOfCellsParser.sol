//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BagOfCellsInfo.sol";
import "../types/CellData.sol";
import "../types/CellSerializationInfo.sol";
import "../types/TransactionTypes.sol";
import "../parser/BitReader.sol";

interface ITreeOfCellsParser {
    function parseSerializedHeader(bytes calldata boc)
        external
        pure
        returns (BagOfCellsInfo memory header);

    function get_tree_of_cells(bytes calldata boc, BagOfCellsInfo memory info)
        external
        view
        returns (CellData[100] memory cells);
}

contract TreeOfCellsParser is BitReader, ITreeOfCellsParser {
    bytes4 public constant BOC_IDX = 0x68ff65f3;
    bytes4 public constant BOC_IDX_CRC32C = 0xacc3a728;
    bytes4 public constant BOC_GENERIC = 0xb5ee9c72;

    receive() external payable {} // to support receiving ETH by default
    fallback() external payable {}

    function readInt(bytes calldata data, uint256 size)
        public
        pure
        returns (uint256 value)
    {
        uint256 res = 0;
        uint256 cursor = 0;
        while (size > 0) {
            res = (res << 8) + uint8(data[cursor]);
            cursor++;
            --size;
        }
        return res;
    }

    function parseSerializedHeader(bytes calldata boc)
        external
        pure
        returns (BagOfCellsInfo memory header)
    {
        uint256 sz = boc.length;
        require(!(sz < 4), "Not enough bytes");

        uint256 ptr = 0;
        header = BagOfCellsInfo(
            bytes4(boc[0:4]), // magic
            0, // root_count
            0, // cell_count
            0, // absent_count
            0, // ref_byte_size
            0, // offset_byte_size
            false, // has_index
            false, // has_roots
            false, // has_crc32c
            false, // has_cache_bits
            0, // roots_offset
            0, // index_offset
            0, // data_offset
            0, // data_size
            0, // total_size
            0 // rootIdx
        );

        require(
            !(header.magic != BOC_GENERIC &&
                header.magic != BOC_IDX &&
                header.magic != BOC_IDX_CRC32C),
            "wrong boc type"
        );

        uint8 flags_byte = uint8(boc[4]);

        if (header.magic == BOC_GENERIC) {
            header.has_index = (flags_byte >> 7) % 2 == 1;
            header.has_crc32c = (flags_byte >> 6) % 2 == 1;
            header.has_cache_bits = (flags_byte >> 5) % 2 == 1;
        } else {
            header.has_index = true;
            header.has_crc32c = header.magic == BOC_IDX_CRC32C;
        }

        require(
            !(header.has_cache_bits && !header.has_index),
            "bag-of-cells: invalid header"
        );

        header.ref_byte_size = flags_byte & 7;
        require(
            !(header.ref_byte_size > 4 || header.ref_byte_size < 1),
            "bag-of-cells: invalid header"
        );
        require(!(sz < 6), "bag-of-cells: invalid header");

        header.offset_byte_size = uint8(boc[5]);
        require(
            !(header.offset_byte_size > 8 || header.offset_byte_size < 1),
            "bag-of-cells: invalid header"
        );
        header.roots_offset =
            6 +
            3 *
            header.ref_byte_size +
            header.offset_byte_size;
        ptr += 6;
        sz -= 6;
        require(!(sz < header.ref_byte_size), "bag-of-cells: invalid header");

        header.cell_count = readInt(boc[ptr:], header.ref_byte_size);
        require(!(header.cell_count <= 0), "bag-of-cells: invalid header");
        require(
            !(sz < 2 * header.ref_byte_size),
            "bag-of-cells: invalid header"
        );
        header.root_count = readInt(
            boc[ptr + header.ref_byte_size:],
            header.ref_byte_size
        );
        require(!(header.root_count <= 0), "bag-of-cells: invalid header");
        header.index_offset = header.roots_offset;
        if (header.magic == BOC_GENERIC) {
            header.index_offset += header.root_count * header.ref_byte_size;
            header.has_roots = true;
        } else {
            require(!(header.root_count != 1), "bag-of-cells: invalid header");
        }
        header.data_offset = header.index_offset;
        if (header.has_index) {
            header.data_offset += header.cell_count * header.offset_byte_size;
        }
        require(
            !(sz < 3 * header.ref_byte_size),
            "bag-of-cells: invalid header"
        );
        header.absent_count = readInt(
            boc[ptr + 2 * header.ref_byte_size:],
            header.ref_byte_size
        );
        require(
            !(header.absent_count < 0 ||
                header.absent_count > header.cell_count),
            "bag-of-cells: invalid header"
        );
        require(
            !(sz < 3 * header.ref_byte_size + header.offset_byte_size),
            "bag-of-cells: invalid header"
        );
        header.data_size = readInt(
            boc[ptr + 3 * header.ref_byte_size:],
            header.offset_byte_size
        );
        require(
            !(header.data_size > header.cell_count << 32),
            "bag-of-cells: invalid header"
        );

        header.total_size =
            header.data_offset +
            header.data_size +
            (header.has_crc32c ? 4 : 0);

        header.rootIdx =
            header.cell_count -
            readInt(boc[header.roots_offset:], header.ref_byte_size) -
            1;

        return header;
    }

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
        }
        calcHashesForToc(boc, info, cells);
        return cells;
    }

    function get_indexes(bytes calldata boc, BagOfCellsInfo memory info)
        public
        pure
        returns (uint256[100] memory custom_index)
    {
        // require(!info.has_index, "has index logic has not realised");

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
        cellInfo.d1 = d1;
        cellInfo.d2 = d2;
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
    function count_setbits(uint32 n) public pure returns (uint256) {
        uint256 cnt = 0;
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
            uint256 ref_idx = readInt(
                cell_slice[cell_info.refs_offset + k * ref_byte_size:],
                ref_byte_size
            );
            require(!(ref_idx <= idx), "bag-of-cells error");
            require(!(ref_idx >= cell_count), "refIndex is bigger cell count");
            refs[k] = cell_count - ref_idx - 1;
        }

        cell = create_data_cell(refs, cell_info);
        cell.cursor =
            (cell_info.data_offset + (idx == 0 ? 0 : custom_index[idx - 1])) *
            8;

        cell.level_mask = cell_info.level_mask;
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

    uint8 public constant OrdinaryCell = 255;
    uint8 public constant PrunnedBranchCell = 1;
    uint8 public constant LibraryCell = 2;
    uint8 public constant MerkleProofCell = 3;
    uint8 public constant MerkleUpdateCell = 4;

    function calcHashesForToc(
        bytes calldata boc,
        BagOfCellsInfo memory info,
        CellData[100] memory cells
    ) public pure {
        uint256 idx;
        bytes calldata cells_slice = boc[info.data_offset:info.data_offset +
            info.data_size];
        uint256[100] memory custom_index = get_indexes(boc, info);

        for (uint256 i = 0; i < info.cell_count; i++) {
            idx = info.cell_count - 1 - i;
            bytes calldata cell_slice = get_cell_slice(
                idx,
                cells_slice,
                custom_index
            );
            
            CellSerializationInfo
                memory cell_info = init_cell_serialization_info(
                    cell_slice,
                    info.ref_byte_size
                );

            cells[i].cellType = OrdinaryCell;

            if (cells[i].special) {
                cells[i].cellType = readUint8(boc, cells, i, 8);
                cells[i].cursor -= 8;
            }

            calcHashForRefs(boc, cell_info, cells, i, cell_slice);
        }
    }

    function getHashesCount(uint32 mask) public pure returns (uint8) {
        return getHashesCountFromMask(mask & 7);
    }

    function getHashesCountFromMask(uint32 mask) public pure returns (uint8) {
        uint8 n = 0;
        uint32 maskCopy = mask;
        for (uint8 i = 0; i < 3; i++) {
            n += uint8(maskCopy & 1);
            maskCopy = maskCopy >> 1;
        }
        return n + 1;
    }

    function getLevelFromMask(uint32 mask) public pure returns (uint8) {
        uint32 maskCopy = mask;
        for (uint8 i = 0; i <= 3; i++) {
            if (maskCopy == 0) {
                return i;
            }
            maskCopy = maskCopy >> 1;
        }
        return 3;
    }

    function getLevel(uint32 mask) public pure returns (uint8) {
        return getLevelFromMask(mask & 7);
    }

    function isLevelSignificant(uint8 level, uint32 mask)
        public
        pure
        returns (bool)
    {
        return (level == 0) || ((mask >> (level - 1)) % 2 != 0);
    }

    function getDepth(
        bytes calldata data,
        uint8 level,
        // uint32 mask,
        // uint256 cellType,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (uint16) {
        uint8 hash_i = getHashesCountFromMask(
            applyLevelMask(level, cells[cellIdx].level_mask)
        ) - 1;

        if (cells[cellIdx].cellType == PrunnedBranchCell) {
            uint8 this_hash_i = getHashesCount(cells[cellIdx].level_mask) - 1;
            if (hash_i != this_hash_i) {
                
                uint256 cursor = 16 +
                    uint256(this_hash_i) *
                    32 *
                    8 +
                    uint256(hash_i) *
                    2 *
                    8;
                cells[cellIdx].cursor += cursor;
                
                uint16 childDepth = readUint16(data, cells, cellIdx, 16);
                
                cells[cellIdx].cursor -= cursor + 16;
                
                return childDepth;
            }
            hash_i = 0;
        }
        
        return cells[cellIdx].depth[hash_i];
    }

    function applyLevelMask(uint8 level, uint32 levelMask)
        public
        pure
        returns (uint32)
    {
        return uint32(levelMask & ((1 << level) - 1));
    }

    function calcHashForRefs(
        bytes calldata data,
        CellSerializationInfo memory cell_info,
        CellData[100] memory cells,
        uint256 i,
        bytes calldata cell_slice
    ) public pure {
        if (cells[i].cellType == PrunnedBranchCell) {
            cells[i].level_mask = uint8(cell_slice[3]);
            cell_info.level_mask = uint8(cell_slice[3]);
        }

        uint8 hash_i_offset = getHashesCount(cell_info.level_mask) -
            (
                cells[i].cellType == PrunnedBranchCell
                    ? 1
                    : getHashesCount(cell_info.level_mask)
            );
        uint8 hash_i = 0;

        


        uint8 level = getLevel(cell_info.level_mask);

        for (uint8 level_i = 0; level_i <= level; level_i++) {
            if (!isLevelSignificant(level_i, cell_info.level_mask)) {
                continue;
            }

            if (hash_i < hash_i_offset) {
                hash_i++;
                continue;
            }
            

            bytes memory _hash;
            {
                if (hash_i == hash_i_offset) {
                    // uint32 new_level_mask = applyLevelMask(level_i);
                    require(
                        !(hash_i != 0 &&
                            cells[i].cellType != PrunnedBranchCell),
                        "Cannot deserialize cell"
                    );
                    {
                        uint8 refsCount = 0;
                        for (uint256 t = 0; t < 4; t++) {
                            if (cells[i].refs[t] == 255) {
                                break;
                            }
                            refsCount++;
                        }
                        
                        uint32 new_level_mask = applyLevelMask(
                            level_i,
                            cells[i].level_mask
                        );
                        // uint8 new_d1 =
                        uint8 d1 = uint8(
                            refsCount +
                                (cells[i].special ? 8 : 0) +
                                new_level_mask *
                                32
                        );
                        _hash = cell_slice[1:cell_info.refs_offset];
                        _hash = bytes.concat(bytes1(d1), _hash);
                    }
                } else {
                    require(
                        !(level_i == 0 ||
                            cells[i].cellType == PrunnedBranchCell),
                        "Cannot deserialize cell 2"
                    );
                    _hash = bytes.concat(
                        _hash,
                        cells[i]._hash[hash_i - hash_i_offset - 1]
                    );
                }
            }

            // uint8 dest_i = hash_i - hash_i_offset;
            if (cells[i].refs[0] != 255) {
                uint256 j = 0;
                for (j = 0; j < 4; j++) {
                    if (cells[i].refs[j] == 255) {
                        break;
                    }
                    _hash = bytes.concat(
                        _hash,
                        abi.encodePacked(
                            getDepth(data, level_i, cells, cells[i].refs[j])
                        )
                    );
                   
                    if (
                        getDepth(data, level_i, cells, cells[i].refs[j]) >
                        cells[i].depth[hash_i - hash_i_offset]
                    ) {
                        cells[i].depth[hash_i - hash_i_offset] = getDepth(
                            data,
                            level_i,
                            cells,
                            cells[i].refs[j]
                        );
                    }
                }

                cells[i].depth[hash_i - hash_i_offset]++;
                
                
                for (j = 0; j < 4; j++) {
                    if (cells[i].refs[j] == 255) {
                        break;
                    }
                    
                    _hash = bytes.concat(
                        _hash,
                        getHash(data, level_i, cells, cells[i].refs[j])
                    );
                }
                
                
                cells[i]._hash[hash_i - hash_i_offset] = sha256(_hash);
                
            } else {
                
                
                
                cells[i]._hash[hash_i - hash_i_offset] = sha256(_hash);
                
            }

            hash_i++;
        }
    }

    function getHash(
        bytes calldata data,
        uint8 level,
        // uint32 levelMask,
        // uint256 cellType,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32) {
        uint8 hash_i = getHashesCountFromMask(
            applyLevelMask(level, cells[cellIdx].level_mask)
        ) - 1;

        if (cells[cellIdx].cellType == PrunnedBranchCell) {
            uint8 this_hash_i = getHashesCount(cells[cellIdx].level_mask) - 1;
            if (hash_i != this_hash_i) {
                
                uint256 cursor = 16 + uint256(hash_i) * 2 * 8;
                cells[cellIdx].cursor += cursor;
                uint256 hash_num = readUint(data, cells, cellIdx, 256);
                cells[cellIdx].cursor -= cursor + 256;

                return bytes32(hash_num);
            }
            hash_i = 0;
        }
        return cells[cellIdx]._hash[hash_i];
    }
}
