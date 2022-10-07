//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./BitReader.sol";
import "hardhat/console.sol";

import "../types/BagOfCellsInfo.sol";
import "../types/CellData.sol";
import "../types/CellSerializationInfo.sol";
import "../types/TransactionTypes.sol";

contract TocHashes is BitReader {
    uint8 public constant OrdinaryCell = 255;
    uint8 public constant PrunnedBranchCell = 1;
    uint8 public constant LibraryCell = 2;
    uint8 public constant MerkleProofCell = 3;
    uint8 public constant MerkleUpdateCell = 4;

    function calcHashesForToc(
        bytes calldata boc,
        BagOfCellsInfo memory info,
        CellData[100] memory cells
    ) public view {
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

    function getHashesCount(uint32 mask) public view returns (uint8) {
        return getHashesCountFromMask(mask & 7);
    }

    function getHashesCountFromMask(uint32 mask) public view returns (uint8) {
        uint8 n = 0;
        uint32 maskCopy = mask;
        for (uint8 i = 0; i < 3; i++) {
            n += uint8(maskCopy & 1);
            maskCopy = maskCopy >> 1;
        }
        return n + 1;
    }

    function getLevelFromMask(uint32 mask) public pure returns (uint8) {
        uint8 n = 0;
        uint32 maskCopy = mask;
        for (uint8 i = 0; i < 3; i++) {
            n += uint8(maskCopy & 1);
            maskCopy = maskCopy >> 1;
        }
        return n + 1;
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
    ) public view returns (uint16) {
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
                cells[cellIdx].cursor = cursor;
                uint16 childDepth = readUint16(data, cells, cellIdx, 16);
                cells[cellIdx].cursor -= cursor;

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
    ) public view {
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
                    _hash = cell_slice[:cell_info.refs_offset];
                    // console.logBytes(_hash);
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
                // console.logBytes(_hash);
                for (j = 0; j < 4; j++) {
                    if (cells[i].refs[j] == 255) {
                        break;
                    }
                    // console.log("LEVEL I:", level_i);
                    _hash = bytes.concat(
                        _hash,
                        getHash(
                            data,
                            level_i,
                            cells,
                            cells[i].refs[j]
                        )
                    );
                }
                // console.logBytes(_hash);
                cells[i]._hash[hash_i - hash_i_offset] = sha256(_hash);
            } else {
                // console.log("WORING HARD WITHOUT REFS");
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
    ) public view returns (bytes32) {
        uint8 hash_i = getHashesCountFromMask(
            applyLevelMask(level, cells[cellIdx].level_mask)
        ) - 1;

        if (cells[cellIdx].cellType == PrunnedBranchCell) {
            uint8 this_hash_i = getHashesCount(cells[cellIdx].level_mask) - 1;
            if (hash_i != this_hash_i) {
                uint256 cursor = 16 + uint256(hash_i) * 2 * 8;
                uint256 hash_num = readUint(data, cells, cellIdx, 256);
                cells[cellIdx].cursor -= cursor;

                return bytes32(hash_num);
            }
            hash_i = 0;
        }
        return cells[cellIdx]._hash[hash_i];
    }

    function get_indexes(bytes calldata boc, BagOfCellsInfo memory info)
        public
        view
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
    ) public view returns (CellSerializationInfo memory cellInfo) {
        require(!(data.length < 2), "Not enough bytes");
        uint8 d1 = uint8(data[0]);
        uint8 d2 = uint8(data[1]);

        cellInfo.refs_cnt = d1 & 7;
        cellInfo.level_mask = d1 >> 5;
        cellInfo.special = (d1 & 8) != 0;

        cellInfo.with_hashes = (d1 & 16) != 0;

        if (cellInfo.refs_cnt > 4) {
            console.log(cellInfo.refs_cnt);
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

    function get_cell_slice(
        uint256 idx,
        bytes calldata cells_slice,
        uint256[100] memory custom_index
    ) public pure returns (bytes calldata cell_slice) {
        uint256 offs = idx == 0 ? 0 : custom_index[idx - 1];
        uint256 offs_end = custom_index[idx];
        return cells_slice[offs:offs_end];
    }
}
