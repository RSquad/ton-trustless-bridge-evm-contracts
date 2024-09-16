#[cfg(not(feature = "library"))]
use cosmwasm_std::entry_point;
use cosmwasm_std::{
    from_json, to_json_binary, wasm_execute, Addr, Empty, Order, Reply, SubMsgResult,
};
use cosmwasm_std::{Binary, Deps, DepsMut, Env, HexBinary, MessageInfo, Response, StdResult};
use cw20::Cw20ReceiveMsg;
use cw_utils::{nonpayable, one_coin};
use oraiswap::router::RouterController;
use tonbridge_bridge::amount::Amount;
use tonbridge_bridge::msg::{
    BridgeToTonMsg, ChannelResponse, DeletePairMsg, ExecuteMsg, InstantiateMsg, MigrateMsg,
    PairQuery, QueryMsg, RegisterDenomMsg, UpdatePairMsg,
};

use tonbridge_bridge::state::{Config, MappingMetadata, TokenFee};
use tonbridge_parser::to_bytes32;

use crate::adapter::{handle_bridge_to_ton, read_transaction, UNIVERSAL_SWAP_ERROR_ID};

use crate::error::ContractError;

use crate::state::{
    ics20_denoms, ACK_COMMITMENT, CONFIG, OWNER, PROCESSED_TXS, REMOTE_INITIATED_CHANNEL_STATE,
    SEND_PACKET_COMMITMENT, TEMP_UNIVERSAL_SWAP, TOKEN_FEE,
};

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    msg: InstantiateMsg,
) -> Result<Response, ContractError> {
    CONFIG.save(
        deps.storage,
        &Config {
            validator_contract_addr: msg.validator_contract_addr,
            bridge_adapter: msg.bridge_adapter,
            token_fee_receiver: msg.token_fee_receiver,
            relayer_fee_receiver: msg.relayer_fee_receiver,
            swap_router_contract: RouterController(msg.swap_router_contract),
            token_factory_addr: msg.token_factory_addr,
            osor_entrypoint_contract: msg.osor_entrypoint_contract,
        },
    )?;
    OWNER.set(deps, Some(info.sender))?;

    Ok(Response::new())
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> Result<Response, ContractError> {
    match msg {
        ExecuteMsg::UpdateOwner { new_owner } => execute_update_owner(deps, info, new_owner),
        ExecuteMsg::UpdateConfig {
            validator_contract_addr,
            bridge_adapter,
            token_fee_receiver,
            relayer_fee_receiver,
            swap_router_contract,
            token_fee,
            token_factory_addr,
            osor_entrypoint_contract,
        } => execute_update_config(
            deps,
            info,
            validator_contract_addr,
            bridge_adapter,
            token_fee_receiver,
            relayer_fee_receiver,
            swap_router_contract,
            token_fee,
            token_factory_addr,
            osor_entrypoint_contract,
        ),
        ExecuteMsg::ReadTransaction { tx_proof, tx_boc } => {
            read_transaction(deps, env, tx_proof, tx_boc)
        }
        ExecuteMsg::UpdateMappingPair(msg) => update_mapping_pair(deps, &info.sender, msg),
        ExecuteMsg::DeleteMappingPair(msg) => execute_delete_mapping_pair(deps, info, msg),
        ExecuteMsg::BridgeToTon(msg) => {
            let coin = one_coin(&info)?;
            let amount = Amount::from_parts(coin.denom, coin.amount);
            handle_bridge_to_ton(deps, env, msg, amount, info.sender)
        }
        ExecuteMsg::Receive(msg) => execute_receive(deps, env, info, msg),
        ExecuteMsg::RegisterDenom(msg) => register_denom(deps, info, msg),
    }
}

#[entry_point]
pub fn reply(deps: DepsMut, _env: Env, reply: Reply) -> Result<Response, ContractError> {
    if let SubMsgResult::Err(err) = reply.result {
        return match reply.id {
            UNIVERSAL_SWAP_ERROR_ID => {
                let universal_swap_data = TEMP_UNIVERSAL_SWAP.load(deps.storage)?;

                let refund_msg = universal_swap_data.return_amount.into_msg(
                    None,
                    &deps.querier,
                    deps.api
                        .addr_validate(&universal_swap_data.recovery_address)?,
                )?;
                TEMP_UNIVERSAL_SWAP.remove(deps.storage);

                Ok(Response::new()
                    .add_attribute("action", "universal_swap_error")
                    .add_attribute("error_trying_to_call_entrypoint_for_universal_swap", err)
                    .add_message(refund_msg))
            }
            _ => Err(ContractError::UnknownReplyId { id: reply.id }),
        };
    }
    // default response
    Ok(Response::new())
}

pub fn execute_update_owner(
    deps: DepsMut,
    info: MessageInfo,
    new_owner: Addr,
) -> Result<Response, ContractError> {
    OWNER.execute_update_admin::<Empty, Empty>(deps, info, Some(new_owner.clone()))?;

    Ok(Response::new().add_attributes(vec![
        ("action", "update_owner"),
        ("new_owner", new_owner.as_str()),
    ]))
}

#[allow(clippy::too_many_arguments)]
pub fn execute_update_config(
    deps: DepsMut,
    info: MessageInfo,
    validator_contract_addr: Option<Addr>,
    bridge_adapter: Option<String>,
    token_fee_receiver: Option<Addr>,
    relayer_fee_receiver: Option<Addr>,
    swap_router_contract: Option<String>,
    token_fee: Option<Vec<TokenFee>>,
    token_factory_addr: Option<Addr>,
    osor_entrypoint_contract: Option<Addr>,
) -> Result<Response, ContractError> {
    OWNER.assert_admin(deps.as_ref(), &info.sender)?;

    if let Some(token_fee) = token_fee {
        for fee in token_fee {
            TOKEN_FEE.save(deps.storage, &fee.token_denom, &fee.ratio)?;
        }
    }

    let mut config = CONFIG.load(deps.storage)?;

    if let Some(validator_contract_addr) = validator_contract_addr {
        config.validator_contract_addr = validator_contract_addr;
    }
    if let Some(bridge_adapter) = bridge_adapter {
        config.bridge_adapter = bridge_adapter;
    }
    if let Some(token_fee_receiver) = token_fee_receiver {
        config.token_fee_receiver = token_fee_receiver;
    }
    if let Some(relayer_fee_receiver) = relayer_fee_receiver {
        config.relayer_fee_receiver = relayer_fee_receiver;
    }
    if let Some(swap_router_contract) = swap_router_contract {
        config.swap_router_contract = RouterController(swap_router_contract);
    }
    if let Some(token_factory_addr) = token_factory_addr {
        config.token_factory_addr = Some(token_factory_addr);
    }
    if let Some(osor_entrypoint_contract) = osor_entrypoint_contract {
        config.osor_entrypoint_contract = osor_entrypoint_contract;
    }

    CONFIG.save(deps.storage, &config)?;

    Ok(Response::default().add_attribute("action", "update_config"))
}

pub fn update_mapping_pair(
    deps: DepsMut,
    caller: &Addr,
    msg: UpdatePairMsg,
) -> Result<Response, ContractError> {
    OWNER.assert_admin(deps.as_ref(), caller)?;

    ics20_denoms().save(
        deps.storage,
        &msg.denom,
        &MappingMetadata {
            asset_info: msg.local_asset_info.clone(),
            remote_decimals: msg.remote_decimals,
            asset_info_decimals: msg.local_asset_info_decimals,
            opcode: to_bytes32(&msg.opcode)?,
            token_origin: msg.token_origin,
            relayer_fee: msg.relayer_fee,
        },
    )?;
    Ok(Response::new().add_attributes(vec![("action", "update_mapping_pair")]))
}

pub fn register_denom(
    deps: DepsMut,
    info: MessageInfo,
    msg: RegisterDenomMsg,
) -> Result<Response, ContractError> {
    OWNER.assert_admin(deps.as_ref(), &info.sender)?;

    let config = CONFIG.load(deps.storage)?;

    let create_denom_msg = wasm_execute(
        config.token_factory_addr.unwrap(),
        &tokenfactory::msg::ExecuteMsg::CreateDenom {
            subdenom: msg.subdenom,
            metadata: msg.metadata,
        },
        info.funds,
    )?;

    Ok(Response::new()
        .add_attribute("action", "register_denom")
        .add_message(create_denom_msg))
}

pub fn execute_delete_mapping_pair(
    deps: DepsMut,
    info: MessageInfo,
    mapping_pair_msg: DeletePairMsg,
) -> Result<Response, ContractError> {
    OWNER.assert_admin(deps.as_ref(), &info.sender)?;

    ics20_denoms().remove(deps.storage, &mapping_pair_msg.denom)?;

    let res = Response::new()
        .add_attribute("action", "execute_delete_mapping_pair")
        .add_attribute("original_denom", mapping_pair_msg.denom);
    Ok(res)
}

pub fn execute_receive(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    wrapper: Cw20ReceiveMsg,
) -> Result<Response, ContractError> {
    nonpayable(&info)?;

    let amount = Amount::cw20(wrapper.amount.into(), info.sender.as_str());
    let msg: BridgeToTonMsg = from_json(&wrapper.msg)?;
    let sender = deps.api.addr_validate(&wrapper.sender)?;
    handle_bridge_to_ton(deps, env, msg, amount, sender)
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn query(deps: Deps, _env: Env, msg: QueryMsg) -> StdResult<Binary> {
    match msg {
        QueryMsg::Owner {} => to_json_binary(&OWNER.query_admin(deps)?.admin),
        QueryMsg::Config {} => to_json_binary(&get_config(deps)?),
        QueryMsg::TokenFee { remote_token_denom } => {
            to_json_binary(&TOKEN_FEE.load(deps.storage, &remote_token_denom)?)
        }
        QueryMsg::IsTxProcessed { tx_hash } => to_json_binary(&is_tx_processed(deps, tx_hash)?),
        QueryMsg::ChannelStateData {} => to_json_binary(&query_channel(deps)?),
        QueryMsg::PairMapping { key } => to_json_binary(&get_mapping_from_key(deps, key)?),
        QueryMsg::SendPacketCommitment { seq } => {
            to_json_binary(&SEND_PACKET_COMMITMENT.load(deps.storage, seq)?)
        }
        QueryMsg::AckCommitment { seq } => to_json_binary(&ACK_COMMITMENT.load(deps.storage, seq)?),
    }
}

pub fn is_tx_processed(deps: Deps, tx_hash: HexBinary) -> StdResult<bool> {
    PROCESSED_TXS
        .may_load(deps.storage, &to_bytes32(&tx_hash)?)
        .map(|res| res.unwrap_or(false))
}

pub fn get_config(deps: Deps) -> StdResult<Config> {
    let config = CONFIG.load(deps.storage)?;
    Ok(config)
}

// make public for ibc tests
pub fn query_channel(deps: Deps) -> StdResult<ChannelResponse> {
    let state = REMOTE_INITIATED_CHANNEL_STATE
        .range(deps.storage, None, None, Order::Ascending)
        .filter_map(Result::ok)
        // this denom is
        .map(|(denom, v)| {
            let outstanding = Amount::from_parts(denom.clone(), v.outstanding);
            let total = Amount::from_parts(denom, v.total_sent);
            (outstanding, total)
        })
        .collect::<Vec<_>>();

    // we want (Vec<outstanding>, Vec<total>)
    let (balances, total_sent): (Vec<Amount>, Vec<Amount>) = state.into_iter().unzip();

    Ok(ChannelResponse {
        balances,
        total_sent,
    })
}

fn get_mapping_from_key(deps: Deps, ibc_denom: String) -> StdResult<PairQuery> {
    let result = ics20_denoms().load(deps.storage, &ibc_denom)?;
    Ok(PairQuery {
        key: ibc_denom,
        pair_mapping: result,
    })
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn migrate(_deps: DepsMut, _env: Env, _msg: MigrateMsg) -> Result<Response, ContractError> {
    Ok(Response::default())
}
