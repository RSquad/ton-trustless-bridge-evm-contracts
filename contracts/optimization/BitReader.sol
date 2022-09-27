//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/CellData.sol";

// TODO: read not only bit, but byte too when it possible

contract BitReader {
    // function readInt(bytes calldata data, uint256 size)
    //     external
    //     pure
    //     returns (uint256 value)
    // {
    //     uint256 res = 0;
    //     uint256 cursor = 0;
    //     while (size > 0) {
    //         res = (res << 8) + uint8(data[cursor]);
    //         cursor++;
    //         --size;
    //     }
    //     return res;
    // }

    function readBit(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (uint8 value) {
        uint256 cursor = cells[cellIdx].cursor / 8;
        uint256 bytesStart = cells[cellIdx].cursor % 8;
        value = uint8((data[cursor] << bytesStart) >> 7);
        cells[cellIdx].cursor += 1;
        return value;
    }

    function readBool(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bool value) {
        return readBit(data, cells, cellIdx) == 1;
    }

    function readUint8(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public pure returns (uint8 value) {
        require(size <= 8, "max size is 8 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint16(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public pure returns (uint16 value) {
        require(size <= 16, "max size is 16 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint32(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public pure returns (uint32 value) {
        require(size <= 32, "max size is 32 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint64(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint16 size
    ) public pure returns (uint64 value) {
        require(size <= 64, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint16 size
    ) public pure returns (uint256 value) {
        require(size <= 256, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }

        return value;
    }

    function readBytes32BitSize(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 size
    ) public pure returns (bytes32 buffer) {
        uint256 value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readBytes32ByteSize(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 sizeb
    ) public pure returns (bytes32 buffer) {
        uint256 size = sizeb * 8;
        uint256 value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(data, cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readCell(
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (uint256 idx) {
        idx = cells[cellIdx].refs[cells[cellIdx].cursorRef];
        cells[cellIdx].cursorRef++;
        return idx;
    }

    function readUnaryLength(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (uint256 value) {
        value = 0;
        while (readBool(data, cells, cellIdx)) {
            value++;
        }
        return value;
    }

    function log2Ceil(uint256 x) public pure returns (uint256 n) {
        bool check = false;

        for (n = 0; x > 1; x >>= 1) {
            n += 1;

            if (x & 1 == 1 && !check) {
                n += 1;
                check = true;
            }
        }

        if (x == 1 && !check) {
            n += 1;
        }

        return n;
    }

    function parseDict(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 keySize
    ) public pure returns (uint256[30] memory cellIdxs) {
        for (uint256 i = 0; i < 30; i++) {
            cellIdxs[i] = 255;
        }
        doParse(data, 0, cells, cellIdx, keySize, cellIdxs);
        return cellIdxs;
    }

    function doParse(
        bytes calldata data,
        uint256 prefix,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 n,
        uint256[30] memory cellIdxs
    ) public pure {
        uint256 prefixLength = 0;
        uint256 pp = prefix;

        // lb0
        if (!readBool(data, cells, cellIdx)) {
            // Short label detected
            prefixLength = readUnaryLength(data, cells, cellIdx);
            // console.log("Short label detected", cellIdx, n, prefixLength);

            for (uint256 i = 0; i < prefixLength; i++) {
                pp = (pp << 1) + readBit(data, cells, cellIdx);
            }
        } else {
            // lb1
            if (!readBool(data, cells, cellIdx)) {
                // long label detected
                prefixLength = readUint64(data, cells, cellIdx, uint8(log2Ceil(n)));
                // console.log("Long label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + readBit(data, cells, cellIdx);
                }
            } else {
                // Same label detected
                uint256 bit = readBit(data, cells, cellIdx);
                prefixLength = readUint64(data, cells, cellIdx, uint8(log2Ceil(n)));
                // console.log("Same label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + bit;
                }
            }
        }
        if (n - prefixLength == 0) {
            // end
            for (uint256 i = 0; i < 30; i++) {
                if (cellIdxs[i] == 255) {
                    cellIdxs[i] = cellIdx;
                    break;
                }
            }
            // cellIdxs[pp] = cellIdx;
            // res.set(new BN(pp, 2).toString(30), extractor(slice));
        } else {
            uint256 leftIdx = readCell(cells, cellIdx);
            uint256 rightIdx = readCell(cells, cellIdx);
            // NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (leftIdx != 255 && !cells[leftIdx].special) {
                doParse(
                    data,
                    pp << 1,
                    cells,
                    leftIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            }
            if (rightIdx != 255 && !cells[rightIdx].special) {
                doParse(
                    data,
                    pp << (1 + 1),
                    cells,
                    rightIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            }
        }
    }
}
