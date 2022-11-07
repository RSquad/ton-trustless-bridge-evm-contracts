//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BlockTypes.sol";
import "../libraries/Ed25519.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../parser/BitReader.sol";

interface IShardValidator {
    function parseShardProofPath(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    )
        external
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        );

    function addPrevBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    )
        external
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        );

    function readMasterProof(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    ) external view returns (bytes32 new_hash);

    function readStateProof(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
        // bytes32 root_hash
    )
        external
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        );
}

contract ShardValidator is BitReader, IShardValidator {
    function parseShardProofPath(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
    )
        public
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        )
    {
        uint256 free_i = 0;
        // check root cell is special
        require(toc[rootIdx].special, "root is not exotic");
        uint256 cellIdx = toc[rootIdx].refs[0];
        // require(isVerifiedBlock(toc[cellIdx]._hash[0]), "Not verified");
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

                    if (free_i < 10) {

                    blocks[free_i].verified = true;
                    blocks[free_i].seq_no = readUint32(boc, toc, leafIdx, 32);

                    // uint32 seq_no = readUint32(boc, toc, leafIdx, 32);
                    // uint32 req_mc_seqno =
                    readUint32(boc, toc, leafIdx, 32);
                    blocks[free_i].start_lt = readUint64(boc, toc, leafIdx, 64);
                    blocks[free_i].end_lt = readUint64(boc, toc, leafIdx, 64);
                    root_hashes[free_i] = readBytes32BitSize(
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
                        
                        free_i++;
                    }
                    // verifiedBlocks[root_hash] = new_block_info;
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
    )
        public
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        )
    {
        uint256 free_i = 0;
        // check root cell is special
        require(toc[rootIdx].special, "root is not exotic");
        uint256 cellIdx = toc[rootIdx].refs[0];
        // require(isVerifiedBlock(toc[cellIdx]._hash[0]), "Not verified");
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

                // verifiedBlocks[root_hash] = VerifiedBlockInfo(
                //     true,
                //     seq_no,
                //     0,
                //     end_lt,
                //     0
                // );
                if (free_i < 10) {
                    root_hashes[free_i] = root_hash;
                    blocks[free_i] = VerifiedBlockInfo(
                        true,
                        seq_no,
                        0,
                        end_lt,
                        0
                    );
                    free_i++;
                }
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
                    // verifiedBlocks[root_hash] = VerifiedBlockInfo(
                    //     true,
                    //     seq_no,
                    //     0,
                    //     end_lt,
                    //     0
                    // );
                    if (free_i < 10) {
                        root_hashes[free_i] = root_hash;
                        blocks[free_i] = VerifiedBlockInfo(
                            true,
                            seq_no,
                            0,
                            end_lt,
                            0
                        );
                        free_i++;
                    }
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
                    // verifiedBlocks[root_hash] = VerifiedBlockInfo(
                    //     true,
                    //     seq_no,
                    //     0,
                    //     end_lt,
                    //     0
                    // );
                    if (free_i < 10) {
                        root_hashes[free_i] = root_hash;
                        blocks[free_i] = VerifiedBlockInfo(
                            true,
                            seq_no,
                            0,
                            end_lt,
                            0
                        );
                        free_i++;
                    }
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
    ) public view returns (bytes32 new_hash) {
        // require(
        //     isVerifiedBlock(toc[rootIdx]._hash[0]),
        //     "Block is not verified"
        // );

        // extra
        uint256 cellIdx = toc[rootIdx].refs[2];
        console.log("test", readUint8(boc, toc, cellIdx, 8));
        bytes32 old_hash = readBytes32BitSize(boc, toc, cellIdx, 256);
        new_hash = readBytes32BitSize(boc, toc, cellIdx, 256);

        // verifiedBlocks[toc[rootIdx]._hash[0]].new_hash = new_hash;
    }

    function readStateProof(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory toc
        // bytes32 root_hash
    )
        public
        view
        returns (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        )
    {
        uint256 free_i = 0;
        // console.log("hashes");
        // console.logBytes32(toc[rootIdx]._hash[0]);
        // console.logBytes32(verifiedBlocks[root_hash].new_hash);

        // require(
        //     toc[rootIdx]._hash[0] == verifiedBlocks[root_hash].new_hash,
        //     "Block with new hash is not verified"
        // );

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

            // verifiedBlocks[blk_root_hash] = VerifiedBlockInfo(
            //     true,
            //     seq_no,
            //     0,
            //     end_lt,
            //     blk_file_hash
            // );
            if (free_i < 10) {
                root_hashes[free_i] = blk_root_hash;
                blocks[free_i] = VerifiedBlockInfo(
                    true,
                    seq_no,
                    0,
                    end_lt,
                    blk_file_hash
                );
                free_i++;
            }
            console.log("blk root hash:");
            console.logBytes32(blk_root_hash);
        }

        // require(state_hash == verifiedBlocks[toc[rootIdx]._hash[0]].new_hash);

        // state_hash -> -> addToVerifiedBlocks[cell (list) .blk_ref]
    }
}
