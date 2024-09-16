use cosmwasm_schema::cw_serde;
use cosmwasm_std::{Addr, Uint128};
use oraiswap::{
    asset::{Asset, AssetInfo},
    router::RouterController,
};
use tonbridge_parser::types::Bytes32;

#[cw_serde]
pub struct MappingMetadata {
    /// asset info on local chain. Can be either cw20 or native
    pub asset_info: AssetInfo,
    pub remote_decimals: u8,
    pub asset_info_decimals: u8,
    pub opcode: Bytes32,
    pub token_origin: u32, // to determine the source of token
    #[serde(default)]
    pub relayer_fee: Uint128,
}

#[cw_serde]
#[derive(Default)]
pub struct ChannelState {
    pub outstanding: Uint128,
    pub total_sent: Uint128,
}

#[cw_serde]
pub struct TokenFee {
    pub token_denom: String,
    pub ratio: Ratio,
}

#[cw_serde]
pub struct RelayerFee {
    pub prefix: String,
    pub fee: Uint128,
}

#[cw_serde]
pub struct Ratio {
    pub nominator: u64,
    pub denominator: u64,
}

#[cw_serde]
pub struct Config {
    pub validator_contract_addr: Addr,
    pub bridge_adapter: String, // bridge adapter on TON
    pub token_fee_receiver: Addr,
    pub relayer_fee_receiver: Addr,
    pub swap_router_contract: RouterController,
    pub token_factory_addr: Option<Addr>,
    pub osor_entrypoint_contract: Addr,
}

#[cw_serde]
pub struct TimeoutSendPacket {
    pub local_refund_asset: Asset,
    pub remote_denom: String,
    pub remote_amount: Uint128,
    pub sender: String,
    pub timeout_timestamp: u64,
    pub opcode: Bytes32,
    #[serde(default)]
    pub recovery_addr: Option<Addr>,
}

#[cw_serde]
pub struct TempUniversalSwap {
    pub recovery_address: String,
    pub return_amount: Asset,
}
