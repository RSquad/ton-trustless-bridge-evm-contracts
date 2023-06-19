//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct ValidatorDescription {
    uint8 cType;
    uint64 weight;
    bytes32 adnl_addr;
    bytes32 pubkey;
    bytes32 node_id;
    // mapping(bytes32 => bool) verified;
}

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