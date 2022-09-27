//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./BitReader.sol";
import "../types/BagOfCellsInfo.sol";
import "../types/TransactionTypes.sol";
import "../types/BlockTypes.sol";
import "hardhat/console.sol";

contract BlockParser is BitReader {
    ValidatorDescription[30] validatorSet;

    function getValidators() public view returns (ValidatorDescription[30] memory) {
        return validatorSet;
    }

    // TODO: onlyowner; only if validatorset is empty
    function setValidatorSet(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) public {
        delete validatorSet;
        uint32 tag = readUint32(boc, treeOfCells, rootIdx, 32);
        console.log("GlobalId:", tag);

        // extra
        uint256 extraCellIdx = treeOfCells[rootIdx].refs[3];
        ValidatorDescription[30] memory v = parseBlockExtra(boc, extraCellIdx, treeOfCells);
    

        // ValidatorDescription[30] memory v = parse_block(boc, rootIdx, treeOfCells);
        for (uint256 i = 0; i < v.length; i++) {
            validatorSet[i] = v[i];
        }
        for (uint256 i = 0; i < validatorSet.length; i++) {
            validatorSet[i].node_id = computeNodeId(validatorSet[i].pubkey);
        }
    }

    function computeNodeId(bytes32 publicKey) public pure returns (bytes32) {
        return sha256(bytes.concat(bytes4(0xc6b41348), publicKey));
    }

    function parse_block(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) public view returns (ValidatorDescription[30] memory) {
        uint32 tag = readUint32(boc, treeOfCells, rootIdx, 32);
        console.log("GlobalId:", tag);

        // extra
        uint256 extraCellIdx = treeOfCells[rootIdx].refs[3];
        return parseBlockExtra(boc, extraCellIdx, treeOfCells);
    }

    function parseBlockExtra(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public view returns (ValidatorDescription[30] memory) {
        require(
            readUint32(boc, treeOfCells, cellIdx, 32) == 0x4a33f6fd,
            "not a BlockExtra"
        );

        // McBlockExtra
        uint256 customIdx = treeOfCells[cellIdx].refs[3];
        require(customIdx != 255, "No McBlockExtra");
        return parseMcBlockExtra(boc, customIdx, treeOfCells);
    }

    function parseMcBlockExtra(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public view returns (ValidatorDescription[30] memory) {
        require(
            readUint16(boc, treeOfCells, cellIdx, 16) == 0xcca5,
            "not a McBlockExtra"
        );

        bool isKeyBlock = readBool(boc, treeOfCells, cellIdx);
        readCell(treeOfCells, cellIdx);
        readCell(treeOfCells, cellIdx);
        readCell(treeOfCells, cellIdx);
        if (isKeyBlock) {
            // config params

            return parseConfigParams(boc, cellIdx, treeOfCells);
        }

        require(false, "is no key block");
        // return validators;
    }

    function parseConfigParams(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public view returns (ValidatorDescription[30] memory) {
        // skip useless data
        treeOfCells[cellIdx].cursor += 76;
        // readBytes32BitSize(boc, treeOfCells, cellIdx, 76);
        bytes32 configAddress = readBytes32BitSize(
            boc,
            treeOfCells,
            cellIdx,
            256
        );
        console.logBytes32(configAddress);
        uint256 configParamsIdx = readCell(treeOfCells, cellIdx);
        require(configParamsIdx != 255, "No Config Params");

        uint256[30] memory txIdxs = parseDict(
            boc,
            treeOfCells,
            configParamsIdx,
            32
        );
        for (uint256 i = 0; i < 30; i++) {
            if (txIdxs[i] == 255) {
                break;
            }

            configParamsIdx = txIdxs[i];
        }

        return parseConfigParam34(boc, configParamsIdx, treeOfCells);
    }

    function parseConfigParam34(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) public view returns (ValidatorDescription[30] memory validators) {
        // for (uint16 i = 17; i < 1024; i++) {
        uint256 skipped = readUint(data, cells, cellIdx, 28);
        // console.log("skipped", i, skipped);
        uint8 cType = readUint8(data, cells, cellIdx, 8);
        // console.log("cType", cType);
        // if (cType == 17 || cType == 18) {
        //     break;
        // } else {
        //     cells[cellIdx].cursor -= 8 + i;
        // }
        // console.log("-------");
        // }

        uint32 utime_since = readUint32(data, cells, cellIdx, 32);
        uint32 utime_until = readUint32(data, cells, cellIdx, 32);
        uint16 total = readUint16(data, cells, cellIdx, 16);
        uint16 main = readUint16(data, cells, cellIdx, 16);
        uint64 totalWeight = 0;
        console.log("cellIdx", cellIdx);
        console.log(utime_since);
        console.log(utime_until);
        console.log(total);
        console.log(main);

        if (cType == 0x12) {
            totalWeight = readUint64(data, cells, cellIdx, 64);
        }
        console.log(totalWeight);
        uint256 subcellIdx = readCell(cells, cellIdx);
        console.log("cell", subcellIdx);
        uint256[30] memory txIdxs = parseDict(
            data,
            cells,
            readCell(cells, subcellIdx),
            16
        );

        console.log("list of items");
        // ValidatorDescription[30] memory validators;
        for (uint256 i = 0; i < 30; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            validators[i] = readValidatorDescription(data, txIdxs[i], cells);
            // console.log("id", i, txIdxs[i]);
        }
        return validators;
    }

    function readValidatorDescription(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) public view returns (ValidatorDescription memory validator) {
        validator.cType = readUint8(data, cells, cellIdx, 8);
        // console.log(cType, 0x53, 0x73);
        require(
            readUint32(data, cells, cellIdx, 32) == 0x8e81278a,
            "not a SigPubKey"
        );
        validator.pubkey = readBytes32BitSize(data, cells, cellIdx, 256);
        validator.weight = readUint64(data, cells, cellIdx, 64);
        if (validator.cType == 0x73) {
            validator.adnl_addr = readBytes32BitSize(data, cells, cellIdx, 256);
        }
        return validator;
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

    //     uint256[30] memory accountIdxs = parseDict(
    //         cells,
    //         account_blocksIdx,
    //         256
    //     );
    //     for (uint256 i = 0; i < 30; i++) {
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
    //         uint256[30] memory txIdxs = parseDict(cells, accountIdxs[i], 64);
    //         for (uint j = 0; j < 30; j++) {
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
