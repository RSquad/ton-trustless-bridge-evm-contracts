//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./BitReader.sol";
import "../types/BagOfCellsInfo.sol";
import "../types/TransactionTypes.sol";
import "../types/BlockTypes.sol";
import "hardhat/console.sol";
import "../libraries/Ed25519.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlockParser.sol";

struct Vdata {
    bytes32 node_id;
    bytes32 r;
    bytes32 s;
}

struct CachedCell {
    uint256 prefixLength;
    bytes32 hash;
}

struct VerifiedBlockInfo {
    bool verified;
    uint32 seq_no;
    uint64 start_lt;
    uint64 end_lt;
    bytes32 new_hash;
}

contract BlockParser is BitReader, Ownable, IBlockParser {
    ValidatorDescription[100] validatorSet;
    uint64 totalWeight = 0;

    CachedCell[10] prunedCells;
    ValidatorDescription[100] candidatesForValidatorSet;
    uint64 candidatesTotalWeight = 0;
    bytes32 root_hash;

    mapping(bytes32 => VerifiedBlockInfo) verifiedBlocks;

    function setRootHashForValidating(bytes32 rh) public {
        root_hash = rh;
    }

    function setVerifiedBlock(bytes32 root_hash, uint32 seq_no)
        public
        onlyOwner
    {
        require(!isVerifiedBlock(root_hash), "block already verified");
        verifiedBlocks[root_hash] = VerifiedBlockInfo(true, seq_no, 0, 0, 0);
    }

    function addCurrentBlockToVerifiedSet() public {
        // if current validatorSet is empty, check caller
        // else check votes

        uint64 currentWeight = 0;
        for (uint256 j = 0; j < validatorSet.length; j++) {
            if (validatorSet[j].verified == root_hash) {
                currentWeight += validatorSet[j].weight;
            }
        }
        // console.log("weights:", currentWeight, totalWeight);
        require(currentWeight * 3 > totalWeight * 2, "not enought votes");

        // validatorSet = candidatesForValidatorSet;
        // delete candidatesForValidatorSet;

        // totalWeight = candidatesTotalWeight;
        // candidatesTotalWeight = 0;
        // console.log("new verified block added:");
        // console.logBytes32(root_hash);

        // require(toc[rootIdx]._hash[0] == root_hash, "wrong toc");

        // uint256 cellIdx = toc[rootIdx].refs[2];
        // console.log("test", readUint8(boc, toc, cellIdx, 8));
        // bytes32 old_hash = readBytes32BitSize(boc, toc, cellIdx, 256);
        // bytes32 new_hash = readBytes32BitSize(boc, toc, cellIdx, 256);

        verifiedBlocks[root_hash] = VerifiedBlockInfo(true, 0, 0, 0, 0);
    }

    function isVerifiedBlock(bytes32 root_hash) public view returns (bool) {
        return verifiedBlocks[root_hash].verified;
    }

    function getTotalWeight() public view returns (uint64) {
        return totalWeight;
    }

    function getPrunedCells() public view returns (CachedCell[10] memory) {
        return prunedCells;
    }

    function verifyValidators(bytes32 file_hash, Vdata[20] calldata vdata)
        public
    {
        uint256 validatodIdx = validatorSet.length;
        for (uint256 i = 0; i < 20; i++) {
            // 1. found validator
            for (uint256 j = 0; j < validatorSet.length; j++) {
                if (validatorSet[j].node_id == vdata[i].node_id) {
                    validatodIdx = j;
                    break;
                }
            }

            require(validatodIdx != validatorSet.length, "wrong node_id");
            // console.log("start Ed25519");
            if (
                Ed25519.verify(
                    validatorSet[validatodIdx].pubkey,
                    vdata[i].r,
                    vdata[i].s,
                    bytes.concat(bytes4(0x706e0bc5), root_hash, file_hash)
                )
            ) {
                // console.log("Success Ed25519");
                validatorSet[validatodIdx].verified = root_hash;
            }
        }
    }

    function getValidators()
        public
        view
        returns (ValidatorDescription[100] memory)
    {
        return validatorSet;
    }

    function getCandidatesForValidators()
        public
        view
        returns (ValidatorDescription[100] memory)
    {
        return candidatesForValidatorSet;
    }

    function setValidatorSet() public {
        // if current validatorSet is empty, check caller
        // else check votes
        if (validatorSet[0].weight == 0) {
            _checkOwner();
        } else {
            uint64 currentWeight = 0;
            for (uint256 j = 0; j < validatorSet.length; j++) {
                if (validatorSet[j].verified == root_hash) {
                    currentWeight += validatorSet[j].weight;
                }
            }
            // console.log("weights:", currentWeight, totalWeight);
            require(currentWeight * 3 > totalWeight * 2, "not enought votes");
        }

        validatorSet = candidatesForValidatorSet;
        delete candidatesForValidatorSet;

        totalWeight = candidatesTotalWeight;
        candidatesTotalWeight = 0;

        // require(toc[rootIdx]._hash[0] == root_hash, "wrong toc");
        //

        // uint256 cellIdx = toc[rootIdx].refs[2];
        // console.log("test", readUint8(boc, toc, cellIdx, 8));
        // bytes32 old_hash = readBytes32BitSize(boc, toc, cellIdx, 256);
        // bytes32 new_hash = readBytes32BitSize(boc, toc, cellIdx, 256);

        verifiedBlocks[root_hash] = VerifiedBlockInfo(true, 0, 0, 0, 0);
    }

    function computeNodeId(bytes32 publicKey) public pure returns (bytes32) {
        return sha256(bytes.concat(bytes4(0xc6b41348), publicKey));
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

    function parseDict2(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 keySize
    ) public returns (uint256[32] memory cellIdxs) {
        for (uint256 i = 0; i < 32; i++) {
            cellIdxs[i] = 255;
        }
        doParse2(data, 0, cells, cellIdx, keySize, cellIdxs);
        return cellIdxs;
    }

    function doParse2(
        bytes calldata data,
        uint256 prefix,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 n,
        uint256[32] memory cellIdxs
    ) public {
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
                prefixLength = readUint64(
                    data,
                    cells,
                    cellIdx,
                    uint8(log2Ceil(n))
                );
                // console.log("Long label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + readBit(data, cells, cellIdx);
                }
            } else {
                // Same label detected
                uint256 bit = readBit(data, cells, cellIdx);
                prefixLength = readUint64(
                    data,
                    cells,
                    cellIdx,
                    uint8(log2Ceil(n))
                );
                // console.log("Same label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + bit;
                }
            }
        }
        // console.log("worked?", cellIdx, prefixLength, n);
        if (n - prefixLength == 0) {
            // console.log("warning, we have validator in base pruned boc");
            // end
            for (uint256 i = 0; i < 32; i++) {
                if (cellIdxs[i] == 255) {
                    cellIdxs[i] = cellIdx;
                    break;
                }
            }
            // cellIdxs[pp] = cellIdx;
            // res.set(new BN(pp, 2).toString(32), extractor(slice));
        } else {
            uint256 leftIdx = readCell(cells, cellIdx);
            uint256 rightIdx = readCell(cells, cellIdx);
            // console.log("left/right idxs", cellIdx, leftIdx, rightIdx);
            // NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (leftIdx != 255 && !cells[leftIdx].special) {
                doParse2(
                    data,
                    pp << 1,
                    cells,
                    leftIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            } else if (cells[leftIdx].special) {
                CachedCell memory sdata = CachedCell(
                    n - prefixLength - 1,
                    bytes32(
                        data[cells[leftIdx].cursor / 8 + 2:cells[leftIdx]
                            .cursor /
                            8 +
                            32 +
                            2]
                    )
                );
                for (uint256 i = 0; i < 10; i++) {
                    if (prunedCells[i].prefixLength == 0) {
                        prunedCells[i] = sdata;
                        break;
                    }
                }
            }
            if (rightIdx != 255 && !cells[rightIdx].special) {
                doParse2(
                    data,
                    pp << (1 + 1),
                    cells,
                    rightIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            } else if (cells[rightIdx].special) {
                CachedCell memory sdata = CachedCell(
                    n - prefixLength - 1,
                    bytes32(
                        data[cells[rightIdx].cursor / 8 + 2:cells[rightIdx]
                            .cursor /
                            8 +
                            32 +
                            2]
                    )
                );
                for (uint256 i = 0; i < 10; i++) {
                    if (prunedCells[i].prefixLength == 0) {
                        prunedCells[i] = sdata;
                        break;
                    }
                }
            }
        }
    }

    function parseCandidatesRootBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) public {
        candidatesTotalWeight = 0;
        delete candidatesForValidatorSet;

        uint32 tag = readUint32(boc, treeOfCells, rootIdx, 32);
        console.log("GlobalId:", tag);

        // extra
        uint256 extraCellIdx = treeOfCells[rootIdx].refs[3];
        parseBlockExtra2(boc, extraCellIdx, treeOfCells);
    }

    function parseBlockExtra2(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public {
        // console.log("cursor", treeOfCells[cellIdx].cursor, treeOfCells[cellIdx].cursor / 8 );
        // console.logBytes(boc[treeOfCells[cellIdx].cursor / 8:]);
        // console.log(treeOfCells[cellIdx].cursor);
        // console.logBytes(
        //     boc[treeOfCells[cellIdx].cursor / 8:treeOfCells[cellIdx].cursor /
        //         8 +
        //         10]
        // );
        uint32 test = readUint32(boc, treeOfCells, cellIdx, 32);
        // console.log(test, 0x4a33f6fd, cellIdx);
        // [treeOfCells[cellIdx].cursor / 8 - 10: treeOfCells[cellIdx].cursor / 8 + 32]
        require(test == 0x4a33f6fd, "not a BlockExtra");

        // McBlockExtra
        uint256 customIdx = treeOfCells[cellIdx].refs[3];
        require(customIdx != 255, "No McBlockExtra");
        parseMcBlockExtra2(boc, customIdx, treeOfCells);
    }

    function parseMcBlockExtra2(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public {
        require(
            readUint16(boc, treeOfCells, cellIdx, 16) == 0xcca5,
            "not a McBlockExtra"
        );

        bool isKeyBlock = readBool(boc, treeOfCells, cellIdx);
        // readCell(treeOfCells, cellIdx);
        // readCell(treeOfCells, cellIdx);
        // readCell(treeOfCells, cellIdx);
        if (isKeyBlock) {
            // config params

            return parseConfigParams2(boc, cellIdx, treeOfCells);
        }

        require(false, "is no key block");
        // return validators;
    }

    function parseConfigParams2(
        bytes calldata boc,
        uint256 cellIdx,
        CellData[100] memory treeOfCells
    ) public {
        // skip useless data
        // treeOfCells[cellIdx].cursor += 76
        treeOfCells[cellIdx].cursor += 8 + 4;
        // readBytes32BitSize(boc, treeOfCells, cellIdx, 76);
        bytes32 configAddress = readBytes32BitSize(
            boc,
            treeOfCells,
            cellIdx,
            256
        );
        console.logBytes32(configAddress);
        uint256 configParamsIdx = treeOfCells[cellIdx].refs[3] == 255
            ? treeOfCells[cellIdx].refs[2]
            : treeOfCells[cellIdx].refs[3];

        // uint256 configParamsIdx = readCell(treeOfCells, cellIdx);
        console.log(
            "cell with ref to config params:",
            cellIdx,
            configParamsIdx
        );
        require(configParamsIdx != 255, "No Config Params");

        uint256[32] memory txIdxs = parseDict(
            boc,
            treeOfCells,
            configParamsIdx,
            32
        );
        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }

            configParamsIdx = txIdxs[i];
        }
        console.log("start reading prunned config params 34", configParamsIdx);
        parseConfigParam342(boc, configParamsIdx, treeOfCells);
    }

    function parseConfigParam342(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) public {
        // for (uint16 i = 17; i < 1024; i++) {
        uint256 skipped = readUint(data, cells, cellIdx, 28);
        // console.log("skipped", i, skipped);
        uint8 cType = readUint8(data, cells, cellIdx, 8);
        console.log("cType", cType);
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
        // totalWeight = 0;
        console.log("cellIdx", cellIdx);
        console.log(utime_since);
        console.log(utime_until);
        console.log(total);
        console.log(main);

        // if (cType == 0x12) {
        //     totalWeight = readUint64(data, cells, cellIdx, 64);
        // }
        // console.log(totalWeight);
        uint256 subcellIdx = readCell(cells, cellIdx);
        console.log("cell", subcellIdx);

        /////////////////////////////
        console.log("start reading hashmap of config params 34");
        uint256[32] memory txIdxs = parseDict2(
            data,
            cells,
            readCell(cells, subcellIdx),
            16
        );
        console.log("finish reading hashmap of config params 34");
        /////////////////////////////
        // uint256[32] memory txIdxs = parseDict(
        //     data,
        //     cells,
        //     readCell(cells, subcellIdx),
        //     16
        // );

        // console.log("list of items");
        // // ValidatorDescription[32] memory validators;
        // for (uint256 i = 0; i < 32; i++) {
        //     if (txIdxs[i] == 255) {
        //         break;
        //     }
        //     validators[i] = readValidatorDescription(data, txIdxs[i], cells);
        //     // console.log("id", i, txIdxs[i]);
        // }
        // return validators;
        ValidatorDescription[32] memory validators;
        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            validators[i] = readValidatorDescription(data, txIdxs[i], cells);
            // console.log("id", i, txIdxs[i]);
        }
        for (uint256 i = 0; i < 32; i++) {
            for (uint256 j = 0; j < 100; j++) {
                // is empty
                if (candidatesForValidatorSet[j].weight == 0) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesForValidatorSet[j] = validators[i];
                    candidatesForValidatorSet[j].node_id = computeNodeId(
                        candidatesForValidatorSet[j].pubkey
                    );
                    break;
                }
                // old validator has less weight then new
                if (
                    candidatesForValidatorSet[j].weight < validators[i].weight
                ) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesTotalWeight -= candidatesForValidatorSet[j]
                        .weight;

                    ValidatorDescription memory tmp = candidatesForValidatorSet[
                        j
                    ];
                    candidatesForValidatorSet[j] = validators[i];
                    validators[i] = tmp;

                    candidatesForValidatorSet[j].node_id = computeNodeId(
                        candidatesForValidatorSet[j].pubkey
                    );
                }
            }
        }
    }

    function parsePartValidators(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) public {
        bool valid = false;
        uint256 prefixLength = 0;
        for (uint256 i = 0; i < 10; i++) {
            if (prunedCells[i].hash == cells[cellIdx]._hash[0]) {
                valid = true;
                prefixLength = prunedCells[i].prefixLength;
                delete prunedCells[i];
                break;
            }
        }
        require(valid, "Wrong boc for validators");
        uint256[32] memory txIdxs = parseDict(data, cells, cellIdx, 5);

        ValidatorDescription[32] memory validators;
        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            validators[i] = readValidatorDescription(data, txIdxs[i], cells);
            // console.log("id", i, txIdxs[i]);
        }
        for (uint256 i = 0; i < 32; i++) {
            for (uint256 j = 0; j < 100; j++) {
                // is empty
                if (candidatesForValidatorSet[j].weight == 0) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesForValidatorSet[j] = validators[i];
                    candidatesForValidatorSet[j].node_id = computeNodeId(
                        candidatesForValidatorSet[j].pubkey
                    );
                    break;
                }
                // old validator has less weight then new
                if (
                    candidatesForValidatorSet[j].weight < validators[i].weight
                ) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesTotalWeight -= candidatesForValidatorSet[j]
                        .weight;

                    ValidatorDescription memory tmp = candidatesForValidatorSet[
                        j
                    ];
                    candidatesForValidatorSet[j] = validators[i];
                    validators[i] = tmp;

                    candidatesForValidatorSet[j].node_id = computeNodeId(
                        candidatesForValidatorSet[j].pubkey
                    );
                }
            }
        }

        // if it is last validators boc, try to set validators;
        // bool isEmpty = true;
        // for (uint256 i = 0; i < 10; i++) {
        //     if (prunedCells[i].prefixLength != 0) {
        //         isEmpty = false;
        //         break;
        //     }
        // }
        // console.log("IS EMPTY:", isEmpty);
        // if (isEmpty) {
        //     setValidatorSet();
        // }
    }

    function parse_block(
        bytes calldata proofBoc,
        BagOfCellsInfo memory proofBocInfo,
        CellData[100] memory proofTreeOfCells,
        bytes32 txRootHash,
        TransactionHeader memory transaction
    ) public view returns (bool) {
        uint256 proofRootIdx = proofBocInfo.cell_count -
            readInt(
                proofBoc[proofBocInfo.roots_offset:],
                proofBocInfo.ref_byte_size
            ) -
            1;

        require(
            isVerifiedBlock(proofTreeOfCells[proofRootIdx]._hash[0]),
            "block is not verified"
        );
        uint32 tag = readUint32(proofBoc, proofTreeOfCells, proofRootIdx, 32);
        // console.log("GlobalId:", tag);
        // blockInfo^ (pruned)
        uint256 blockInfoIdx = readCell(proofTreeOfCells, proofRootIdx);
        // require(check_block_info(proofTreeOfCells, blockInfoIdx, transaction), "lt doesn't belong to block interval");
        // value flow^ (pruned)
        readCell(proofTreeOfCells, proofRootIdx);
        // state_update^ (pruned)
        readCell(proofTreeOfCells, proofRootIdx);
        uint256 extraIdx = readCell(proofTreeOfCells, proofRootIdx);

        return
            parse_block_extra(
                proofBoc,
                proofTreeOfCells,
                extraIdx,
                txRootHash,
                transaction
            );
    }

    function readUintLeq(
        bytes calldata proofBoc,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 n
    ) public view returns (uint256) {
        uint16 last_one = 0;
        uint256 l = 1;
        bool found = false;
        for (uint16 i = 0; i < 32; i++) {
            if ((n & l) > 0) {
                last_one = i;
                found = true;
            }
            l = l << 1;
        }
        require(found, "not a UintLe");
        last_one++;
        return readUint(proofBoc, cells, cellIdx, last_one);
    }

    function check_block_info(
        bytes calldata proofBoc,
        CellData[100] memory cells,
        uint256 cellIdx,
        TransactionHeader memory transaction
    ) public view returns (bool) {
        require(
            readUint32(proofBoc, cells, cellIdx, 32) == 0x9bc7a987,
            "not a BlockInfo"
        );
        // // version
        // readUint32(cells, cellIdx, 32);
        // // not_master
        // readBool(cells, cellIdx);
        // // after_merge
        // readBool(cells, cellIdx);
        // // before_split
        // readBool(cells, cellIdx);
        // // after_split
        // readBool(cells, cellIdx);
        // // want_split
        // readBool(cells, cellIdx);
        // // want merge
        // readBool(cells, cellIdx);
        // // key_block
        // readBool(cells, cellIdx);
        // // vert seqno incer
        // readBool(cells, cellIdx);
        cells[cellIdx].cursor += 32 + 1 * 8;
        // flags
        require(readUint8(proofBoc, cells, cellIdx, 8) <= 1, "data.flags > 1");
        // seq_no
        // readUint32(cells, cellIdx, 32);
        // vert_seq_no
        // readUint32(cells, cellIdx, 32);
        cells[cellIdx].cursor += 64;
        // shard Ident
        readUint8(proofBoc, cells, cellIdx, 2);
        readUintLeq(proofBoc, cells, cellIdx, 60);
        readUint32(proofBoc, cells, cellIdx, 32);
        readUint64(proofBoc, cells, cellIdx, 64);

        // end shard Ident

        // gen_utime
        readUint32(proofBoc, cells, cellIdx, 32);

        uint64 start_lt = readUint64(proofBoc, cells, cellIdx, 64);
        uint64 end_lt = readUint64(proofBoc, cells, cellIdx, 64);

        return transaction.lt >= start_lt || transaction.lt <= end_lt;
    }

    function parse_block_extra(
        bytes calldata proofBoc,
        CellData[100] memory cells,
        uint256 cellIdx,
        bytes32 txRootHash,
        TransactionHeader memory transaction
    ) public view returns (bool) {
        uint32 isBlockExtra = readUint32(proofBoc, cells, cellIdx, 32);
        require(isBlockExtra == 1244919549, "cell is not extra block info");

        // in_msg_descr^ (pruned)
        readCell(cells, cellIdx);
        // out_msg_descr^ (pruned)
        readCell(cells, cellIdx);
        // account_blocks^
        uint256 account_blocksIdx = readCell(cells, readCell(cells, cellIdx));
        // console.log("PARSE WORKS 1");
        uint256[32] memory accountIdxs = parseDict(
            proofBoc,
            cells,
            account_blocksIdx,
            256
        );
        // console.log("PARSE WORKS 2");
        for (uint256 i = 0; i < 32; i++) {
            if (accountIdxs[i] == 255) {
                break;
            }
            // _ (HashmapAugE 256 AccountBlock CurrencyCollection) = ShardAccountBlocks;
            parseCurrencyCollection(proofBoc, cells, accountIdxs[i]);
            require(
                readUint8(proofBoc, cells, accountIdxs[i], 4) == 5,
                "is not account block"
            );
            bytes32 addressHash = readBytes32ByteSize(
                proofBoc,
                cells,
                accountIdxs[i],
                32
            );

            if (addressHash != transaction.addressHash) {
                continue;
            }

            // get transactions of this account
            uint256[32] memory txIdxs = parseDict(
                proofBoc,
                cells,
                accountIdxs[i],
                64
            );
            for (uint256 j = 0; j < 32; j++) {
                if (txIdxs[j] == 255) {
                    break;
                }
                if (cells[readCell(cells, txIdxs[j])]._hash[0] == txRootHash) {
                    return true;
                }
            }
        }
        return false;
    }

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

    function parseCurrencyCollection(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public view returns (bytes32 coins) {
        coins = readCoins(data, cells, cellIdx);
        bool check = readBool(data, cells, cellIdx);
        if (check) {
            uint256 dcIdx = readCell(cells, cellIdx);
            if (!cells[dcIdx].special) {
                parseDict(data, cells, dcIdx, 32);
            }
        }

        return coins;
    }

    function readCoins(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32 value) {
        uint8 Bytes = readUint8(data, cells, cellIdx, 4);

        if (Bytes == 0) {
            return bytes32(0);
        }
        return readBytes32ByteSize(data, cells, cellIdx, Bytes);
    }

    function parseShardProofPath(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    ) public {
        // check root cell is special
        require(toc[rootIdx].special, "root is not exotic");
        uint256 cellIdx = toc[rootIdx].refs[0];
        require(isVerifiedBlock(toc[cellIdx]._hash[0]), "Not verified");
        // block skip cells
        cellIdx = toc[cellIdx].refs[3];
        cellIdx = toc[cellIdx].refs[3];
        cellIdx = toc[cellIdx].refs[0];

        // require(0xcc26 == readUint16(boc, toc, cellIdx, 16), "not a McStateExtra");

        uint256[32] memory txIdxs = parseDict(boc, toc, cellIdx, 32);

        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            // todo: loop for loadBinTree
            uint256[32] memory binTreeCells;
            binTreeCells[0] = txIdxs[i];
            uint256 j = 0;
            while (binTreeCells[0] != 0) {
                uint256 leafIdx = binTreeCells[j]; // toc[txIdxs[i]].refs[0];
                binTreeCells[j] = 0;

                // console.log("test for leaf Idx:", leafIdx);
                if (readBit(boc, toc, leafIdx) == 0) {
                    // console.log("leafIdx:", leafIdx);
                    uint8 dType = readUint8(boc, toc, leafIdx, 4);

                    require(dType == 0xa || dType == 0xb, "not a ShardDescr");

                    VerifiedBlockInfo memory new_block_info = VerifiedBlockInfo(
                        true,
                        readUint32(boc, toc, leafIdx, 32),
                        0,
                        0,
                        0
                    );

                    // uint32 seq_no = readUint32(boc, toc, leafIdx, 32);
                    // uint32 req_mc_seqno =
                    readUint32(boc, toc, leafIdx, 32);
                    new_block_info.start_lt = readUint64(boc, toc, leafIdx, 64);
                    new_block_info.end_lt = readUint64(boc, toc, leafIdx, 64);
                    bytes32 root_hash = readBytes32BitSize(
                        boc,
                        toc,
                        leafIdx,
                        256
                    );
                    // bytes32 file_hash = readBytes32BitSize(
                    //     boc,
                    //     toc,
                    //     leafIdx,
                    //     256
                    // );

                    // console.log("new verified block added:");
                    // console.logBytes32(root_hash);
                    verifiedBlocks[root_hash] = new_block_info;

                    // console.log("seq_no", new_block_info.seq_no);
                    // console.log("req_mc_seqno", req_mc_seqno);
                    // console.log("start_lt", new_block_info.start_lt);
                    // console.log("end_lt", new_block_info.end_lt);
                    // console.log("root_hash:");
                    // console.logBytes32(root_hash);
                    // console.log("file_hash:");
                    // console.logBytes32(file_hash);
                } else {
                    if (toc[leafIdx].refs[0] != 255) {
                        // j += 1;
                        binTreeCells[j] = toc[leafIdx].refs[0];
                    }
                    if (toc[leafIdx].refs[1] != 255) {
                        j += 1;
                        binTreeCells[j] = toc[leafIdx].refs[1];
                    }
                }
                if (j > 0 && binTreeCells[j] == 0) {
                    j--;
                }
            }
        }
    }

    function addPrevBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    ) public {
        // check root cell is special
        require(toc[rootIdx].special, "root is not exotic");
        uint256 cellIdx = toc[rootIdx].refs[0];
        require(isVerifiedBlock(toc[cellIdx]._hash[0]), "Not verified");
        cellIdx = toc[cellIdx].refs[0];

        require(
            readUint32(boc, toc, cellIdx, 32) == 0x9bc7a987,
            "not a BlockInfo"
        );
        readUint32(boc, toc, cellIdx, 32);
        bool not_master = readBool(boc, toc, cellIdx);
        bool after_merge = readBool(boc, toc, cellIdx);
        console.log("MASTER AFTER MERGE flags:", not_master, after_merge);

        cellIdx = not_master ? toc[cellIdx].refs[1] : toc[cellIdx].refs[0];

        if (!after_merge) {
            {
                uint64 end_lt = readUint64(boc, toc, cellIdx, 64);
                uint32 seq_no = readUint32(boc, toc, cellIdx, 32);
                bytes32 root_hash = readBytes32BitSize(boc, toc, cellIdx, 256);
                verifiedBlocks[root_hash] = VerifiedBlockInfo(
                    true,
                    seq_no,
                    0,
                    end_lt,
                    0
                );
                console.log("aded block with root_hash");
                console.logBytes32(root_hash);
            }
            // data.prev = loadExtBlkRef(cell, t);
        } else {
            {
                if (toc[cellIdx].refs[0] != 255) {
                    uint64 end_lt = readUint64(
                        boc,
                        toc,
                        toc[cellIdx].refs[0],
                        64
                    );
                    uint32 seq_no = readUint32(
                        boc,
                        toc,
                        toc[cellIdx].refs[0],
                        32
                    );

                    bytes32 root_hash = readBytes32BitSize(
                        boc,
                        toc,
                        toc[cellIdx].refs[0],
                        256
                    );
                    verifiedBlocks[root_hash] = VerifiedBlockInfo(
                        true,
                        seq_no,
                        0,
                        end_lt,
                        0
                    );
                    console.log("aded block with root_hash");
                    console.logBytes32(root_hash);
                }
            }
            {
                if (toc[cellIdx].refs[1] != 255) {
                    uint64 end_lt = readUint64(
                        boc,
                        toc,
                        toc[cellIdx].refs[1],
                        64
                    );
                    uint32 seq_no = readUint32(
                        boc,
                        toc,
                        toc[cellIdx].refs[1],
                        32
                    );
                    bytes32 root_hash = readBytes32BitSize(
                        boc,
                        toc,
                        toc[cellIdx].refs[1],
                        256
                    );
                    verifiedBlocks[root_hash] = VerifiedBlockInfo(
                        true,
                        seq_no,
                        0,
                        end_lt,
                        0
                    );
                    console.log("aded block with root_hash");
                    console.logBytes32(root_hash);
                }
            }
            // data.prev1 = loadRefIfExist(cell, t, loadExtBlkRef);
            // data.prev2 = loadRefIfExist(cell, t, loadExtBlkRef);
        }
    }

    function readMasterProof(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    ) public {
        require(
            isVerifiedBlock(toc[rootIdx]._hash[0]),
            "Block is not verified"
        );

        // extra
        uint256 cellIdx = toc[rootIdx].refs[2];
        console.log("test", readUint8(boc, toc, cellIdx, 8));
        bytes32 old_hash = readBytes32BitSize(boc, toc, cellIdx, 256);
        bytes32 new_hash = readBytes32BitSize(boc, toc, cellIdx, 256);

        verifiedBlocks[toc[rootIdx]._hash[0]].new_hash = new_hash;
    }

    function readStateProof(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc,
        bytes32 root_hash
    ) public {
        console.log("hashes");
        console.logBytes32(toc[rootIdx]._hash[0]);
        console.logBytes32(verifiedBlocks[root_hash].new_hash);

        require(
            toc[rootIdx]._hash[0] == verifiedBlocks[root_hash].new_hash,
            "Block with new hash is not verified"
        );

        // console.logBytes32(toc[rootIdx]._hash[0]);

        require(
            readUint32(boc, toc, rootIdx, 32) == 0x9023afe2,
            "not a ShardStateUnsplit"
        );

        // custom
        uint256 cellIdx = toc[rootIdx].refs[3];
        require(
            readUint16(boc, toc, cellIdx, 16) == 0xcc26,
            "not a McStateExtra"
        );

        // prev_blocks
        cellIdx = toc[cellIdx].refs[2];

        console.log("start cell for parse:", cellIdx);
        uint256[32] memory txIdxs = parseDict(boc, toc, cellIdx, 30);

        console.log("parse ended");

        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            console.log("found:", txIdxs[i], toc[txIdxs[i]].cursor);
            toc[txIdxs[i]].cursor += 66;

            uint64 end_lt = readUint64(boc, toc, txIdxs[i], 64);
            uint32 seq_no = readUint32(boc, toc, txIdxs[i], 32);
            bytes32 blk_root_hash = readBytes32BitSize(
                boc,
                toc,
                txIdxs[i],
                256
            );
            bytes32 blk_file_hash = readBytes32BitSize(
                boc,
                toc,
                txIdxs[i],
                256
            );

            verifiedBlocks[blk_root_hash] = VerifiedBlockInfo(
                true,
                seq_no,
                0,
                end_lt,
                blk_file_hash
            );
            console.log("blk root hash:");
            console.logBytes32(blk_root_hash);
        }

        // require(state_hash == verifiedBlocks[toc[rootIdx]._hash[0]].new_hash);

        // state_hash -> -> addToVerifiedBlocks[cell (list) .blk_ref]
    }
}
