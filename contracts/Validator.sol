//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./types/BlockTypes.sol";
import "./validator/SignatureValidator.sol";
import "./parser/TreeOfCellsParser.sol";
import "./validator/ShardValidator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IValidator {
    function isVerifiedBlock(bytes32 rootHash) external view returns (bool);
}

contract Validator is IValidator, Ownable {
    mapping(bytes32 => VerifiedBlockInfo) verifiedBlocks;
    // bytes32 root_hash;

    ISignatureValidator signatureValidator;
    ITreeOfCellsParser tocParser;
    IShardValidator shardValidator;

    constructor(
        address signatureValidatorAddr,
        address shardValidatorAddr,
        address tocParserAddr
    ) {
        signatureValidator = ISignatureValidator(signatureValidatorAddr);
        tocParser = ITreeOfCellsParser(tocParserAddr);
        shardValidator = IShardValidator(shardValidatorAddr);
    }

    function isSignedByValidator(bytes32 node_id, bytes32 root_h) public view returns (bool) {
        return signatureValidator.isSignedByValidator(node_id, root_h);
    }    

    function isVerifiedBlock(bytes32 rootHash) public view returns (bool) {
        return verifiedBlocks[rootHash].verified;
    }

    function getPrunedCells() external view returns (CachedCell[10] memory) {
        return signatureValidator.getPrunedCells();
    }

    function getValidators()
        public
        view
        returns (ValidatorDescription[100] memory)
    {
        return signatureValidator.getValidators();
    }

    function getCandidatesForValidators()
        external
        view
        returns (ValidatorDescription[100] memory)
    {
        return signatureValidator.getCandidatesForValidators();
    }

    function parseCandidatesRootBlock(bytes calldata boc) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory treeOfCells = tocParser.get_tree_of_cells(
            boc,
            header
        );
        signatureValidator.parseCandidatesRootBlock(
            boc,
            header.rootIdx,
            treeOfCells
        );
    }

    function parsePartValidators(bytes calldata boc) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory treeOfCells = tocParser.get_tree_of_cells(
            boc,
            header
        );
        signatureValidator.parsePartValidators(
            boc,
            header.rootIdx,
            treeOfCells
        );
    }

    function initValidators() public onlyOwner {
        bytes32 key_block_root_hash = signatureValidator.initValidators();
        verifiedBlocks[key_block_root_hash] = VerifiedBlockInfo(
            true,
            0,
            0,
            0,
            0
        );
    }

    function setValidatorSet() public {
        bytes32 key_block_root_hash = signatureValidator.setValidatorSet();
        verifiedBlocks[key_block_root_hash] = VerifiedBlockInfo(
            true,
            0,
            0,
            0,
            0
        );
    }

    function verifyValidators(bytes32 root_h, bytes32 file_hash, Vdata[20] calldata vdata)
        public
    {
        signatureValidator.verifyValidators(root_h, file_hash, vdata);
    }

    // function setRootHashForValidating(bytes32 rh) public {
    //     signatureValidator.setRootHashForValidating(rh);
    // }

    function addCurrentBlockToVerifiedSet(bytes32 root_h) public {
        bytes32 rh = signatureValidator.addCurrentBlockToVerifiedSet(root_h);
        verifiedBlocks[rh] = VerifiedBlockInfo(true, 0, 0, 0, 0);
    }

    function parseShardProofPath(bytes calldata boc) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory toc = tocParser.get_tree_of_cells(boc, header);

        require(
            isVerifiedBlock(toc[toc[header.rootIdx].refs[0]]._hash[0]),
            "Not verified"
        );

        (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        ) = shardValidator.parseShardProofPath(boc, header.rootIdx, toc);

        for (uint256 i = 0; i < root_hashes.length; i++) {
            if (root_hashes[i] == 0) {
                break;
            }

            verifiedBlocks[root_hashes[i]] = blocks[i];
            
            
        }
    }

    function addPrevBlock(bytes calldata boc) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory toc = tocParser.get_tree_of_cells(boc, header);

        require(
            isVerifiedBlock(toc[toc[header.rootIdx].refs[0]]._hash[0]),
            "Not verified"
        );

        (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        ) = shardValidator.addPrevBlock(boc, header.rootIdx, toc);

        for (uint256 i = 0; i < root_hashes.length; i++) {
            if (root_hashes[i] == 0) {
                break;
            }

            verifiedBlocks[root_hashes[i]] = blocks[i];
        }
    }

    function readMasterProof(bytes calldata boc) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory toc = tocParser.get_tree_of_cells(boc, header);

        require(isVerifiedBlock(toc[header.rootIdx]._hash[0]), "Not verified");
        bytes32 new_hash = shardValidator.readMasterProof(
            boc,
            header.rootIdx,
            toc
        );

        verifiedBlocks[toc[header.rootIdx]._hash[0]].new_hash = new_hash;
    }

    function readStateProof(bytes calldata boc, bytes32 rh) public {
        BagOfCellsInfo memory header = tocParser.parseSerializedHeader(boc);
        CellData[100] memory toc = tocParser.get_tree_of_cells(boc, header);

        require(
            toc[header.rootIdx]._hash[0] == verifiedBlocks[rh].new_hash,
            "Block with new hash is not verified"
        );

        (
            bytes32[10] memory root_hashes,
            VerifiedBlockInfo[10] memory blocks
        ) = shardValidator.readStateProof(boc, header.rootIdx, toc);

        for (uint256 i = 0; i < root_hashes.length; i++) {
            if (root_hashes[i] == 0) {
                break;
            }

            verifiedBlocks[root_hashes[i]] = blocks[i];
        }
    }

    function setVerifiedBlock(bytes32 root_hash, uint32 seq_no) public onlyOwner {
        require(!isVerifiedBlock(root_hash), "block already verified");
        verifiedBlocks[root_hash] = VerifiedBlockInfo(true, seq_no, 0, 0, 0);
    }
}
