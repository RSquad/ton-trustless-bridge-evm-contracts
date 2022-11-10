//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BagOfCellsInfo.sol";
import "../parser/BitReader.sol";
import "../types/TransactionTypes.sol";
import "../types/BlockTypes.sol";

interface IBlockParser {
    function parseCandidatesRootBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) external returns (ValidatorDescription[32] memory);

    function parsePartValidators(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells,
        uint256 prefixLength
    ) external view returns (ValidatorDescription[32] memory);

    function parse_block(
        bytes calldata proofBoc,
        BagOfCellsInfo memory proofBocInfo,
        CellData[100] memory proofTreeOfCells,
        bytes32 txRootHash,
        TransactionHeader memory transaction
    ) external view returns (bool);

    function computeNodeId(bytes32 publicKey) external pure returns (bytes32);
}

contract BlockParser is BitReader, IBlockParser {
    function computeNodeId(bytes32 publicKey) public pure returns (bytes32) {
        return sha256(bytes.concat(bytes4(0xc6b41348), publicKey));
    }

    function readValidatorDescription(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) private pure returns (ValidatorDescription memory validator) {
        validator.cType = readUint8(data, cells, cellIdx, 8);

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
    )
        private
        returns (uint256[32] memory cellIdxs, CachedCell[10] memory prunedCells)
    {
        for (uint256 i = 0; i < 32; i++) {
            cellIdxs[i] = 255;
        }
        doParse2(data, 0, cells, cellIdx, keySize, cellIdxs, prunedCells);
        return (cellIdxs, prunedCells);
    }

    function doParse2(
        bytes calldata data,
        uint256 prefix,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 n,
        uint256[32] memory cellIdxs,
        CachedCell[10] memory prunedCells
    ) private {
        uint256 prefixLength = 0;
        uint256 pp = prefix;

        // lb0
        if (!readBool(data, cells, cellIdx)) {
            // Short label detected
            prefixLength = readUnaryLength(data, cells, cellIdx);

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
            
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + bit;
                }
            }
        }
        
        if (n - prefixLength == 0) {
            
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
            
            // NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (leftIdx != 255 && !cells[leftIdx].special) {
                doParse2(
                    data,
                    pp << 1,
                    cells,
                    leftIdx,
                    n - prefixLength - 1,
                    cellIdxs,
                    prunedCells
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
                    cellIdxs,
                    prunedCells
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
    ) public returns (ValidatorDescription[32] memory) {
        // uint32 tag = 
        readUint32(boc, treeOfCells, rootIdx, 32);

        // extra
        uint256 cellIdx = treeOfCells[rootIdx].refs[3];

        uint32 test = readUint32(boc, treeOfCells, cellIdx, 32);
        require(test == 0x4a33f6fd, "not a BlockExtra");

        // McBlockExtra
        cellIdx = treeOfCells[cellIdx].refs[3];
        require(cellIdx != 255, "No McBlockExtra");

        require(
            readUint16(boc, treeOfCells, cellIdx, 16) == 0xcca5,
            "not a McBlockExtra"
        );

        bool isKeyBlock = readBool(boc, treeOfCells, cellIdx);

        if (isKeyBlock) {
            // config params
            // skip useless data TODO: check tlb for this struct
            // treeOfCells[cellIdx].cursor += 76
            treeOfCells[cellIdx].cursor += 8 + 4;
            // readBytes32BitSize(boc, treeOfCells, cellIdx, 76);
            // bytes32 configAddress = 
            readBytes32BitSize(
                boc,
                treeOfCells,
                cellIdx,
                256
            );
            
            uint256 configParamsIdx = treeOfCells[cellIdx].refs[3] == 255
                ? treeOfCells[cellIdx].refs[2]
                : treeOfCells[cellIdx].refs[3];

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

            return parseConfigParam342(boc, configParamsIdx, treeOfCells);
        }

        require(false, "is no key block");
        // will never runs
        ValidatorDescription[32] memory nullValidators;
        return nullValidators;
    }

    function parseConfigParam342(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) private returns (ValidatorDescription[32] memory validators) {
        // uint256 skipped = 
        readUint(data, cells, cellIdx, 28);
        // uint8 cType = 
        readUint8(data, cells, cellIdx, 8);

        // uint32 utime_since = 
        readUint32(data, cells, cellIdx, 32);
        // uint32 utime_until = 
        readUint32(data, cells, cellIdx, 32);
        // uint16 total = 
        readUint16(data, cells, cellIdx, 16);
        // uint16 main = 
        readUint16(data, cells, cellIdx, 16);

        uint256 subcellIdx = readCell(cells, cellIdx);

        CachedCell[10] memory prunedCells;
        uint256[32] memory txIdxs;
        (txIdxs, prunedCells) = parseDict2(
            data,
            cells,
            readCell(cells, subcellIdx),
            16
        );

        // ValidatorDescription[32] memory validators;
        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            validators[i] = readValidatorDescription(data, txIdxs[i], cells);
        }

        return validators;
        // for (uint256 i = 0; i < 32; i++) {
        //     for (uint256 j = 0; j < 100; j++) {
        //         // is empty
        //         if (candidatesForValidatorSet[j].weight == 0) {
        //             candidatesTotalWeight += validators[i].weight;
        //             candidatesForValidatorSet[j] = validators[i];
        //             candidatesForValidatorSet[j].node_id = computeNodeId(
        //                 candidatesForValidatorSet[j].pubkey
        //             );
        //             break;
        //         }
        //         // old validator has less weight then new
        //         if (
        //             candidatesForValidatorSet[j].weight < validators[i].weight
        //         ) {
        //             candidatesTotalWeight += validators[i].weight;
        //             candidatesTotalWeight -= candidatesForValidatorSet[j]
        //                 .weight;

        //             ValidatorDescription memory tmp = candidatesForValidatorSet[
        //                 j
        //             ];
        //             candidatesForValidatorSet[j] = validators[i];
        //             validators[i] = tmp;

        //             candidatesForValidatorSet[j].node_id = computeNodeId(
        //                 candidatesForValidatorSet[j].pubkey
        //             );
        //         }
        //     }
        // }
    }

    function parsePartValidators(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells,
        uint256 prefixLength
    ) public view returns (ValidatorDescription[32] memory validators) {
        
        uint256[32] memory txIdxs = parseDict(data, cells, cellIdx, prefixLength);

        // ValidatorDescription[32] memory validators;
        for (uint256 i = 0; i < 32; i++) {
            if (txIdxs[i] == 255) {
                break;
            }
            validators[i] = readValidatorDescription(data, txIdxs[i], cells);
            
        }

        return validators;
        // for (uint256 i = 0; i < 32; i++) {
        //     for (uint256 j = 0; j < 100; j++) {
        //         // is empty
        //         if (candidatesForValidatorSet[j].weight == 0) {
        //             candidatesTotalWeight += validators[i].weight;
        //             candidatesForValidatorSet[j] = validators[i];
        //             candidatesForValidatorSet[j].node_id = computeNodeId(
        //                 candidatesForValidatorSet[j].pubkey
        //             );
        //             break;
        //         }
        //         // old validator has less weight then new
        //         if (
        //             candidatesForValidatorSet[j].weight < validators[i].weight
        //         ) {
        //             candidatesTotalWeight += validators[i].weight;
        //             candidatesTotalWeight -= candidatesForValidatorSet[j]
        //                 .weight;

        //             ValidatorDescription memory tmp = candidatesForValidatorSet[
        //                 j
        //             ];
        //             candidatesForValidatorSet[j] = validators[i];
        //             validators[i] = tmp;

        //             candidatesForValidatorSet[j].node_id = computeNodeId(
        //                 candidatesForValidatorSet[j].pubkey
        //             );
        //         }
        //     }
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

        // require(
        //     isVerifiedBlock(proofTreeOfCells[proofRootIdx]._hash[0]),
        //     "block is not verified"
        // );
        // uint32 tag = 
        readUint32(proofBoc, proofTreeOfCells, proofRootIdx, 32);
        
        // blockInfo^ (pruned)
        // uint256 blockInfoIdx = 
        readCell(proofTreeOfCells, proofRootIdx);
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
    ) public pure returns (uint256) {
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
    ) public pure returns (bool) {
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
        
        uint256[32] memory accountIdxs = parseDict(
            proofBoc,
            cells,
            account_blocksIdx,
            256
        );
        
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
}
