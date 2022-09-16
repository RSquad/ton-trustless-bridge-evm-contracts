//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./BitReader.sol";
import "../types/BagOfCellsInfo.sol";
import "../types/TransactionTypes.sol";
import "hardhat/console.sol";

contract BlockParser is BitReader {
    function parse_block(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) public view {
        uint32 tag = readUint32(boc, treeOfCells, rootIdx, 32);
        console.log("GlobalId:", tag);
    }
    // function parse_block(
    //     bytes calldata proofBoc,
    //     BagOfCellsInfo memory proofBocInfo,
    //     CellData[100] memory proofTreeOfCells,
    //     bytes32 txRootHash,
    //     TransactionHeader memory transaction
    // ) public view returns (bool) {
    //     uint256 proofRootIdx = proofBocInfo.cell_count -
    //         read_int(
    //             proofBoc[proofBocInfo.roots_offset:],
    //             proofBocInfo.ref_byte_size
    //         ) -
    //         1;

    //     uint32 tag = readUint32(proofTreeOfCells, proofRootIdx, 32);
    //     // console.log("GlobalId:", tag);
    //     // blockInfo^ (pruned)
    //     uint256 blockInfoIdx = readCell(proofTreeOfCells, proofRootIdx);
    //     // require(check_block_info(proofTreeOfCells, blockInfoIdx, transaction), "lt doesn't belong to block interval");
    //     // value flow^ (pruned)
    //     readCell(proofTreeOfCells, proofRootIdx);
    //     // state_update^ (pruned)
    //     readCell(proofTreeOfCells, proofRootIdx);
    //     uint256 extraIdx = readCell(proofTreeOfCells, proofRootIdx);
    //     return
    //         parse_block_extra(
    //             proofTreeOfCells,
    //             extraIdx,
    //             txRootHash,
    //             transaction
    //         );
    // }

    // function readUintLeq(CellData[100] memory cells, uint cellIdx, uint n) public view returns (uint) {
    //     uint16 last_one = 0;
    //     uint l = 1;
    //     bool found = false;
    //     for (uint16 i = 0; i < 32; i++) {
    //         if ((n & l) > 0) {
    //             last_one = i;
    //             found = true;
    //         }
    //         l = l << 1;
    //     }
    //     require(found, "not a UintLe");
    //     last_one++;
    //     return readUint(cells, cellIdx, last_one);
    // }

    // function check_block_info(CellData[100] memory cells, uint cellIdx, TransactionHeader memory transaction) public view returns (bool) {
    //     require(readUint32(cells, cellIdx, 32) == 0x9bc7a987, "not a BlockInfo");
    //     // // version
    //     // readUint32(cells, cellIdx, 32);
    //     // // not_master
    //     // readBool(cells, cellIdx);
    //     // // after_merge
    //     // readBool(cells, cellIdx);
    //     // // before_split
    //     // readBool(cells, cellIdx);
    //     // // after_split
    //     // readBool(cells, cellIdx);
    //     // // want_split
    //     // readBool(cells, cellIdx);
    //     // // want merge
    //     // readBool(cells, cellIdx);
    //     // // key_block
    //     // readBool(cells, cellIdx);
    //     // // vert seqno incer
    //     // readBool(cells, cellIdx);
    //     cells[cellIdx].cursor += 32 + 1 * 8;
    //     // flags
    //     require(readUint8(cells, cellIdx, 8) <= 1, "data.flags > 1");
    //     // seq_no
    //     // readUint32(cells, cellIdx, 32);
    //     // vert_seq_no
    //     // readUint32(cells, cellIdx, 32);
    //     cells[cellIdx].cursor += 64;
    //     // shard Ident
    //     readUint8(cells, cellIdx, 2);
    //     readUintLeq(cells, cellIdx, 60);
    //     readUint32(cells, cellIdx, 32);
    //     readUint64(cells, cellIdx, 64);

    //     // end shard Ident

    //     // gen_utime
    //     readUint32(cells, cellIdx, 32);

    //     uint64 start_lt = readUint64(cells, cellIdx, 64);
    //     uint64 end_lt = readUint64(cells, cellIdx, 64);

    //     return transaction.lt >= start_lt || transaction.lt <= end_lt;
    // }

    // function parse_block_extra(
    //     CellData[100] memory cells,
    //     uint256 cellIdx,
    //     bytes32 txRootHash,
    //     TransactionHeader memory transaction
    // ) public view returns (bool) {
    //     uint32 isBlockExtra = readUint32(cells, cellIdx, 32);
    //     require(isBlockExtra == 1244919549, "cell is not extra block info");

    //     // in_msg_descr^ (pruned)
    //     readCell(cells, cellIdx);
    //     // out_msg_descr^ (pruned)
    //     readCell(cells, cellIdx);
    //     // account_blocks^
    //     uint256 account_blocksIdx = readCell(cells, readCell(cells, cellIdx));

    //     uint256[10] memory accountIdxs = parseDict(
    //         cells,
    //         account_blocksIdx,
    //         256
    //     );
    //     for (uint256 i = 0; i < 10; i++) {
    //         if (accountIdxs[i] == 255) {
    //             break;
    //         }
    //         // _ (HashmapAugE 256 AccountBlock CurrencyCollection) = ShardAccountBlocks;
    //         parseCurrencyCollection(cells, accountIdxs[i]);
    //         require(readUint8(cells, accountIdxs[i], 4) == 5, "is not account block");
    //         bytes32 addressHash = readBytes32(cells, accountIdxs[i], 32);

    //         if (addressHash != transaction.addressHash) {
    //             continue;
    //         }

    //         // get transactions of this account
    //         uint256[10] memory txIdxs = parseDict(cells, accountIdxs[i], 64);
    //         for (uint j = 0; j < 10; j++) {
    //             if (txIdxs[j] == 255) {
    //                 break;
    //             }
    //             if (cells[readCell(cells, txIdxs[j])]._hash[0] == txRootHash) {
    //                 return true;
    //             }
    //         }
    //     }
    //     return false;
    // }
}
