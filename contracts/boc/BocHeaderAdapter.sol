//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./BocHeaderInfoAdapter.sol";
import "./TreeOfCellsAdapter.sol";
import "./UtilsLib.sol";

struct Transaction {
   uint checkCode; 
   bytes32 addressHash;
   uint lt;
   bytes32 prevTransHash;
   uint prevTransLt;

   uint time;
   uint OutMesagesCount;

   uint oldStatus;
   uint newStatus;
}

contract BocHeaderAdapter is BocHeaderInfoAdapter, TreeOfCellsAdapter {

    function deserialize(bytes calldata boc) public view returns(Transaction memory transaction) {
        BagOfCellsInfo memory info = parse_serialized_header(boc);
        
        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[50] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint rootIdx = info.cell_count - UtilsLib.read_int(boc[info.roots_offset:], info.ref_byte_size) - 1;
        console.log("Root idx: %d",rootIdx);
        
        CellData[50] memory cells = get_tree_of_cells(boc, info);
        uint cursor = 0;
        
        transaction.checkCode = readBits(cells[rootIdx].bits, cursor, 4);
        cursor += 4;
        
        // addressHash
        transaction.addressHash = bytes32(readBits(cells[rootIdx].bits, cursor, 32 * 8));
        cursor += 32 * 8;
        // lt
        transaction.lt = readBits(cells[rootIdx].bits, cursor, 64);
        cursor += 64;

        transaction.prevTransHash = bytes32(readBits(cells[rootIdx].bits, cursor, 32 * 8));
        cursor += 32 * 8;
        transaction.prevTransLt = readBits(cells[rootIdx].bits, cursor, 64);
        cursor += 64;

        transaction.time = readBits(cells[rootIdx].bits, cursor, 32);
        cursor += 32;

        transaction.OutMesagesCount = readBits(cells[rootIdx].bits, cursor, 15);
        cursor += 15;

        transaction.oldStatus = readBits(cells[rootIdx].bits, cursor, 2);
        cursor += 2;
        transaction.newStatus = readBits(cells[rootIdx].bits, cursor, 2);
        cursor += 2;

        // messagesRef = cells[rootIdx].refs[0]
        // hash update = cells[rootIdx].refs[1]
        // description = cells[rootIdx].refs[2]


        return transaction;
    }

    function readBits(bytes memory data, uint start, uint size) public pure returns (uint res) {
        res = 0;
        uint cursor = start / 8;
        uint bytesStart = start % 8;
        while (size > 0) {
            res = (res << 1) + (uint8(data[cursor]) << bytesStart >> 7 );
            bytesStart = (bytesStart + 1) % 8;
            if (bytesStart == 0) {
                cursor ++;
            }
            size --;
        }
        return res;
    }
}