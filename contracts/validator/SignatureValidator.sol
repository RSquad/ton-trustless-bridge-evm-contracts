//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BlockTypes.sol";
import "../libraries/Ed25519.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../parser/BitReader.sol";
import "../parser/BlockParser.sol";

interface ISignatureValidator {
    function getPrunedCells() external view returns (CachedCell[10] memory);

    function addCurrentBlockToVerifiedSet(bytes32 root_h)
        external
        view
        returns (bytes32);

    // function setRootHashForValidating(bytes32 rh) external;

    function verifyValidators(
        bytes32 root_h,
        bytes32 file_hash,
        Vdata[20] calldata vdata
    ) external;

    function getValidators()
        external
        view
        returns (ValidatorDescription[100] memory);

    function getCandidatesForValidators()
        external
        view
        returns (ValidatorDescription[100] memory);

    function setValidatorSet() external returns (bytes32);

    function parseCandidatesRootBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) external;

    function parsePartValidators(
        bytes calldata data,
        uint256 cellIdx,
        CellData[100] memory cells
    ) external;

    function isSignedByValidator(bytes32 node_id, bytes32 root_h)
        external
        view
        returns (bool);

    function initValidators() external returns (bytes32);
}

contract SignatureValidator is ISignatureValidator, Ownable {
    ValidatorDescription[100] private validatorSet;
    uint64 private totalWeight = 0;

    CachedCell[10] private prunedCells;
    ValidatorDescription[100] private candidatesForValidatorSet;
    uint64 private candidatesTotalWeight = 0;

    bytes32 private root_hash;

    IBlockParser private blockParser;

    mapping(bytes32 => mapping(bytes32 => bool)) signedBlocks;

    constructor(address blockParserAddr) {
        blockParser = IBlockParser(blockParserAddr);
    }

    function isSignedByValidator(bytes32 node_id, bytes32 root_h)
        public
        view
        returns (bool)
    {
        return signedBlocks[node_id][root_h];
    }

    function getPrunedCells() public view returns (CachedCell[10] memory) {
        return prunedCells;
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

    // function setRootHashForValidating(bytes32 rh) public {
    //     root_hash = rh;
    // }

    function addCurrentBlockToVerifiedSet(bytes32 root_h)
        public
        view
        returns (bytes32)
    {
        uint64 currentWeight = 0;
        for (uint256 j = 0; j < validatorSet.length; j++) {
            if (signedBlocks[validatorSet[j].node_id][root_h]) {
                currentWeight += validatorSet[j].weight;
            }
        }

        require(currentWeight * 3 > totalWeight * 2, "not enought votes");

        return root_hash;
    }

    function verifyValidators(
        bytes32 root_h,
        bytes32 file_hash,
        Vdata[20] calldata vdata
    ) public {
        bytes32 test_root_hash = root_hash == 0 ? root_h : root_hash;

        require(
            test_root_hash != 0 && file_hash != 0,
            "wrong root_hash or file_hash"
        );

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
            if (
                Ed25519.verify(
                    validatorSet[validatodIdx].pubkey,
                    vdata[i].r,
                    vdata[i].s,
                    bytes.concat(bytes4(0x706e0bc5), test_root_hash, file_hash)
                )
            ) {
                signedBlocks[validatorSet[validatodIdx].node_id][
                    test_root_hash
                ] = true;
            }
        }
    }

    function initValidators() public onlyOwner returns (bytes32) {
        require(validatorSet[0].weight == 0, "current validators not empty");

        validatorSet = candidatesForValidatorSet;
        delete candidatesForValidatorSet;

        totalWeight = candidatesTotalWeight;
        candidatesTotalWeight = 0;
        bytes32 rh = root_hash;
        root_hash = 0;

        return (rh);
    }

    function setValidatorSet() public returns (bytes32) {
        // if current validatorSet is empty, check caller
        // else check votes
        require(validatorSet[0].weight != 0);

        // check all pruned cells are empty
        for (uint256 i = 0; i < prunedCells.length; i++) {
            require(prunedCells[i].hash == 0, "need read all validators");
        }

        uint64 currentWeight = 0;
        for (uint256 j = 0; j < validatorSet.length; j++) {
            if (signedBlocks[validatorSet[j].node_id][root_hash]) {
                currentWeight += validatorSet[j].weight;
            }
        }

        require(currentWeight * 3 > totalWeight * 2, "not enought votes");

        validatorSet = candidatesForValidatorSet;
        delete candidatesForValidatorSet;

        totalWeight = candidatesTotalWeight;
        candidatesTotalWeight = 0;
        bytes32 rh = root_hash;
        root_hash = 0;

        return (rh);
    }

    function parseCandidatesRootBlock(
        bytes calldata boc,
        uint256 rootIdx,
        CellData[100] memory treeOfCells
    ) public {
        delete candidatesForValidatorSet;
        candidatesTotalWeight = 0;
        delete prunedCells;
        root_hash = treeOfCells[rootIdx]._hash[0];

        ValidatorDescription[32] memory validators = blockParser
            .parseCandidatesRootBlock(boc, rootIdx, treeOfCells);

        for (uint256 i = 0; i < 32; i++) {
            for (uint256 j = 0; j < 100; j++) {
                // is empty
                if (candidatesForValidatorSet[j].weight == 0) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesForValidatorSet[j] = validators[i];
                    candidatesForValidatorSet[j].node_id = blockParser
                        .computeNodeId(candidatesForValidatorSet[j].pubkey);
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

                    candidatesForValidatorSet[j].node_id = blockParser
                        .computeNodeId(candidatesForValidatorSet[j].pubkey);
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

        ValidatorDescription[32] memory validators = blockParser
            .parsePartValidators(data, cellIdx, cells, prefixLength);

        for (uint256 i = 0; i < 32; i++) {
            for (uint256 j = 0; j < 100; j++) {
                // is empty
                if (candidatesForValidatorSet[j].weight == 0) {
                    candidatesTotalWeight += validators[i].weight;
                    candidatesForValidatorSet[j] = validators[i];
                    candidatesForValidatorSet[j].node_id = blockParser
                        .computeNodeId(candidatesForValidatorSet[j].pubkey);
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

                    candidatesForValidatorSet[j].node_id = blockParser
                        .computeNodeId(candidatesForValidatorSet[j].pubkey);
                }
            }
        }
    }
}
