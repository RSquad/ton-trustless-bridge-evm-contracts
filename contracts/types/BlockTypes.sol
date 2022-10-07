//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct ValidatorDescription {
    uint8 cType;
    uint64 weight;
    bytes32 adnl_addr;
    bytes32 pubkey;
    bytes32 node_id;
    bytes32 verified;
}