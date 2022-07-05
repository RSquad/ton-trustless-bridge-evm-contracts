//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";



contract Adapter {
    string private greeting;

    bytes4 reachBocMagicPrefix = 0xb5ee9c72;
    bytes4 leanBocMagicPrefix = 0x68ff65f3;
    bytes4 leanBocMagicPrefixCRC = 0xacc3a728;

    constructor() {
        console.log("Deploying a Adapter");
    }



    function greet() public view returns (string memory) {
        return greeting;
    }

    function setGreeting(string memory _greeting) public {
        console.log("Changing greeting from '%s' to '%s'", greeting, _greeting);
        greeting = _greeting;
    }

    function readNBytesUIntFromArray(uint8 n, bytes calldata ui8array) public returns (uint) {
    uint res = 0;
    for (uint8 c = 0; c < n; c++) {
        res *= 256;
        res += uint8(ui8array[c]);
    }
    return res;
    }

    function getBoc(bytes calldata boc) external  {
        bytes4 prefix = bytes4(boc[0:4]);
        // console.log("Prefix: '%s'", string(prefix));
        console.logBytes4(prefix);
        
        bool has_idx = false;
        bool hash_crc32 = false;
        bool has_cache_bits = false;

        uint16 flags = 0;
        uint8 size_bytes = 0;

        if (prefix == reachBocMagicPrefix) {
            console.log("isRich");
            uint8 flags_byte = uint8(boc[4]);
            has_idx = (flags_byte & 128) != 0;
            hash_crc32 = (flags_byte & 64) != 0;
            has_cache_bits = (flags_byte & 32) != 0;
            flags = (flags_byte & 16) * 2 + (flags_byte & 8);
            size_bytes = flags_byte % 8;
        } else if (prefix == leanBocMagicPrefix) {
            console.log("isLean");
            has_idx = true;
            hash_crc32 = false;
            has_cache_bits = false;
            flags = 0;
            size_bytes = uint8(boc[4]);
        } else if (prefix == leanBocMagicPrefixCRC) {
            console.log("isLeanCRC");
            has_idx = true;
            hash_crc32 = true;
            has_cache_bits = false;
            flags = 0;
            size_bytes = uint8(boc[4]);
        } else {
            // throw Error('Unknown magic prefix');
        }
        
        // Counters
        bytes calldata serializedBoc = boc[5:];
        if (serializedBoc.length < 1 + 5 * size_bytes) {
            // throw new Error('Not enough bytes for encoding cells counters');
        }
        uint8 offset_bytes = uint8(serializedBoc[0]);
        serializedBoc = serializedBoc[1:];
        uint cells_num = readNBytesUIntFromArray(size_bytes, serializedBoc);
        serializedBoc = serializedBoc[size_bytes:];
        uint roots_num = readNBytesUIntFromArray(size_bytes, serializedBoc);
        serializedBoc = serializedBoc[size_bytes:];
        uint absent_num = readNBytesUIntFromArray(size_bytes, serializedBoc);
        serializedBoc = serializedBoc[size_bytes:];
        uint tot_cells_size = readNBytesUIntFromArray(offset_bytes, serializedBoc);
        serializedBoc = serializedBoc[offset_bytes:];
        if (serializedBoc.length < roots_num * size_bytes) {
            // throw new Error('Not enough bytes for encoding root cells hashes');
        }

        
        // Roots
        // let's think that we have only 1 root always
        // let root_list = [];
        uint root = 0;
        for (uint c = 0; c < roots_num; c++) {
            if(root == 0) {
                root = readNBytesUIntFromArray(size_bytes, serializedBoc);
            }
            // root_list.push(readNBytesUIntFromArray(size_bytes, serializedBoc));
            serializedBoc = serializedBoc[size_bytes:];
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

    // // Cells
    // if (serializedBoc.length < tot_cells_size) {
    //     throw new Error('Not enough bytes for cells data');
    // }
    // const cells_data = serializedBoc.slice(0, tot_cells_size);
    // serializedBoc = serializedBoc.slice(tot_cells_size);

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
    // return {
    //     has_idx: has_idx,
    //     hash_crc32: hash_crc32,
    //     has_cache_bits: has_cache_bits,
    //     flags: flags,
    //     size_bytes: size_bytes,
    //     off_bytes: offset_bytes,
    //     cells_num: cells_num,
    //     roots_num: roots_num,
    //     absent_num: absent_num,
    //     tot_cells_size: tot_cells_size,
    //     root_list: root_list,
    //     index: index,
    //     cells_data: cells_data
    // };
    }
}
