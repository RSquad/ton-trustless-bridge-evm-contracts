//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";

struct BocHeader {
    bool has_idx;
    bool hash_crc32;
    bool has_cache_bits;
    uint16 flags;
    uint8 size_bytes;
    uint8 off_bytes;
    uint256 cells_num;
    uint256 roots_num;
    uint256 absent_num;
    uint256 tot_cells_size;
    uint256 root;
    // root_list: root_list,
    // index: index,
    bytes cells_data;
}

contract BaseAdapter {
    bytes4 reachBocMagicPrefix = 0xb5ee9c72;
    bytes4 leanBocMagicPrefix = 0x68ff65f3;
    bytes4 leanBocMagicPrefixCRC = 0xacc3a728;

    constructor() {
        console.log("Deploying a Adapter");
    }

    function readNBytesUIntFromArray(uint8 n, bytes calldata ui8array)
        public
        returns (uint256)
    {
        uint256 res = 0;
        for (uint8 c = 0; c < n; c++) {
            res *= 256;
            res += uint8(ui8array[c]);
        }
        return res;
    }

    function parseBocHeader(bytes calldata boc)
        external
        returns (BocHeader memory header)
    {
        bytes4 prefix = bytes4(boc[0:4]);
        // console.log("Prefix: '%s'", string(prefix));
        console.logBytes4(prefix);

        BocHeader memory bocHeader = BocHeader(
            false,
            false,
            false,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            // root_list,
            // index,
            boc[0:4]
        );

        // bool has_idx = false;
        // bool hash_crc32 = false;
        // bool has_cache_bits = false;

        // uint16 flags = 0;
        // uint8 size_bytes = 0;

        if (prefix == reachBocMagicPrefix) {
            console.log("isRich");
            uint8 flags_byte = uint8(boc[4]);
            bocHeader.has_idx = (flags_byte & 128) != 0;
            bocHeader.hash_crc32 = (flags_byte & 64) != 0;
            bocHeader.has_cache_bits = (flags_byte & 32) != 0;
            bocHeader.flags = (flags_byte & 16) * 2 + (flags_byte & 8);
            bocHeader.size_bytes = flags_byte % 8;
        } else if (prefix == leanBocMagicPrefix) {
            console.log("isLean");
            bocHeader.has_idx = true;
            bocHeader.hash_crc32 = false;
            bocHeader.has_cache_bits = false;
            bocHeader.flags = 0;
            bocHeader.size_bytes = uint8(boc[4]);
        } else if (prefix == leanBocMagicPrefixCRC) {
            console.log("isLeanCRC");
            bocHeader.has_idx = true;
            bocHeader.hash_crc32 = true;
            bocHeader.has_cache_bits = false;
            bocHeader.flags = 0;
            bocHeader.size_bytes = uint8(boc[4]);
        } else {
            // throw Error('Unknown magic prefix');
        }

        // Counters
        bytes calldata serializedBoc = boc[5:];
        if (serializedBoc.length < 1 + 5 * bocHeader.size_bytes) {
            // throw new Error('Not enough bytes for encoding cells counters');
        }
        bocHeader.off_bytes = uint8(serializedBoc[0]);
        serializedBoc = serializedBoc[1:];
        bocHeader.cells_num = readNBytesUIntFromArray(
            bocHeader.size_bytes,
            serializedBoc
        );
        serializedBoc = serializedBoc[bocHeader.size_bytes:];
        bocHeader.roots_num = readNBytesUIntFromArray(
            bocHeader.size_bytes,
            serializedBoc
        );
        serializedBoc = serializedBoc[bocHeader.size_bytes:];
        bocHeader.absent_num = readNBytesUIntFromArray(
            bocHeader.size_bytes,
            serializedBoc
        );
        serializedBoc = serializedBoc[bocHeader.size_bytes:];
        bocHeader.tot_cells_size = readNBytesUIntFromArray(
            bocHeader.off_bytes,
            serializedBoc
        );
        serializedBoc = serializedBoc[bocHeader.off_bytes:];
        if (serializedBoc.length < bocHeader.roots_num * bocHeader.size_bytes) {
            // throw new Error('Not enough bytes for encoding root cells hashes');
        }

        // Roots
        // let's think that we have only 1 root always
        // let root_list = [];
        uint256 root = 0;
        for (uint256 c = 0; c < bocHeader.roots_num; c++) {
            if (root == 0) {
                root = readNBytesUIntFromArray(
                    bocHeader.size_bytes,
                    serializedBoc
                );
            }
            // root_list.push(readNBytesUIntFromArray(size_bytes, serializedBoc));
            serializedBoc = serializedBoc[bocHeader.size_bytes:];
        }

        if (bocHeader.has_idx) {
            console.log("has index!!!");
        }
        // // Index
        // let index: number[] | null = null;
        // if (has_idx) {
        //     index = [];
        //     if (serializedBoc.length < offset_bytes * cells_num)
        //         throw new Error("Not enough bytes for index encoding");
        //     for (let c = 0; c < cells_num; c++) {
        //         index.push(readNBytesUIntFromArray(offset_bytes, serializedBoc));
        //         serializedBoc = serializedBoc.slice(offset_bytes);
        //     }
        // }

        // Cells
        if (serializedBoc.length < bocHeader.tot_cells_size) {
            // throw new Error('Not enough bytes for cells data');
        }
        bocHeader.cells_data = serializedBoc[0:bocHeader.tot_cells_size];
        serializedBoc = serializedBoc[bocHeader.tot_cells_size:];
        console.log(root);
        console.logBytes(bocHeader.cells_data);

        if (bocHeader.hash_crc32) {
            console.log("has crc32 !!!");
        }
        // // CRC32
        // if (hash_crc32) {
        //     if (serializedBoc.length < 4) {
        //         throw new Error('Not enough bytes for crc32c hashsum');
        //     }
        //     const length = inputData.length;
        //     if (!crc32c(inputData.slice(0, length - 4)).equals(serializedBoc.slice(0, 4))) {
        //         throw new Error('Crc32c hashsum mismatch');
        //     }
        //     serializedBoc = serializedBoc.slice(4);
        // }

        // // Check if we parsed everything
        // if (serializedBoc.length) {
        //     throw new Error('Too much bytes in BoC serialization');
        // }
        return bocHeader;
    }

    function deserializeCellData(
        bytes calldata cellData,
        uint8 referenceIndexSize
    ) external 
    //  returns(
    //     uint8 kind, bytes memory bits, uint[4] memory refs, uint residue
    // )
    {
        if (cellData.length < 2) {
            console.log("Not enough bytes to encode");
        }

        // uint8 d1 = uint8(cellData[0]);
        // uint8 d2 = uint8(cellData[1]);
        uint256 cursor = 2;

        bool isExotic = (uint8(cellData[0]) & 8) != 0;
        uint8 refNum = uint8(cellData[0]) % 8;
        uint8 dataBytesize = uint8(cellData[1]) / 2;
        // bool fullfilledBytes = (uint8(cellData[1]) % 2) == 0;
        uint256[4] memory refs;

        // Build Cell
        if (cellData.length < dataBytesize + referenceIndexSize * refNum) {
            // throw new Error('Not enough bytes to encode cell data');
            console.log("Not enough bytes to encode cell data");
        }

        // Cell data
        /*
        let kind: CellType = 'ordinary';
        if (isExotic) {
            let k = cellData.readUInt8();
            if (k === 1) {
                kind = 'pruned';
            } else if (k === 2) {
                kind = 'library_reference';
            } else if (k === 3) {
                kind = 'merkle_proof';
            } else if (k === 4) {
                kind = 'merkle_update';
            } else {
                throw Error('Invalid cell type: ' + k);
            }
            cellData = cellData.slice(1);
            dataBytesize--;
        }
        */
        uint8 kind = 0;
        if (isExotic) {
            kind = uint8(cellData[cursor]);
            cursor += 1;
            dataBytesize--;
        }

        bytes memory bits = cellData[cursor:dataBytesize];
        cursor += dataBytesize;

        // bits.setTopUppedArray(cellData.slice(0, dataBytesize), fullfilledBytes);
        // cellData = cellData.slice(dataBytesize);

        // References
        for (uint8 r = 0; r < refNum; r++) {
            refs[r] = readNBytesUIntFromArray(
                referenceIndexSize,
                cellData[cursor:]
            );
            // refs.push(readNBytesUIntFromArray(referenceIndexSize, cellData));
            // cellData = cellData.slice(referenceIndexSize);
            cursor += referenceIndexSize;
        }

        // Resolve kind
        // let cell = new Cell(kind, bits);

        // return ( kind, bits, refs, cursor );
    }

    function deserializeBoc(bytes calldata boc) external {
        BocHeader memory header = this.parseBocHeader(boc);
        console.log("Header has parsed");
        uint256 cursor = 0;

        for (uint256 ci = 0; ci < header.cells_num; ci++) {
            // (uint8 kind, bytes memory bits, uint[4] memory refs, uint residue) =  this.deserializeCellData(header.cells_data, header.size_bytes);
            this.deserializeCellData(header.cells_data, header.size_bytes);
            // cursor = residue;
            // console.log(cursor);
        }

        // Topological check
        // for (uint ci = header.cells_num - 1; ci >= 0; ci--) {

        // }
    }
}