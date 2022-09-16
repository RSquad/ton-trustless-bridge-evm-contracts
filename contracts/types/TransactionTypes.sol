//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct TonAddress {
    bytes32 hash;
    uint8 wc;
}

struct RawCommonMessageInfo {
    uint256 Type;
    bool ihrDisabled;
    bool bounce;
    bool bounced;
    TonAddress src;
    TonAddress dest;
    // value RawCurrencyCollection
    bytes32 value;
    bytes32 ihrFee;
    bytes32 fwdFee;
    uint256 createdLt;
    uint256 createdAt;
    bytes32 importFee;
}

struct Message {
    RawCommonMessageInfo info;
    uint256 bodyIdx;
}

struct MessagesHeader {
    bool hasInMessage;
    bool hasOutMessages;
    Message inMessage;
    Message[5] outMessages;
}

struct TransactionHeader {
    uint8 checkCode;
    bytes32 addressHash;
    uint64 lt;
    bytes32 prevTransHash;
    uint64 prevTransLt;
    uint32 time;
    uint32 OutMesagesCount;
    uint8 oldStatus;
    uint8 newStatus;
    bytes32 fees;
    MessagesHeader messages;
}

struct TestData {
    address eth_address;
    uint256 amount;
}