use std::str::FromStr;

use cosmwasm_std::{
    attr, coin, coins,
    testing::{mock_dependencies, mock_env, mock_info},
    to_json_binary, wasm_execute, Addr, BankMsg, CanonicalAddr, Coin, CosmosMsg, HexBinary, SubMsg,
    Uint128, Uint256, WasmMsg,
};

use cw20::{BalanceResponse, Cw20ExecuteMsg, Cw20ReceiveMsg};

use oraiswap::{
    asset::{Asset, AssetInfo},
    router::RouterController,
};

use tonbridge_bridge::{
    amount::Amount,
    msg::{
        BridgeToTonMsg, ChannelResponse, ExecuteMsg, InstantiateMsg, QueryMsg as BridgeQueryMsg,
        UpdatePairMsg,
    },
    state::{ChannelState, Config, MappingMetadata, Ratio, TimeoutSendPacket, TokenFee},
};
use tonbridge_parser::{
    transaction_parser::SEND_TO_TON_MAGIC_NUMBER,
    types::{BridgePacketData, Status},
    OPCODE_1, OPCODE_2,
};
use tonlib::{
    address::TonAddress,
    cell::CellBuilder,
    responses::{AnyCell, MaybeRefData, MessageType, TransactionMessage},
};

use crate::{
    adapter::{handle_packet_receive, on_acknowledgment, DEFAULT_TIMEOUT, UNIVERSAL_SWAP_ERROR_ID},
    bridge::Bridge,
    channel::increase_channel_balance,
    contract::{execute, instantiate},
    error::ContractError,
    helper::{build_ack_commitment, build_burn_asset_msg, build_mint_asset_msg},
    state::{ACK_COMMITMENT, CONFIG, REMOTE_INITIATED_CHANNEL_STATE, SEND_PACKET, TOKEN_FEE},
    testing::mock::{new_mock_app, MockApp},
};
use skip::entry_point::ExecuteMsg as EntryPointExecuteMsg;

#[test]
fn test_validate_transaction_out_msg() {
    let mut maybe_ref = MaybeRefData::default();
    let bridge_addr = "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string();
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res, None);
    let mut transaction_message = TransactionMessage::default();
    transaction_message.info.msg_type = MessageType::ExternalIn as u8;
    maybe_ref.data = Some(transaction_message.clone());
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res, None);
    transaction_message.info.msg_type = MessageType::ExternalOut as u8;
    maybe_ref.data = Some(transaction_message.clone());
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res, None);
    transaction_message.info.src = TonAddress::from_str(&bridge_addr.clone()).unwrap();
    maybe_ref.data = Some(transaction_message.clone());
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res, None);

    transaction_message.body.cell_ref = Some((None, None));
    maybe_ref.data = Some(transaction_message.clone());
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res, None);

    let any_cell = AnyCell::default();
    transaction_message.body.cell_ref = Some((Some(any_cell.clone()), None));
    maybe_ref.data = Some(transaction_message.clone());
    let res = Bridge::validate_transaction_out_msg(maybe_ref.clone(), bridge_addr.clone());
    assert_eq!(res.unwrap(), any_cell.cell);
}

#[test]
fn test_handle_packet_receive() {
    let mut deps = mock_dependencies();
    let deps_mut = deps.as_mut();
    let storage = deps_mut.storage;
    let api = deps_mut.api;
    let querier = deps_mut.querier;
    let env = mock_env();
    let current_timestamp = env.block.time.seconds() + DEFAULT_TIMEOUT;

    let seq = 1;
    let token_origin = 529034805;
    let timeout_timestamp = env.block.time.seconds() - 100;
    let src_sender = "EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh".to_string();
    let src_denom = "EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh".to_string();
    let amount = Uint128::from(1000000000u128);

    let receiver_raw: Vec<u8> = vec![
        23, 12, 3, 5, 13, 30, 10, 3, 20, 28, 27, 5, 31, 12, 11, 15, 3, 1, 22, 13, 21, 3, 30, 20,
        12, 3, 16, 0, 11, 14, 26, 4,
    ];
    let receiver = CanonicalAddr::from(receiver_raw);

    let mut bridge_packet_data = BridgePacketData {
        seq,
        token_origin,
        timeout_timestamp,
        src_sender: src_sender.clone(),
        src_denom: src_denom.clone(),
        amount,
        receiver: receiver.clone(),
        memo: None,
    };

    let mapping = MappingMetadata {
        asset_info: AssetInfo::NativeToken {
            denom: "orai".to_string(),
        },
        remote_decimals: 6,
        asset_info_decimals: 6,
        opcode: OPCODE_2,
        token_origin: 529034805,
        relayer_fee: Uint128::zero(),
    };
    CONFIG
        .save(
            storage,
            &Config {
                validator_contract_addr: Addr::unchecked("validator"),
                bridge_adapter: "bridge_adapter".to_string(),
                token_fee_receiver: Addr::unchecked("token_fee_receiver"),
                relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
                swap_router_contract: RouterController("router".to_string()),
                token_factory_addr: None,
                osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
            },
        )
        .unwrap();
    TOKEN_FEE
        .save(
            storage,
            "orai",
            &Ratio {
                nominator: 1,
                denominator: 1000,
            },
        )
        .unwrap();

    // case 1: timeout
    let res = handle_packet_receive(
        &env,
        storage,
        api,
        &querier,
        current_timestamp,
        bridge_packet_data.clone(),
        mapping.clone(),
    )
    .unwrap();

    assert_eq!(res.0.len(), 0);
    assert_eq!(
        res.1
            .iter()
            .find(|x| x.key == "ack_value" && x.value == "timeout")
            .is_some(),
        true
    );

    // case 2: happy case
    bridge_packet_data.seq = 2;
    bridge_packet_data.timeout_timestamp = current_timestamp;
    handle_packet_receive(
        &env,
        storage,
        api,
        &querier,
        current_timestamp,
        bridge_packet_data.clone(),
        mapping,
    )
    .unwrap();

    let commitment = ACK_COMMITMENT
        .load(deps.as_ref().storage, bridge_packet_data.seq)
        .unwrap();
    assert_eq!(
        commitment.to_be_bytes(),
        build_ack_commitment(
            bridge_packet_data.seq,
            token_origin,
            amount,
            bridge_packet_data.timeout_timestamp,
            receiver.as_slice(),
            &src_denom,
            &src_sender,
            Status::Success
        )
        .unwrap()
        .as_slice()
    );
}

#[test]
fn test_read_transaction() {
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        cw20_addr,
        validator_addr,
        ..
    } = new_mock_app();

    // update bridge adapter contract
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: Some("EQCWH9kCKpCTpswaygq-Ah7h-1vH3xZ3gJq7-SM6ZkYiOgHH".to_string()),
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: None,
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap();

    let tx_boc = HexBinary::from_hex("b5ee9c72010211010003450003b57961fd9022a9093a6cc1aca0abe021ee1fb5bc7df1677809abbf9233a6646223a00002b5df4ae0c41591328d8b3673d4b795f57c789e145481d3b1d2413af77a28086813032f2cf0c00002b5df4527ec1668fba29000546e2689c80102030201e0040500827298457e3ebcfa880e4a67df0d88c69cca63a7ca8de9234ad23dbe051f586d8469b9aa5df59ef1ad564d84695fd6c9182ef92b205953a7da224579e187466403bb02170446c91cef574c186c1fe8110f1001b1680026199d4cf9ecc6786607ea6ab5d07ebb2b7300531ce1d62713126b93e9b547fb002587f6408aa424e9b306b282af8087b87ed6f1f7c59de026aefe48ce9991888e91cef574c00612b38a000056bbe9008b04cd1f743ac0060201dd08090118af35dc850000000000000000070285ffff800e538276dbe580f97e140d56c7a695e8a9e7a641d8379b1f6b8da49a100d42f8444e2000000000cd1f574c299beee0c4cf91a62d47583c7745120351acd2a5810e0d0101200a0101200b00c948012c3fb2045521274d983594157c043dc3f6b78fbe2cef013577f24674cc8c44750005b94eca7698c8dafacc801ff8f0f63edae1d14809c6871dcabcc6ed24fbf63391cd590dc00608235a000056bbe95c1884cd1f74526a993b6d800000000000000040019fe004b0fec81154849d3660d65055f010f70fdade3ef8b3bc04d5dfc919d3323111d30010926e9e39e0b6f991fe801420858017cc708d639ef898187dc61b9eac89901a00002b5df4ae0c43668fba29600c02bda64c12a300000000000000071f886e350000000000000000000000000000271000000000668faba614cdf7706267c8d316a3ac1e3ba28901a8d66952c0800e538276dbe580f97e140d56c7a695e8a9e7a641d8379b1f6b8da49a100d42f8500d0e00438002dca7653b4c646d7d66400ffc787b1f6d70e8a404e3438ee55e6376927dfb19d00000009e47c28c3d09000000000000000000f200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc98a23504c40d3cc0000000000040000000000044acf306fc0346e061272572316da3988492c51b2df2a48f0fae17327c722d09c41504ccc").unwrap();

    let tx_proof = HexBinary::from_hex("b5ee9c7201021a010003e800094603eb26d6f3d075f89f8ad8bb011a6814ec6a283c697cbcc0ca2450eaad97a06327002501241011ef55aaffffff110203040502a09bc7a98700000000800102a6fa0e0000000102000000008000000000000000668fba2900002b5df4ae0c4000002b5df4ae0c4d28b29c140008f0420252443f025228dbc400000007000000000000002e06072848010169134a3a596b68d647965f54a94d98fea6b8cdca27f61d5f8117859ae80f71460003284801017bdcfc2172b6c9e181490a9960cd7b90b44dd129ebc618a416f60c0144298d38002423894a33f6fde8a3fae01eb649213b6347684dcdd1bea74a224138fe572d3b2b41d156d02415ea2e404dd0ee02412f2a7791d30abd074ec16256fa83cd5376d4b0fbcfddf8df4008090a009800002b5df49eca040252443fadd1d2b79fce4fb274d594057b44704ff4a09d783433498401d7a3268998344d7d92a3baba00a520556b90da5731b089013a8491278cf99870417e8178cd5028009800002b5df49eca0a02a6fa0dad0968c77acc29e9847831a33ecf1005ea8b189a9fc33fc9a640718d23639083a9e2bf177215b1ed5d4f8737860e81c9f3ae9669024ecaedde03957abf34359a2848010126a390200ef92244737858b673f1eddffd1c0b96fc85d754efbdaab26a28ec2c001c284801019a90185f6324eab6c87c27f5a8ff53ea2a129b6b519e9d95f81c4dbb648b0cdf001c2109a0773e1bc20b220b6903b9f0de100c0d2209101d4c77b50e0f28480101d6b60f4f983236f3b9e6a5b198a318ecb28bb7b5b1df54711cdaf4142f300e85001928480101df692049ca7bbaa2a47bf4008e104f7f11838553b7883c8dc39d865f57145524001322091015c153d910112209100cb12509121328480101812da7fe1eab36c72bf9174ae0dfd6ed4477180a7090ed81503a3e27a3aa9fe9000d284801016a53739349b426fbaa9093865a46d4986f351f269f1a24e94596ab9afea86f05001322091008bed0f514152848010173151c552b62a83c7ff320b32184eb6219e12e8d6aaba1c40061cec12c5ca742000a22091004e5ff19161722a3be07f6408aa424e9b306b282af8087b87ed6f1f7c59de026aefe48ce9991888e8dc4d138b2c3fb2045521274d983594157c043dc3f6b78fbe2cef013577f24674cc8c44754000002b5df4ae0c41371344e40181928480101f8c0756de82229a358f03b021ba0c2cd31ddfcf3b220192248fd05b7ddfc425f001228480101f070dea8890cc35e161d5c3019d8e8b195dff34ffd2ef60b975727645296d338000600827298457e3ebcfa880e4a67df0d88c69cca63a7ca8de9234ad23dbe051f586d8469b9aa5df59ef1ad564d84695fd6c9182ef92b205953a7da224579e187466403bb").unwrap();

    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    let token_denom = "EQBynBO23ywHy_CgarY9NK9FTz0yDsG82PtcbSTQgGoXwiuA";
    let packet_timeout_timestamp = 1720691622u64;
    app.set_block_time_seconds(packet_timeout_timestamp - 10);

    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: token_denom.to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked(cw20_addr.clone()),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
        &[],
    )
    .unwrap();

    // case 1: read tx failed, block not verify,
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::ReadTransaction {
            tx_proof: tx_proof.clone(),
            tx_boc: tx_boc.clone(),
        },
        &[],
    )
    .unwrap_err();

    // shard block with block hash
    let block_hash =
        HexBinary::from_hex("eb26d6f3d075f89f8ad8bb011a6814ec6a283c697cbcc0ca2450eaad97a06327")
            .unwrap();

    // set verified for simplicity
    app.execute(
        owner.clone(),
        validator_addr.clone(),
        &tonbridge_validator::msg::ExecuteMsg::SetVerifiedBlock {
            root_hash: block_hash,
            seq_no: 1,
        },
        &[],
    )
    .unwrap();

    println!("{}", app.get_block_height());
    app.set_block_time_seconds(app.get_block_time().seconds() - 10);
    println!("{}", app.get_block_height());

    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::ReadTransaction { tx_proof, tx_boc },
        &[],
    )
    .unwrap();

    // query channel state
    let res: ChannelResponse = app
        .query(bridge_addr.clone(), &BridgeQueryMsg::ChannelStateData {})
        .unwrap();

    assert_eq!(
        res,
        ChannelResponse {
            balances: vec![Amount::Native(coin(10000, token_denom))],
            total_sent: vec![Amount::Native(coin(10000, token_denom))],
        }
    );
}

#[test]
fn test_bridge_native_to_ton() {
    let mut deps = mock_dependencies();
    let denom = "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB";
    instantiate(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        InstantiateMsg {
            validator_contract_addr: Addr::unchecked("validator_contract_addr"),
            bridge_adapter: "bridge_adapter".to_string(),
            token_fee_receiver: Addr::unchecked("token_fee_receiver"),
            relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
            swap_router_contract: "swap_router_contract".to_string(),
            token_factory_addr: None,
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        },
    )
    .unwrap();

    // case 1: failed, no funds
    let err = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("sender", &vec![]),
        ExecuteMsg::BridgeToTon(BridgeToTonMsg {
            to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
            denom: denom.to_string(),
            timeout: None,
            recovery_addr: None,
        }),
    )
    .unwrap_err();
    assert_eq!(err.to_string(), "No funds sent");

    // case 2: failed, not mapping pair
    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("sender", &vec![coin(10000, "orai")]),
        ExecuteMsg::BridgeToTon(BridgeToTonMsg {
            to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
            denom: denom.to_string(),
            timeout: None,
            recovery_addr: None,
        }),
    )
    .unwrap_err();

    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: denom.to_string(),
            local_asset_info: AssetInfo::NativeToken {
                denom: "orai".to_string(),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
    )
    .unwrap();

    // case 4: maping pair is invalid
    let err = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("sender", &vec![coin(10000, "atom")]),
        ExecuteMsg::BridgeToTon(BridgeToTonMsg {
            to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
            denom: denom.to_string(),
            timeout: None,
            recovery_addr: None,
        }),
    )
    .unwrap_err();
    assert_eq!(err.to_string(), ContractError::InvalidFund {}.to_string());

    // case 5: failed, channel don't exist
    let err = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("sender", &vec![coin(10000, "orai")]),
        ExecuteMsg::BridgeToTon(BridgeToTonMsg {
            to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
            denom: denom.to_string(),
            timeout: None,
            recovery_addr: None,
        }),
    )
    .unwrap_err();
    assert_eq!(err.to_string(), "Generic error: Channel does not exist");

    // case 6: success
    increase_channel_balance(deps.as_mut().storage, denom, Uint128::from(1000000000u128)).unwrap();
    let res = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("sender", &vec![coin(10000, "orai")]),
        ExecuteMsg::BridgeToTon(BridgeToTonMsg {
            to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
            denom: denom.to_string(),
            timeout: None,
            recovery_addr: None,
        }),
    )
    .unwrap();
    assert_eq!(res.messages, vec![]);
    assert_eq!(
        res.attributes,
        vec![
            attr("action", "send_to_ton"),
            attr("opcode_packet", SEND_TO_TON_MAGIC_NUMBER.to_string()),
            attr("local_sender", "sender"),
            attr(
                "remote_receiver",
                "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT"
            ),
            attr(
                "remote_denom",
                "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB"
            ),
            attr("local_amount", "10000"),
            attr("token_origin", &529034805u32.to_string()),
            attr("relayer_fee", "0"),
            attr("token_fee", "0"),
            attr(
                "timeout_timestamp",
                &mock_env()
                    .block
                    .time
                    .plus_seconds(3600)
                    .seconds()
                    .to_string()
            ),
            attr("remote_amount", "10000"),
            attr("seq", "1"),
            attr("recovery_addr", "sender"),
        ]
    );
}

#[test]
fn test_bridge_cw20_to_ton() {
    let mut deps = mock_dependencies();
    instantiate(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        InstantiateMsg {
            validator_contract_addr: Addr::unchecked("validator_contract_addr"),
            bridge_adapter: "bridge_adapter".to_string(),
            token_fee_receiver: Addr::unchecked("token_fee_receiver"),
            relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
            swap_router_contract: "swap_router_contract".to_string(),
            token_factory_addr: None,
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        },
    )
    .unwrap();

    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked("usdt"),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
    )
    .unwrap();

    increase_channel_balance(
        deps.as_mut().storage,
        "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB",
        Uint128::from(1000000000u128),
    )
    .unwrap();

    let res = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("usdt", &vec![]),
        ExecuteMsg::Receive(Cw20ReceiveMsg {
            sender: "sender".to_string(),
            amount: Uint128::from(10000u128),
            msg: to_json_binary(&BridgeToTonMsg {
                to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
                denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
                timeout: None,
                recovery_addr: None,
            })
            .unwrap(),
        }),
    )
    .unwrap();
    assert_eq!(res.messages, vec![]);
    assert_eq!(
        res.attributes,
        vec![
            attr("action", "send_to_ton"),
            attr("opcode_packet", SEND_TO_TON_MAGIC_NUMBER.to_string()),
            attr("local_sender", "sender"),
            attr(
                "remote_receiver",
                "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT"
            ),
            attr(
                "remote_denom",
                "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB"
            ),
            attr("local_amount", "10000"),
            attr("token_origin", &529034805u32.to_string()),
            attr("relayer_fee", "0"),
            attr("token_fee", "0"),
            attr(
                "timeout_timestamp",
                &mock_env()
                    .block
                    .time
                    .plus_seconds(3600)
                    .seconds()
                    .to_string()
            ),
            attr("remote_amount", "10000"),
            attr("seq", "1"),
            attr("recovery_addr", "sender"),
        ]
    );
}

#[test]
fn test_bridge_to_ton_with_fee() {
    let mut deps = mock_dependencies();
    instantiate(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        InstantiateMsg {
            validator_contract_addr: Addr::unchecked("validator_contract_addr"),
            bridge_adapter: "bridge_adapter".to_string(),

            token_fee_receiver: Addr::unchecked("token_fee_receiver"),
            relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),

            swap_router_contract: "swap_router_contract".to_string(),
            token_factory_addr: None,
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        },
    )
    .unwrap();

    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked("orai"),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode: opcode.clone(),
            token_origin: 529034805,
            relayer_fee: Uint128::new(1000),
        }),
    )
    .unwrap();

    // add token fee
    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: None,
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: Some(vec![TokenFee {
                token_denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
                ratio: Ratio {
                    nominator: 1,
                    denominator: 1000,
                },
            }]),
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
    )
    .unwrap();

    increase_channel_balance(
        deps.as_mut().storage,
        "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB",
        Uint128::from(1000000000u128),
    )
    .unwrap();

    let res = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("orai", &vec![]),
        ExecuteMsg::Receive(Cw20ReceiveMsg {
            sender: "sender".to_string(),
            amount: Uint128::from(10000u128),
            msg: to_json_binary(&BridgeToTonMsg {
                to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
                denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
                timeout: None,
                recovery_addr: None,
            })
            .unwrap(),
        }),
    )
    .unwrap();
    assert_eq!(
        res.messages,
        vec![
            SubMsg::new(CosmosMsg::Wasm(WasmMsg::Execute {
                contract_addr: "orai".to_string(),
                msg: to_json_binary(&Cw20ExecuteMsg::Transfer {
                    recipient: "token_fee_receiver".to_string(),
                    amount: Uint128::from(10u128)
                })
                .unwrap(),
                funds: vec![],
            })),
            SubMsg::new(CosmosMsg::Wasm(WasmMsg::Execute {
                contract_addr: "orai".to_string(),
                msg: to_json_binary(&Cw20ExecuteMsg::Transfer {
                    recipient: "relayer_fee_receiver".to_string(),
                    amount: Uint128::from(1000u128)
                })
                .unwrap(),
                funds: vec![],
            }))
        ]
    );
    assert_eq!(
        res.attributes,
        vec![
            attr("action", "send_to_ton"),
            attr("opcode_packet", SEND_TO_TON_MAGIC_NUMBER.to_string()),
            attr("local_sender", "sender"),
            attr(
                "remote_receiver",
                "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT"
            ),
            attr(
                "remote_denom",
                "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB"
            ),
            attr("local_amount", "8990"),
            attr("token_origin", &529034805u32.to_string()),
            attr("relayer_fee", "1000"),
            attr("token_fee", "10"),
            attr(
                "timeout_timestamp",
                &mock_env()
                    .block
                    .time
                    .plus_seconds(3600)
                    .seconds()
                    .to_string()
            ),
            attr("remote_amount", "8990"),
            attr("seq", "1"),
            attr("recovery_addr", "sender"),
        ]
    );

    // set relayer fee = 0

    execute(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked("orai"),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
    )
    .unwrap();
    let res = execute(
        deps.as_mut(),
        mock_env(),
        mock_info("orai", &vec![]),
        ExecuteMsg::Receive(Cw20ReceiveMsg {
            sender: "sender".to_string(),
            amount: Uint128::from(10000u128),
            msg: to_json_binary(&BridgeToTonMsg {
                to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
                denom: "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB".to_string(),
                timeout: None,
                recovery_addr: None,
            })
            .unwrap(),
        }),
    )
    .unwrap();
    assert_eq!(
        res.messages,
        vec![SubMsg::new(CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr: "orai".to_string(),
            msg: to_json_binary(&Cw20ExecuteMsg::Transfer {
                recipient: "token_fee_receiver".to_string(),
                amount: Uint128::from(10u128)
            })
            .unwrap(),
            funds: vec![],
        })),]
    );
    assert_eq!(
        res.attributes,
        vec![
            attr("action", "send_to_ton"),
            attr("opcode_packet", &SEND_TO_TON_MAGIC_NUMBER.to_string()),
            attr("local_sender", "sender"),
            attr(
                "remote_receiver",
                "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT"
            ),
            attr(
                "remote_denom",
                "EQA5FnPP13uZPJQq7aj6UHLEukJJZSZW053cU1Wu6R6BpYYB"
            ),
            attr("local_amount", "9990"),
            attr("token_origin", &529034805u32.to_string()),
            attr("relayer_fee", "0"),
            attr("token_fee", "10"),
            attr(
                "timeout_timestamp",
                &mock_env()
                    .block
                    .time
                    .plus_seconds(3600)
                    .seconds()
                    .to_string()
            ),
            attr("remote_amount", "9990"),
            attr("seq", "2"),
            attr("recovery_addr", "sender"),
        ]
    );
}

#[test]
fn test_build_mint_msg_by_token_factory() {
    let MockApp {
        token_factory_addr, ..
    } = new_mock_app();
    let receiver = Addr::unchecked("receiver");

    let msg = build_mint_asset_msg(
        Some(token_factory_addr.clone()),
        &Asset {
            amount: Uint128::from(10000u128),
            info: AssetInfo::NativeToken {
                denom: "ton".to_string(),
            },
        },
        receiver.clone().into_string(),
    )
    .unwrap();

    assert_eq!(
        msg,
        CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr: token_factory_addr.to_string(),
            msg: to_json_binary(&tokenfactory::msg::ExecuteMsg::MintTokens {
                denom: "ton".to_string(),
                amount: Uint128::from(10000u128),
                mint_to_address: receiver.into_string(),
            })
            .unwrap(),
            funds: vec![],
        })
    );
}

#[test]
fn test_build_burn_msg_by_token_factory() {
    let MockApp {
        token_factory_addr, ..
    } = new_mock_app();
    let receiver = Addr::unchecked("receiver");

    let msg = build_burn_asset_msg(
        Some(token_factory_addr.clone()),
        &Asset {
            amount: Uint128::from(10000u128),
            info: AssetInfo::NativeToken {
                denom: "ton".to_string(),
            },
        },
        receiver.clone().into_string(),
    )
    .unwrap();

    assert_eq!(
        msg,
        CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr: token_factory_addr.to_string(),
            msg: to_json_binary(&tokenfactory::msg::ExecuteMsg::BurnTokens {
                denom: "ton".to_string(),
                amount: Uint128::from(10000u128),
                burn_from_address: receiver.into_string(),
            })
            .unwrap(),
            funds: vec![],
        })
    );
}

#[test]
fn test_happy_case_token_factory() {
    // Transaction used for this test case: https://testnet.tonviewer.com/transaction/aec51d2faa4c0889f691bcbd2f69f805986516a378ccae4628eec2b8c17b0198
    // Here I bridge usdt to Oraichain and mint it as token factory token
    let MockApp {
        mut app,
        owner,
        bridge_addr,
        token_factory_addr,
        validator_addr,
        ..
    } = new_mock_app();

    app.set_block_time_seconds(1000);

    println!("block time {}", app.get_block_time().seconds());

    // update config to mutate bridge adapter address
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: Some(validator_addr.clone()),
            bridge_adapter: Some("EQAFzUWT10H8NZtXn5sFrv_MmrfMe3iJJJV_JDHUPR0PdVHh".to_string()),
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: None,
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap();

    // create denom
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::RegisterDenom(
            tonbridge_bridge::msg::RegisterDenomMsg {
                subdenom: "usdt".to_string(),
                metadata: None,
            },
        ),
        &coins(10_000_000u128, "orai"),
    )
    .unwrap();

    let denom = format!("factory/{}/usdt", token_factory_addr.to_string()).to_string();

    // update mapping
    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000001")
            .unwrap();

    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: "EQAX_18eFGby3HZaB0vr95rg5Te3kHoaUOLG3iS_QjtMJNg9".to_string(), // usdt contract
            local_asset_info: AssetInfo::NativeToken {
                denom: denom.to_string(),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::zero(),
        }),
        &[],
    )
    .unwrap();

    // set verified block
    app.execute(
        owner.clone(),
        validator_addr.clone(),
        &tonbridge_validator::msg::ExecuteMsg::SetVerifiedBlock {
            root_hash: HexBinary::from_hex(
                "11f786de79ad426e88ce5f09df1e4e99ae7deaddef91be439fad5628c64b7d41",
            )
            .unwrap(),
            seq_no: 21464841,
        },
        &[],
    )
    .unwrap();

    // verify shard block
    app.execute(owner.clone(), validator_addr.clone(),&tonbridge_validator::msg::ExecuteMsg::VerifyShardBlocks {
        mc_block_root_hash: HexBinary::from_hex(
            "11f786de79ad426e88ce5f09df1e4e99ae7deaddef91be439fad5628c64b7d41",
        )
        .unwrap(),
        shard_proof_links: vec![
            HexBinary::from_hex(
                "b5ee9c72010214010002790009460311f786de79ad426e88ce5f09df1e4e99ae7deaddef91be439fad5628c64b7d41001701241011ef55aafffffffd020304052848010111a70415d93f861d5b1dcb8aac3b36b8a5a7d1cf4ab48d269296f984e3433fb10001284801014d3b19a7efc9dc2a71d96307bc08b20f4dabb9dd43b37863e1e849acf1f0948f0003284801016c04b8e2ac4f53dafff33d4fef852aa128ba0e13ca134c1a02ddb1a4b89b9978001624894a33f6fd4a7ff3ff2b5ad717867ca3606a50baa0ae44bebbaa6b93a8d915cbc10d6bd070133ef3ab24477263613687ee57f917649795fc86eac3f4f0d6857cfa5e87e96dc006070809284801019134b8cf7d0bcb35eb2507206267e3f28cf788e6e92aca317533d140ce87ed96000400010228480101dc6723c5ad75303f405ca1a3f92f23972452d52b7e185231d81ed004b44c5f5100062317cca568d88bf7024684ee18040a0b0c2103d0400d2848010117efd5f43c1957d33a15a5b68e9bcf13ecc5f78d7b1563da0f6b18ac0513d84d0002210150132201c00e0f2201c010112848010153fd5319d537db40029cbe99cba2a0ed9a75c5b20a279870bf59dc700e565d00000201db500afc02780a3c38480000af8a0721c0000000af8a0721c009bff36e49ee3413aa4989027e4d3d3760150f47ea9d66145f0456033e8fdfed8ab908199311a96370770ff3870756d9947115d656e0122c4b25cd975d64e4ee88800023da6100000000000000000a3c383335285a621228480101ea66196bfe106add86fc565d9ce9fa521aac6037e43dfc8428583f1c72dcd62d0001001341e3da05520ee6b2802028480101439558d502c16dc8b7653426f214deab76586ca2c56f23ab98b48b5267eed8bc0003",
            )
            .unwrap(),
            HexBinary::from_hex(
                "b5ee9c72010208010001960009460337fe6dc93dc682754931204fc9a7a6ec02a1e8fd53acc28be08ac067d1fbfdb1000501241011ef55aafffffffd0203040502a09bc7a987000000008401015f804f000000000200000000000000000000000066a50b4c000015f140e43800000015f140e438014d4af0b900047b4c0147870601478393c40000000800000000000001ee060728480101fcf00788fd51e3bc42a1d5379da3afdb1b31b17a6eb86ff5ee158202c1f02d770001284801017c88382b17de0be074a0053d1e056a7271d7b7c23b0c4b469a8da990b0da32d3000428480101115a57b53b90f009f12446afc450de68834146b01f014d96cbdb07ad69dc529000010098000015f140d4f5c4014787075bfa5a9407caa943497759faf565d96fe8d4d675ed72a964cec001eb440b335a3eae995fe699666a48287cf910c5f2a0818b14a1a0a20b5a83ae97135e6436ae0098000015f140d4f5c4015f804ec3ee48fcfb1951c41df4cc1ceb1b68e7dabc32182746e36bcb3090f14bad0af4cdd2b41c9af274705c299d8c79406ae3c328623ac1d192c91c3b3caddcd4627c",
            )
            .unwrap(),
        ],
    },&[]).unwrap();

    // verify tx block
    let res = app.execute(owner.clone(), bridge_addr.clone(),&tonbridge_bridge::msg::ExecuteMsg::ReadTransaction {
        tx_boc: HexBinary::from_hex("b5ee9c72010211010003450003b5705cd4593d741fc359b579f9b05aeffcc9ab7cc7b788924957f2431d43d1d0f75000015f140d4f5c1a36f23584818716259d1b12d4a1a60b8c6f4df29976e6721a4eff339660d9870000015f14079684366a50b4a000546c4674280102030201e004050082725bc12430b7094c9649826b0550b887a42522f80b11bbda296bc4a0ae8f3c3a82a7307e385b80e3e85fa6aed19a5cf24d56d64f18e3628d26fe9f745f2f48d8110217044389021cc38c186a3fd4110f1001b16801ed89e454ebd04155a7ef579cecc7ff77907f2288f16bb339766711298f1f77570001735164f5d07f0d66d5e7e6c16bbff326adf31ede2249255fc90c750f4743dd5021cc38c00612b38a00002be2814e5e04cd4a1686c0060201dd08090118af35dc850000000000000000070285ffff8002ffebe3c28cde5b8ecb40e97d7ef35c1ca6f6f20f434a1c58dbc497e8476984844e2000000000cd4a326e299beee0c4cf91a62d47583c7745120351acd2a5810e0d0101200a0101200b00c948000b9a8b27ae83f86b36af3f360b5dff99356f98f6f112492afe4863a87a3a1eeb000a6d5ffc41ad5e8e3dc6466573d7f527c4e37a1b249e3c778be1b9c90c140f8a10206bd4400608235a00002be281a9eb84cd4a16946a993b6d800000000000000040019fe0002e6a2c9eba0fe1acdabcfcd82d77fe64d5be63dbc44924abf9218ea1e8e87bab004e144dd2dfc339aa2639312e1cd6f5d35a03924795906c1a4d156fb124e7097a000015f140d4f5c366a50b4a600c02bda64c12a300000000000000011f886e35000000000000000000000000000027100000000066a5193714cdf7706267c8d316a3ac1e3ba28901a8d66952c08002ffebe3c28cde5b8ecb40e97d7ef35c1ca6f6f20f434a1c58dbc497e8476984900d0e0043800536affe20d6af471ee32332b9ebfa93e271bd0d924f1e3bc5f0dce4860a07c5100000009e468f4c15a16c0000000000000000f400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc98a23504c40d3cc0000000000040000000000053a3508ffc6a9d6d2c621844cb7fe15d925624c39aabb75f4d0c992e64911db9641504ccc").unwrap(),
        tx_proof: HexBinary::from_hex("b5ee9c72010210010002fb00094603c3ee48fcfb1951c41df4cc1ceb1b68e7dabc32182746e36bcb3090f14bad0af4001f01241011ef55aafffffffd0203040502a09bc7a987000000008401015f804e000000000200000000000000000000000066a50b4a000015f140d4f5c0000015f140d4f5c44d4af0b900047b4c0147870601478393c40000000800000000000001ee06072848010167650f78a9eae9494f5a3a0b4ffa657c3de887d6657294db573277968937141a000128480101cc14e21c72a1dc48a74e278dd596d7b0ca90e8c2ca12b1f89b3f62b729b86a17001e23894a33f6fdc540aa39b755ffae32b04c425d2c46501e831aba8f7fb18c819bb6b60a37477855ba839d64291c2e272d37bed587debc8653dbb1f6342747bb3447681533dfbf4008090a0098000015f140c5b3840147870601160693e59aeda77a71c6a85c3206e624c2b876589909f1046434be0495ec8db37737bf2aea702ee9a183ee2b94b6f35aaebd83180fc2a3ccce2c36e7320ba90098000015f140c5b381015f804d60808aef9591c0f3065403bb60937021674a049c05e60624539d2f1b0e508179a206b4ebab6fd3727aa62830bfe6274ec01efb73bad093fcf7da98136591c04d28480101f266622e77d2b020b40dda4ec40655bbe76865265760a595147c6d4958617137000928480101747427c412a5ddbbc3933125b9b2956d23c18c48b511a51311aa10ac6b2529dc000a21079b167f1a0b220960d8b3f8d00c0d22a3bf4b9a8b27ae83f86b36af3f360b5dff99356f98f6f112492afe4863a87a3a1eea6c46742505cd4593d741fc359b579f9b05aeffcc9ab7cc7b788924957f2431d43d1d0f75a000000af8a06a7ae09b119d0a0e0f284801014518eb72f99744912489062273d29c4efa158e17c0ab7c7188438932f55a9824000328480101f6532afe25bf35a0e13fef84792cb35fde2c1fcdbed78ce321413413bdce75df00060082725bc12430b7094c9649826b0550b887a42522f80b11bbda296bc4a0ae8f3c3a82a7307e385b80e3e85fa6aed19a5cf24d56d64f18e3628d26fe9f745f2f48d811").unwrap(),
    },&[]).unwrap();
    println!("Res: {:?}", res);
    let receiver = Addr::unchecked("orai1ehmhqcn8erf3dgavrca69zgp4rtxj5kqgtcnyd");
    let sender_balance = app.query_balance(receiver.clone(), denom.clone()).unwrap();
    assert_eq!(sender_balance.u128(), 10000);

    // app.execute(
    //     owner.clone(),
    //     bridge_addr.clone(),
    //     &tonbridge_bridge::msg::ExecuteMsg::BridgeToTon(BridgeToTonMsg {
    //         denom: "EQAX_18eFGby3HZaB0vr95rg5Te3kHoaUOLG3iS_QjtMJNg9".to_string(), // usdt contract
    //         timeout: Some(123), // just random number for timeout in Ton contract
    //         to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
    //         recovery_addr: None,
    //     }),
    //     &coins(1000, denom.clone()),
    // )
    // .unwrap();
    // let sender_balance = app.query_balance(owner.clone(), denom.clone()).unwrap();
    // assert_eq!(sender_balance.u128(), 9000);

    // // check packet commitment exist
    // let packet_commitment: Uint256 = app
    //     .query(
    //         bridge_addr.clone(),
    //         &tonbridge_bridge::msg::QueryMsg::SendPacketCommitment { seq: 1 },
    //     )
    //     .unwrap();
    // let receiver = Addr::unchecked("orai1ehmhqcn8erf3dgavrca69zgp4rtxj5kqgtcnyd");
    // let sender_balance = app.query_balance(receiver.clone(), denom.clone()).unwrap();
    // assert_eq!(sender_balance.u128(), 10000);

    // app.execute(
    //     receiver.clone(),
    //     bridge_addr.clone(),
    //     &tonbridge_bridge::msg::ExecuteMsg::BridgeToTon(BridgeToTonMsg {
    //         denom: "EQAX_18eFGby3HZaB0vr95rg5Te3kHoaUOLG3iS_QjtMJNg9".to_string(), // usdt contract
    //         timeout: Some(123), // just random number for timeout in Ton contract
    //         to: "EQABEq658dLg1KxPhXZxj0vapZMNYevotqeINH786lpwwSnT".to_string(),
    //     }),
    //     &coins(1000, denom.clone()),
    // )
    // .unwrap();
    // let sender_balance = app.query_balance(owner.clone(), denom.clone()).unwrap();
    // assert_eq!(sender_balance.u128(), 9000);

    // // check packet commitment exist
    // let packet_commitment: Uint256 = app
    //     .query(
    //         bridge_addr.clone(),
    //         &tonbridge_bridge::msg::QueryMsg::SendPacketCommitment { seq: 1 },
    //     )
    //     .unwrap();
    // println!("Packet commitment: {:?}", packet_commitment);

    // // active timeout case
    // // set verified block
    // app.execute(
    //     owner.clone(),
    //     validator_addr.clone(),
    //     &tonbridge_validator::msg::ExecuteMsg::SetVerifiedBlock {
    //         root_hash: HexBinary::from_hex(
    //             "1dbdf6c3a0e6403743f4f044e3482b41117bdc55105cca1e470395cb62f301fe",
    //         )
    //         .unwrap(),
    //         seq_no: 21513044,
    //     },
    //     &[],
    // )
    // .unwrap();

    // // verify shard block
    // app.execute(owner.clone(), validator_addr.clone(),&tonbridge_validator::msg::ExecuteMsg::VerifyShardBlocks {
    //     mc_block_root_hash: HexBinary::from_hex(
    //         "1dbdf6c3a0e6403743f4f044e3482b41117bdc55105cca1e470395cb62f301fe",
    //     )
    //     .unwrap(),
    //     shard_proof_links: vec![
    //         HexBinary::from_hex(
    //             "b5ee9c720102140100029c000946031dbdf6c3a0e6403743f4f044e3482b41117bdc55105cca1e470395cb62f301fe001c01241011ef55aafffffffd0203040528480101f7b02a9ab86c227e407ab753f69c9d9c3dd3a073bccff9562642f3788a95367a0001284801012baaf8e264d4166febb2f334860082faea0d98d1f7ddf852c95160ef6d31324f000328480101da936546c64177b2944610bbc980a8bccf720eb41c7f27c63da5db65d041743d001b24894a33f6fd8bd93ace296c723843fc85ca4bd223dca4cdcb1a373efb093ae0abe96d1827ec83a84ba692374de961fe6e2124bee1df1449b3a47a98a103c09cb894f50309e4c006070809284801018b65ed79386c9472a2e1872d721f8b9a669c1a1514d34458749698b0173af6c40009284801015ab0d4a68fb1b59a3e91a51ef8c415c0296171177ec1c55067a3c1d7a95bbf6f00092848010133510da93049a7f962c359d309a008f2d362afb30cc82b5424e7508f90b053a7000b2317cca5685ad6384e42cb4178040a0b0c2103d0400d2848010146d602e6bb2e2ee54d4c8b790331fdee18ea857983ab58500f5f40f8d5fcad300002210150132201c00e0f2201c01011284801012e009a1f5b4109941e6dd3eff2997ba66acab3957a73d0d5456ce23b47cec0a9000201db500b0255000a421aa00000aff0670e44000000aff0670e443dea22e7fea32d0af5d6839840d8cea1a699a60088b1fdf5a9d95b3fa1d9479652ec77b5ae2bb9dbcd0176456eb89bae9f8be7b5bb8f37339a0201833acc02fd30800023ec5100000000000000000a421a8b3538835212284801010bc77b4297ff68a6b47696ec294601555feac35afe533dd112005a9efe01486f0001001340f9db7272077359402028480101819591975d9ba757d70334539dae4041ddb3b803c5f9fbf5cee8aa9d76ea6caa0003"
    //         )
    //         .unwrap(),
    //     ],
    // },&[]).unwrap();

    // // verify tx block
    // let res = app.execute(owner.clone(), bridge_addr.clone(),&tonbridge_bridge::msg::ExecuteMsg::ReadTransaction {
    //     tx_boc: HexBinary::from_hex("b5ee9c7201020c010002120003b5705cd4593d741fc359b579f9b05aeffcc9ab7cc7b788924957f2431d43d1d0f75000015fe0ce1c88543a47496a1c10c55ae4ea0fac552161cf37113fdedc36fbe7de167fac4582f83000015fe0ce1c88366a7106a00034678276080102030201e0040500827276bd09e213392c99262fb24da3698b62ecc2c2ade4d78e6795fe790c5c8cd889b7d2e9c290c4e869f32832850e9fb1d7dba2957b7270d24007072903fdafe92802130408dbbc001866987a110a0b01af68000b9a8b27ae83f86b36af3f360b5dff99356f98f6f112492afe4863a87a3a1eeb0001735164f5d07f0d66d5e7e6c16bbff326adf31ede2249255fc90c750f4743dd4dbbc000060a8c0600002bfc19c39108cd4e20d4c0060101df0801181ae4fbbb0000000000000000070000019fe0002e6a2c9eba0fe1acdabcfcd82d77fe64d5be63dbc44924abf9218ea1e8e87bab004e144dd2dfc339aa2639312e1cd6f5d35a03924795906c1a4d156fb124e7097a000015fe0ce1c88666a7106a60090019ae89be5b0000000000000001a0009c4438a91c000000000000000000a100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc983a7f04c1d3f80000000000002000000000002f6baf589033f725cc7cd5f93ee12841f9bf962f604d45dd2d03e91c635847a9a409016e4").unwrap(),
    //     tx_proof: HexBinary::from_hex("b5ee9c720102140100035800094603bd445cffd465a15ebad073081b19d434d334c011163fbeb53b2b67f43b28f2ca001e01241011ef55aafffffffd0203040502a09bc7a98700000000840101604aa0000000000200000000000000000000000066a7106a000015fe0ce1c880000015fe0ce1c887ebda212700047d890148435101483bdec40000000800000000000001ee060728480101d53ae37cff4f42cdcfa13e8080a3bb5782d5681b9f969ab3fd96468bdd8559c800012848010124f95b9a61f67cff887c026396ff068272944ab44c349bf57cad866165613e42001d23894a33f6fd0eada71d832bdf383c2e650947ad2f3aea6f7d398764a0ce286f93a8f8f491aedca8416ad47b174aae57a82e41b10e17240eb3b75c7d0c179378713a432c738c4008090a0098000015fe0cd2864401484351774dfb269dad3f065ac2d5bf0e3fcb63bb57a180b8a0ae960a0de08c8937e428bad98b4c3b2b9ab384349b5f54eb3ba7bdc413600034ab91a73ac4759d5ae1570098000015fe0cd2864601604a9f0179d4d990e1997a634dddc0d093fad50c3ffd3d1556dfaa5281ff600b89f06517939154393ec4155a691397144ca8eab91767572478d0c59537faf4001a0e1a28480101b206130edf2d5098671f82b37e8694c4a3db2aba3c33b368e0029607c9f0876900092848010119dc6fe2d49ad87a460ebf9de73a75150bbf110861b0143c9d0af3af5705f7bf000c21079d648d0a0b220960eb2468500c0d22070e3107090e0f2848010162f9e5482518e29e3e2424856a17c191ec9e944b92e5478ec4edf4af8e254dbe000623a3bf1735164f5d07f0d66d5e7e6c16bbff326adf31ede2249255fc90c750f4743dd4d81d108a0b9a8b27ae83f86b36af3f360b5dff99356f98f6f112492afe4863a87a3a1eeb3d000015fe0ce1c881b03a212010111228480101a159c5c1074d4ab48ed154f45baea0da74faf8a13e1eae64c9d9ef2c626b84760005284801011ad34fc8c119c14c2eb2411480c9abc06d0308e214979d1d252d18fab8e20c7d0006210964cf04ec1013008272595338af06028f98fef5ee6279a4b8dc5b1aa50724184340b85f633e3c616226b7d2e9c290c4e869f32832850e9fb1d7dba2957b7270d24007072903fdafe92828480101f9cb28f3a48a71c117a14d69a7a6d3c02e882679bb93280c699fb19b73cdb48e0004").unwrap(),
    // },&[]).unwrap();
    // println!("Res: {:?}", res);
    // let sender_balance = app.query_balance(owner.clone(), denom.clone()).unwrap();
    // assert_eq!(sender_balance.u128(), 10000);
}

#[test]
fn test_refund_bridge_to_ton() {
    let mut deps = mock_dependencies();
    instantiate(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        InstantiateMsg {
            validator_contract_addr: Addr::unchecked("validator_contract_addr"),
            bridge_adapter: "bridge_adapter".to_string(),
            token_fee_receiver: Addr::unchecked("token_fee_receiver"),
            relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
            swap_router_contract: "swap_router_contract".to_string(),
            token_factory_addr: Some(Addr::unchecked("token_factory")),
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        },
    )
    .unwrap();

    let seq = 1u64;

    let send_packet = TimeoutSendPacket {
        local_refund_asset: Asset {
            info: AssetInfo::NativeToken {
                denom: "ton_orai".to_string(),
            },
            amount: Uint128::new(1000000),
        },
        remote_denom: "ton".to_string(),
        remote_amount: Uint128::new(1000000000),
        sender: "sender".to_string(),
        timeout_timestamp: mock_env().block.time.seconds(),
        opcode: OPCODE_1,
        recovery_addr: None,
    };
    REMOTE_INITIATED_CHANNEL_STATE
        .save(deps.as_mut().storage, "ton", &ChannelState::default())
        .unwrap();

    // case 1: not found send_packet => error
    let mut cell_builder = CellBuilder::new();
    cell_builder
        .store_slice(&SEND_TO_TON_MAGIC_NUMBER.to_be_bytes())
        .unwrap();
    cell_builder.store_slice(&seq.to_be_bytes()).unwrap();
    cell_builder.store_u8(2, 2).unwrap();
    let cell = cell_builder.build().unwrap();

    let err = on_acknowledgment(deps.as_mut(), &cell);
    assert!(err.is_err());

    // refund success (mint token)
    // before refund, channel balance = 0;
    let channel_balance = REMOTE_INITIATED_CHANNEL_STATE
        .load(deps.as_ref().storage, "ton")
        .unwrap();
    assert_eq!(
        channel_balance,
        ChannelState {
            outstanding: Uint128::new(0),
            total_sent: Uint128::new(0)
        }
    );

    SEND_PACKET
        .save(deps.as_mut().storage, seq, &send_packet)
        .unwrap();

    let res = on_acknowledgment(deps.as_mut(), &cell).unwrap();
    // before refund, channel balance updated;
    let channel_balance = REMOTE_INITIATED_CHANNEL_STATE
        .load(deps.as_ref().storage, "ton")
        .unwrap();
    assert_eq!(
        channel_balance,
        ChannelState {
            outstanding: Uint128::new(1000000000),
            total_sent: Uint128::new(1000000000)
        }
    );
    assert_eq!(
        res.1,
        vec![
            attr("action", "acknowledgment"),
            attr("seq", "1"),
            attr("status", "Timeout")
        ]
    );
    assert_eq!(
        res.0,
        vec![CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr: "token_factory".to_string(),
            msg: to_json_binary(&tokenfactory::msg::ExecuteMsg::MintTokens {
                denom: "ton_orai".to_string(),
                amount: Uint128::new(1000000),
                mint_to_address: "sender".to_string(),
            })
            .unwrap(),
            funds: vec![],
        })]
    );

    // refund by sendToken
    let send_packet = TimeoutSendPacket {
        local_refund_asset: Asset {
            info: AssetInfo::NativeToken {
                denom: "ton_orai".to_string(),
            },
            amount: Uint128::new(1000000),
        },
        remote_denom: "ton".to_string(),
        remote_amount: Uint128::new(1000000000),
        sender: "sender".to_string(),
        timeout_timestamp: mock_env().block.time.seconds(),
        opcode: OPCODE_2,
        recovery_addr: None,
    };
    SEND_PACKET
        .save(deps.as_mut().storage, seq, &send_packet)
        .unwrap();
    let res = on_acknowledgment(deps.as_mut(), &cell).unwrap();
    assert_eq!(
        res.0,
        vec![CosmosMsg::Bank(BankMsg::Send {
            to_address: "sender".to_string(),
            amount: vec![Coin {
                denom: "ton_orai".to_string(),
                amount: Uint128::new(1000000),
            }]
        })]
    );
}

#[test]
fn test_refund_bridge_to_ton_with_recovery_addr() {
    let mut deps = mock_dependencies();
    instantiate(
        deps.as_mut(),
        mock_env(),
        mock_info("owner", &vec![]),
        InstantiateMsg {
            validator_contract_addr: Addr::unchecked("validator_contract_addr"),
            bridge_adapter: "bridge_adapter".to_string(),
            token_fee_receiver: Addr::unchecked("token_fee_receiver"),
            relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
            swap_router_contract: "swap_router_contract".to_string(),
            token_factory_addr: Some(Addr::unchecked("token_factory")),
            osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
        },
    )
    .unwrap();

    let seq = 1u64;

    let send_packet = TimeoutSendPacket {
        local_refund_asset: Asset {
            info: AssetInfo::NativeToken {
                denom: "ton_orai".to_string(),
            },
            amount: Uint128::new(1000000),
        },
        remote_denom: "ton".to_string(),
        remote_amount: Uint128::new(1000000000),
        sender: "sender".to_string(),
        timeout_timestamp: mock_env().block.time.seconds(),
        opcode: OPCODE_1,
        recovery_addr: Some(Addr::unchecked("recovery_addr")),
    };
    REMOTE_INITIATED_CHANNEL_STATE
        .save(deps.as_mut().storage, "ton", &ChannelState::default())
        .unwrap();

    // case 1: not found send_packet => error
    let mut cell_builder = CellBuilder::new();
    cell_builder
        .store_slice(&SEND_TO_TON_MAGIC_NUMBER.to_be_bytes())
        .unwrap();
    cell_builder.store_slice(&seq.to_be_bytes()).unwrap();
    cell_builder.store_u8(2, 2).unwrap();
    let cell = cell_builder.build().unwrap();

    let err = on_acknowledgment(deps.as_mut(), &cell);
    assert!(err.is_err());

    // refund success (mint token)
    // before refund, channel balance = 0;
    let channel_balance = REMOTE_INITIATED_CHANNEL_STATE
        .load(deps.as_ref().storage, "ton")
        .unwrap();
    assert_eq!(
        channel_balance,
        ChannelState {
            outstanding: Uint128::new(0),
            total_sent: Uint128::new(0)
        }
    );

    SEND_PACKET
        .save(deps.as_mut().storage, seq, &send_packet)
        .unwrap();

    let res = on_acknowledgment(deps.as_mut(), &cell).unwrap();
    // before refund, channel balance updated;
    let channel_balance = REMOTE_INITIATED_CHANNEL_STATE
        .load(deps.as_ref().storage, "ton")
        .unwrap();
    assert_eq!(
        channel_balance,
        ChannelState {
            outstanding: Uint128::new(1000000000),
            total_sent: Uint128::new(1000000000)
        }
    );
    assert_eq!(
        res.1,
        vec![
            attr("action", "acknowledgment"),
            attr("seq", "1"),
            attr("status", "Timeout")
        ]
    );
    assert_eq!(
        res.0,
        vec![CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr: "token_factory".to_string(),
            msg: to_json_binary(&tokenfactory::msg::ExecuteMsg::MintTokens {
                denom: "ton_orai".to_string(),
                amount: Uint128::new(1000000),
                mint_to_address: "recovery_addr".to_string(),
            })
            .unwrap(),
            funds: vec![],
        })]
    );

    // refund by sendToken
    let send_packet = TimeoutSendPacket {
        local_refund_asset: Asset {
            info: AssetInfo::NativeToken {
                denom: "ton_orai".to_string(),
            },
            amount: Uint128::new(1000000),
        },
        remote_denom: "ton".to_string(),
        remote_amount: Uint128::new(1000000000),
        sender: "sender".to_string(),
        timeout_timestamp: mock_env().block.time.seconds(),
        opcode: OPCODE_2,
        recovery_addr: Some(Addr::unchecked("recovery_addr")),
    };
    SEND_PACKET
        .save(deps.as_mut().storage, seq, &send_packet)
        .unwrap();
    let res = on_acknowledgment(deps.as_mut(), &cell).unwrap();
    assert_eq!(
        res.0,
        vec![CosmosMsg::Bank(BankMsg::Send {
            to_address: "recovery_addr".to_string(),
            amount: vec![Coin {
                denom: "ton_orai".to_string(),
                amount: Uint128::new(1000000),
            }]
        })]
    );
}

#[test]
#[cfg(not(feature = "test-tube"))]
fn test_bridge_ton_to_orai_with_fee() {
    let MockApp {
        mut app,
        owner,
        validator_addr,
        bridge_addr,
        cw20_addr,
        relayer_fee_addr,
        token_fee_addr,
        ..
    } = new_mock_app();

    // update bridge adapter contract
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: Some("EQCWH9kCKpCTpswaygq-Ah7h-1vH3xZ3gJq7-SM6ZkYiOgHH".to_string()),
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: None,
            token_factory_addr: None,
            osor_entrypoint_contract: None,
        },
        &[],
    )
    .unwrap();

    let tx_boc = HexBinary::from_hex("b5ee9c72010211010003450003b57961fd9022a9093a6cc1aca0abe021ee1fb5bc7df1677809abbf9233a6646223a00002b5df4ae0c41591328d8b3673d4b795f57c789e145481d3b1d2413af77a28086813032f2cf0c00002b5df4527ec1668fba29000546e2689c80102030201e0040500827298457e3ebcfa880e4a67df0d88c69cca63a7ca8de9234ad23dbe051f586d8469b9aa5df59ef1ad564d84695fd6c9182ef92b205953a7da224579e187466403bb02170446c91cef574c186c1fe8110f1001b1680026199d4cf9ecc6786607ea6ab5d07ebb2b7300531ce1d62713126b93e9b547fb002587f6408aa424e9b306b282af8087b87ed6f1f7c59de026aefe48ce9991888e91cef574c00612b38a000056bbe9008b04cd1f743ac0060201dd08090118af35dc850000000000000000070285ffff800e538276dbe580f97e140d56c7a695e8a9e7a641d8379b1f6b8da49a100d42f8444e2000000000cd1f574c299beee0c4cf91a62d47583c7745120351acd2a5810e0d0101200a0101200b00c948012c3fb2045521274d983594157c043dc3f6b78fbe2cef013577f24674cc8c44750005b94eca7698c8dafacc801ff8f0f63edae1d14809c6871dcabcc6ed24fbf63391cd590dc00608235a000056bbe95c1884cd1f74526a993b6d800000000000000040019fe004b0fec81154849d3660d65055f010f70fdade3ef8b3bc04d5dfc919d3323111d30010926e9e39e0b6f991fe801420858017cc708d639ef898187dc61b9eac89901a00002b5df4ae0c43668fba29600c02bda64c12a300000000000000071f886e350000000000000000000000000000271000000000668faba614cdf7706267c8d316a3ac1e3ba28901a8d66952c0800e538276dbe580f97e140d56c7a695e8a9e7a641d8379b1f6b8da49a100d42f8500d0e00438002dca7653b4c646d7d66400ffc787b1f6d70e8a404e3438ee55e6376927dfb19d00000009e47c28c3d09000000000000000000f200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc98a23504c40d3cc0000000000040000000000044acf306fc0346e061272572316da3988492c51b2df2a48f0fae17327c722d09c41504ccc").unwrap();
    let tx_proof = HexBinary::from_hex("b5ee9c7201021a010003e800094603eb26d6f3d075f89f8ad8bb011a6814ec6a283c697cbcc0ca2450eaad97a06327002501241011ef55aaffffff110203040502a09bc7a98700000000800102a6fa0e0000000102000000008000000000000000668fba2900002b5df4ae0c4000002b5df4ae0c4d28b29c140008f0420252443f025228dbc400000007000000000000002e06072848010169134a3a596b68d647965f54a94d98fea6b8cdca27f61d5f8117859ae80f71460003284801017bdcfc2172b6c9e181490a9960cd7b90b44dd129ebc618a416f60c0144298d38002423894a33f6fde8a3fae01eb649213b6347684dcdd1bea74a224138fe572d3b2b41d156d02415ea2e404dd0ee02412f2a7791d30abd074ec16256fa83cd5376d4b0fbcfddf8df4008090a009800002b5df49eca040252443fadd1d2b79fce4fb274d594057b44704ff4a09d783433498401d7a3268998344d7d92a3baba00a520556b90da5731b089013a8491278cf99870417e8178cd5028009800002b5df49eca0a02a6fa0dad0968c77acc29e9847831a33ecf1005ea8b189a9fc33fc9a640718d23639083a9e2bf177215b1ed5d4f8737860e81c9f3ae9669024ecaedde03957abf34359a2848010126a390200ef92244737858b673f1eddffd1c0b96fc85d754efbdaab26a28ec2c001c284801019a90185f6324eab6c87c27f5a8ff53ea2a129b6b519e9d95f81c4dbb648b0cdf001c2109a0773e1bc20b220b6903b9f0de100c0d2209101d4c77b50e0f28480101d6b60f4f983236f3b9e6a5b198a318ecb28bb7b5b1df54711cdaf4142f300e85001928480101df692049ca7bbaa2a47bf4008e104f7f11838553b7883c8dc39d865f57145524001322091015c153d910112209100cb12509121328480101812da7fe1eab36c72bf9174ae0dfd6ed4477180a7090ed81503a3e27a3aa9fe9000d284801016a53739349b426fbaa9093865a46d4986f351f269f1a24e94596ab9afea86f05001322091008bed0f514152848010173151c552b62a83c7ff320b32184eb6219e12e8d6aaba1c40061cec12c5ca742000a22091004e5ff19161722a3be07f6408aa424e9b306b282af8087b87ed6f1f7c59de026aefe48ce9991888e8dc4d138b2c3fb2045521274d983594157c043dc3f6b78fbe2cef013577f24674cc8c44754000002b5df4ae0c41371344e40181928480101f8c0756de82229a358f03b021ba0c2cd31ddfcf3b220192248fd05b7ddfc425f001228480101f070dea8890cc35e161d5c3019d8e8b195dff34ffd2ef60b975727645296d338000600827298457e3ebcfa880e4a67df0d88c69cca63a7ca8de9234ad23dbe051f586d8469b9aa5df59ef1ad564d84695fd6c9182ef92b205953a7da224579e187466403bb").unwrap();

    let opcode =
        HexBinary::from_hex("0000000000000000000000000000000000000000000000000000000000000002")
            .unwrap();
    let token_denom = "EQBynBO23ywHy_CgarY9NK9FTz0yDsG82PtcbSTQgGoXwiuA";
    let packet_timeout_timestamp = 1720691622u64;

    app.set_block_time_seconds(packet_timeout_timestamp - 10);

    // update fee
    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateConfig {
            validator_contract_addr: None,
            bridge_adapter: None,
            token_fee_receiver: None,
            relayer_fee_receiver: None,
            swap_router_contract: None,
            token_fee: Some(vec![TokenFee {
                token_denom: token_denom.to_string(),
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

    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::UpdateMappingPair(UpdatePairMsg {
            denom: token_denom.to_string(),
            local_asset_info: AssetInfo::Token {
                contract_addr: Addr::unchecked(cw20_addr.clone()),
            },
            remote_decimals: 6,
            local_asset_info_decimals: 6,
            opcode,
            token_origin: 529034805,
            relayer_fee: Uint128::new(1000),
        }),
        &[],
    )
    .unwrap();

    // shard block with block hash
    let block_hash =
        HexBinary::from_hex("eb26d6f3d075f89f8ad8bb011a6814ec6a283c697cbcc0ca2450eaad97a06327")
            .unwrap();

    // set verified for simplicity
    app.execute(
        owner.clone(),
        validator_addr.clone(),
        &tonbridge_validator::msg::ExecuteMsg::SetVerifiedBlock {
            root_hash: block_hash,
            seq_no: 1,
        },
        &[],
    )
    .unwrap();

    app.set_block_time_seconds(app.get_block_time().seconds() - 10);

    app.execute(
        owner.clone(),
        bridge_addr.clone(),
        &tonbridge_bridge::msg::ExecuteMsg::ReadTransaction { tx_proof, tx_boc },
        &[],
    )
    .unwrap();

    // try query fee balance
    let relayer_balance: BalanceResponse = app
        .query(
            cw20_addr.clone(),
            &cw20_base::msg::QueryMsg::Balance {
                address: relayer_fee_addr.to_string(),
            },
        )
        .unwrap();
    assert_eq!(relayer_balance.balance, Uint128::from(1000u128));
    let token_fee_balance: BalanceResponse = app
        .query(
            cw20_addr.clone(),
            &cw20_base::msg::QueryMsg::Balance {
                address: token_fee_addr.to_string(),
            },
        )
        .unwrap();
    assert_eq!(token_fee_balance.balance, Uint128::from(10u128));
}

// TODO
// #[test]
// fn test_read_ack_transaction() {
//     let mut deps = mock_dependencies();
//     let deps_mut = deps.as_mut();
//     let seq = 1u64;
//     let mut cell_builder = CellBuilder::new();

//     // case 1: invalid no-op -> invalid packet
//     cell_builder
//         .store_slice(&RECEIVE_PACKET_MAGIC_NUMBER.to_be_bytes())
//         .unwrap();

//      let res =
// }

#[test]
fn test_ton_universal_swap() {
    let mut deps = mock_dependencies();
    let deps_mut = deps.as_mut();
    let storage = deps_mut.storage;
    let api = deps_mut.api;
    let querier = deps_mut.querier;
    let env = mock_env();

    let seq = 1;
    let token_origin = 529034805;
    let src_sender = "EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh".to_string();
    let src_denom = "EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh".to_string();
    let amount = Uint128::from(1000000000u128);

    let receiver_raw: Vec<u8> = vec![
        23, 12, 3, 5, 13, 30, 10, 3, 20, 28, 27, 5, 31, 12, 11, 15, 3, 1, 22, 13, 21, 3, 30, 20,
        12, 3, 16, 0, 11, 14, 26, 4,
    ];
    let receiver = CanonicalAddr::from(receiver_raw);

    let mut bridge_packet_data = BridgePacketData {
        seq,
        token_origin,
        timeout_timestamp: env.block.time.seconds() + DEFAULT_TIMEOUT,
        src_sender: src_sender.clone(),
        src_denom: src_denom.clone(),
        amount,
        receiver: receiver.clone(),
        memo: None,
    };

    let mapping = MappingMetadata {
        asset_info: AssetInfo::NativeToken {
            denom: "orai".to_string(),
        },
        remote_decimals: 6,
        asset_info_decimals: 6,
        opcode: OPCODE_2,
        token_origin: 529034805,
        relayer_fee: Uint128::zero(),
    };
    CONFIG
        .save(
            storage,
            &Config {
                validator_contract_addr: Addr::unchecked("validator"),
                bridge_adapter: "bridge_adapter".to_string(),
                token_fee_receiver: Addr::unchecked("token_fee_receiver"),
                relayer_fee_receiver: Addr::unchecked("relayer_fee_receiver"),
                swap_router_contract: RouterController("router".to_string()),
                token_factory_addr: None,
                osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
            },
        )
        .unwrap();
    TOKEN_FEE
        .save(
            storage,
            "orai",
            &Ratio {
                nominator: 1,
                denominator: 1000,
            },
        )
        .unwrap();

    // case 1: memo is empty, dont trigger osor contract
    let res = handle_packet_receive(
        &env,
        storage,
        api,
        &querier,
        env.block.time.seconds(),
        bridge_packet_data.clone(),
        mapping.clone(),
    )
    .unwrap();
    assert_eq!(
        res.0,
        vec![SubMsg::new(CosmosMsg::Bank(BankMsg::Send {
            to_address: "orai1ehmhqcn8erf3dgavrca69zgp4rtxj5kqgtcnyd".to_string(),
            amount: vec![Coin {
                denom: "orai".to_string(),
                amount: Uint128::new(1000000000)
            }]
        }))]
    );

    // case 2:  call universal swap
    bridge_packet_data.seq = 2;
    bridge_packet_data.memo = Some(
        CellBuilder::new()
            .store_string("abc")
            .unwrap()
            .build()
            .unwrap(),
    );
    let res = handle_packet_receive(
        &env,
        storage,
        api,
        &querier,
        env.block.time.seconds(),
        bridge_packet_data.clone(),
        mapping.clone(),
    )
    .unwrap();

    assert_eq!(
        res.0,
        vec![SubMsg::reply_on_error(
            wasm_execute(
                "osor_entrypoint_contract".to_string(),
                &EntryPointExecuteMsg::UniversalSwap {
                    memo: "abc".to_string()
                },
                vec![Coin {
                    denom: "orai".to_string(),
                    amount: Uint128::new(1000000000)
                }]
            )
            .unwrap(),
            UNIVERSAL_SWAP_ERROR_ID
        )]
    );
}
