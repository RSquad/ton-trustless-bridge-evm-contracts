use cosmwasm_schema::cw_serde;
use cosmwasm_std::{CanonicalAddr, HexBinary, StdResult, Uint128, Uint256};
use tonlib::{address::TonAddress as TonlibTonAddress, cell::Cell};

pub type Bytes32 = [u8; 32];
pub type ValidatorSet = Vec<ValidatorDescription>;

#[cw_serde]
#[derive(Copy, Default)]
pub struct ValidatorDescription {
    pub c_type: u8,
    pub weight: u64,
    pub adnl_addr: Bytes32,
    pub pubkey: Bytes32,
    pub node_id: Bytes32,
    // mapping(bytes32 => bool) verified;
}

#[cw_serde]
pub struct Vdata {
    pub node_id: Bytes32,
    pub r: Bytes32,
    pub s: Bytes32,
}

#[cw_serde]
pub struct VdataHex {
    pub node_id: HexBinary,
    pub r: HexBinary,
    pub s: HexBinary,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct CachedCell {
    pub prefix_length: u128,
    pub hash: Bytes32,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct VerifiedBlockInfo {
    pub verified: bool,
    pub seq_no: u32,
    pub start_lt: u64,
    pub end_lt: u64,
    pub new_hash: Bytes32,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct CellData {
    pub special: bool,
    pub refs: [usize; 4],
    pub cursor: usize,
    pub cursor_ref: u8,

    pub hashes: [Bytes32; 4],
    pub level_mask: u32,
    pub depth: [u16; 4],
    pub cell_type: u8,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct CellSerializationInfo {
    pub d1: u8,
    pub d2: u8,
    pub special: bool,
    pub level_mask: u32,
    pub with_hashes: bool,
    pub hashes_offset: usize,
    pub depth_offset: usize,
    pub data_offset: usize,
    pub data_len: usize,
    pub data_with_bits: bool,
    pub refs_offset: usize,
    pub refs_cnt: usize,
    pub end_offset: usize,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct TonAddress {
    pub hash: Bytes32,
    pub wc: u8,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct RawCommonMessageInfo {
    pub msg_type: Uint256,
    pub ihr_disabled: bool,
    pub bounce: bool,
    pub bounced: bool,
    pub src: TonAddress,
    pub dest: TonAddress,
    // value RawCurrencyCollection
    pub value: Bytes32,
    pub ihr_fee: Bytes32,
    pub fwd_fee: Bytes32,
    pub created_lt: Uint256,
    pub created_at: Uint256,
    pub import_fee: Bytes32,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct Message {
    pub info: RawCommonMessageInfo,
    pub body_idx: usize,
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct MessagesHeader {
    pub has_in_message: bool,
    pub has_out_messages: bool,
    pub in_message: Message,
    pub out_messages: [Message; 5],
}

#[cw_serde]
#[derive(Copy, Default)]
pub struct TransactionHeader {
    pub check_code: u8,
    pub address_hash: Bytes32,
    pub lt: u64,
    pub prev_trans_hash: Bytes32,
    pub prev_trans_lt: u64,
    pub time: u32,
    pub out_mesages_count: u32,
    pub old_status: u8,
    pub new_status: u8,
    pub fees: Bytes32,
    pub messages: MessagesHeader,
}

#[cw_serde]
#[derive(Default)]
pub struct PacketData {
    // should change to cannonical addr, same as Address with 20 bytes
    pub receiving_address: String,
    // pub receiving_token: AssetInfo,
    pub amount: Uint256,
}

#[cw_serde]
#[derive(Default)]
pub struct KeyBlockValidators {
    pub previous: ValidatorSet,
    pub current: ValidatorSet,
    pub next: ValidatorSet,
}

#[derive(Clone, Debug)]
pub struct BridgePacketDataRaw {
    pub seq: u64,
    pub token_origin: u32,
    pub timeout_timestamp: u64,
    pub src_sender: TonlibTonAddress,
    pub src_denom: TonlibTonAddress,
    pub amount: u128,
    pub receiver: CanonicalAddr,
    pub memo: Option<Cell>,
}

impl BridgePacketDataRaw {
    pub fn to_pretty(self) -> StdResult<BridgePacketData> {
        Ok(BridgePacketData {
            seq: self.seq,
            token_origin: self.token_origin,
            timeout_timestamp: self.timeout_timestamp,
            src_sender: self.src_sender.to_string(),
            src_denom: self.src_denom.to_string(),
            receiver: self.receiver,
            memo: self.memo,
            amount: Uint128::from(self.amount),
        })
    }
}

#[derive(Clone, PartialEq, Debug)]
pub struct BridgePacketData {
    pub seq: u64,
    pub token_origin: u32,
    pub timeout_timestamp: u64,
    pub src_sender: String,
    pub src_denom: String,
    pub amount: Uint128,
    pub receiver: CanonicalAddr,
    pub memo: Option<Cell>,
}

#[cw_serde]
pub enum Status {
    Success = 0,
    Error = 1,
    Timeout = 2,
}

impl Status {
    pub fn from_value(value: u8) -> Option<Status> {
        match value {
            0 => Some(Status::Success),
            1 => Some(Status::Error),
            2 => Some(Status::Timeout),
            _ => None,
        }
    }
}

impl std::fmt::Display for Status {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Status::Success => write!(f, "Success"),
            Status::Error => write!(f, "Error"),
            Status::Timeout => write!(f, "Timeout"),
        }
    }
}

#[cw_serde]
pub struct AckPacket {
    pub seq: u64,
    pub status: Status,
}
