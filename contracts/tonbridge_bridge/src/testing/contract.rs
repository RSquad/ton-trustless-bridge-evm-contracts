use cosmwasm_std::{
    coin, from_json,
    testing::{mock_dependencies, mock_env},
    Addr, HexBinary, Uint128,
};
use oraiswap::{asset::AssetInfo, router::RouterController};
use tonbridge_bridge::{
    amount::Amount,
    msg::{ChannelResponse, DeletePairMsg, PairQuery, QueryMsg as BridgeQueryMsg, UpdatePairMsg},
    state::{Config, MappingMetadata, Ratio, TokenFee},
};
use tonbridge_parser::{to_bytes32, EMPTY_HASH};

use crate::{
    channel::{decrease_channel_balance, increase_channel_balance},
    contract::{is_tx_processed, query},
    state::PROCESSED_TXS,
};

use super::mock::{new_mock_app, MockApp};

#[test]
fn test_instantiate_contract() {
    let MockApp {
        app,
        owner,
        bridge_addr,
        token_factory_addr,
        validator_addr,
        token_fee_addr,
        relayer_fee_addr,
        ..
    } = new_mock_app();

    let config: Config = app
        .query(bridge_addr.clone(), &BridgeQueryMsg::Config {})
        .unwrap();
    assert_eq!(
        config,
        Config {
            validator_contract_addr: validator_addr.clone(),
            bridge_adapter: "EQAE8anZidQFTKcsKS_98iDEXFkvuoa1YmVPxQC279zAoV7R".to_string(),
            token_fee_receiver: token_fee_addr.clone(),
            relayer_fee_receiver: relayer_fee_addr.clone(),
            swap_router_contract: RouterController("router".to_string()),
            token_factory_addr: Some(token_factory_addr),
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        }
    );
    let _owner: Addr = app
        .query(bridge_addr.clone(), &BridgeQueryMsg::Owner {})
        .unwrap();
    assert_eq!(owner, _owner);
}

#[test]
fn test_update_owner() {
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        ..
    } = new_mock_app();

    // update failed, not admin
    app.execute(
        Addr::unchecked("alice"),
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateOwner {
            new_owner: Addr::unchecked("alice"),
        },
        &[],
    )
    .unwrap_err();

    // update success
    app.execute(
        owner,
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateOwner {
            new_owner: Addr::unchecked("alice"),
        },
        &[],
    )
    .unwrap();
    let _owner: Addr = app
        .query(bridge_addr.clone(), &BridgeQueryMsg::Owner {})
        .unwrap();
    assert_eq!(_owner, Addr::unchecked("alice"));
}

#[test]
fn test_update_config() {
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        token_factory_addr,
        ..
    } = new_mock_app();

    // update failed, not admin
    app.execute(
        Addr::unchecked("alice"),
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: None,
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: None,
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap_err();

    // update success
    app.execute(
        owner,
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: Some(Addr::unchecked("contract1")),
            bridge_adapter: Some("DQAE8anZidQFTKcsKS_98iDEXFkvuoa1YmVPxQC279zAoV7R".to_string()),
            token_fee_receiver: Some(Addr::unchecked("new_token_fee")),
            relayer_fee_receiver: Some(Addr::unchecked("new_relayer_fee")),
            swap_router_contract: Some("new_router".to_string()),
            token_fee: None,
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap();

    let config: Config = app
        .query(bridge_addr.clone(), &BridgeQueryMsg::Config {})
        .unwrap();
    assert_eq!(
        config,
        Config {
            validator_contract_addr: Addr::unchecked("contract1"),
            bridge_adapter: "DQAE8anZidQFTKcsKS_98iDEXFkvuoa1YmVPxQC279zAoV7R".to_string(),
            token_fee_receiver: Addr::unchecked("new_token_fee"),
            relayer_fee_receiver: Addr::unchecked("new_relayer_fee"),
            swap_router_contract: RouterController("new_router".to_string()),
            token_factory_addr: Some(token_factory_addr),
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        }
    );
}

#[test]
fn test_update_token_fee() {
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        ..
    } = new_mock_app();

    app.execute(
        owner,
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: None,
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: Some(vec![TokenFee {
                token_denom: "orai".to_string(),
                ratio: Ratio {
                    nominator: 1,
                    denominator: 1000,
                },
            }]),
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap();

    let ratio: Ratio = app
        .query(
            bridge_addr.clone(),
            &BridgeQueryMsg::TokenFee {
                remote_token_denom: "orai".to_string(),
            },
        )
        .unwrap();

    assert_eq!(
        ratio,
        Ratio {
            nominator: 1,
            denominator: 1000,
        },
    )
}

#[test]
fn test_register_mapping_pair() {
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        cw20_addr,
        ..
    } = new_mock_app();
    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    let ibc_denom = "EQCcvbJBC2z5eiG00mtS6hYgijemXjMEnRrdPAenNSAringl";

    // register failed, no admin
    app.execute(
        Addr::unchecked("alice"),
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: ibc_denom.to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked(cw20_addr.clone()),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode: opcode.clone(),
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
        &[],
    )
    .unwrap_err();

    // register success
    app.execute(
        owner.clone(),
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: ibc_denom.to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked(cw20_addr.clone()),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode: opcode.clone(),
            token_origin: 529034805,
            relayer_fee: Uint128::default(),
        }),
        &[],
    )
    .unwrap();

    // query mapping

    let res: PairQuery = app
        .query(
            bridge_addr.clone(),
            &BridgeQueryMsg::PairMapping {
                key: ibc_denom.to_string(),
            },
        )
        .unwrap();
    assert_eq!(
        res,
        PairQuery {
            key: ibc_denom.to_string(),
            pair_mapping: MappingMetadata {
                asset_info: AssetInfo::Token {
                    contract_addr: Addr::unchecked(cw20_addr.clone()),
                },
                remote_decimals: 6,
                asset_info_decimals: 6,
                opcode: to_bytes32(&opcode).unwrap(),
                token_origin: 529034805,
                relayer_fee: Uint128::default()
            }
        }
    );

    // try remove
    app.execute(
        owner.clone(),
        Addr::unchecked(bridge_addr.as_str()),
        &tonbridge_bridge::msg::ExecuteMsg::DeleteMappingPair(DeletePairMsg {
            denom: "EQCcvbJBC2z5eiG00mtS6hYgijemXjMEnRrdPAenNSAringl".to_string(),
        }),
        &[],
    )
    .unwrap();
}

#[test]
fn test_update_channel_balance() {
    let mut deps = mock_dependencies();
    let denom = "ton";
    // try increase
    increase_channel_balance(deps.as_mut().storage, denom, Uint128::from(1000000u128)).unwrap();

    // after increase, query channel balance
    let state: ChannelResponse = from_json(
        &query(
            deps.as_ref(),
            mock_env(),
            BridgeQueryMsg::ChannelStateData {},
        )
        .unwrap(),
    )
    .unwrap();

    assert_eq!(
        state,
        ChannelResponse {
            balances: vec![Amount::Native(coin(1000000, denom))],
            total_sent: vec![Amount::Native(coin(1000000, denom))],
        }
    );

    // try decrease channel balance
    decrease_channel_balance(deps.as_mut().storage, denom, Uint128::from(500000u128)).unwrap();

    // after decrease, query channel balance
    let state: ChannelResponse = from_json(
        &query(
            deps.as_ref(),
            mock_env(),
            BridgeQueryMsg::ChannelStateData {},
        )
        .unwrap(),
    )
    .unwrap();

    assert_eq!(
        state,
        ChannelResponse {
            balances: vec![Amount::Native(coin(500000, denom))],
            total_sent: vec![Amount::Native(coin(1000000, denom))],
        }
    );

    // cannot decrease channel balance because not enough balances
    decrease_channel_balance(deps.as_mut().storage, denom, Uint128::from(600000u128)).unwrap_err();
}

#[test]
fn test_is_tx_processed() {
    let deps = mock_dependencies();
    let result = is_tx_processed(deps.as_ref(), HexBinary::from(EMPTY_HASH)).unwrap();
    assert_eq!(result, false);

    let mut deps = mock_dependencies();
    PROCESSED_TXS
        .save(deps.as_mut().storage, &EMPTY_HASH, &true)
        .unwrap();
    let result = is_tx_processed(deps.as_ref(), HexBinary::from(EMPTY_HASH)).unwrap();
    assert_eq!(result, true);
}
