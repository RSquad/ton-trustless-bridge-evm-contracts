use cosmwasm_std::{coins, Addr, HexBinary};

pub fn new_mock_app() -> MockApp {
    MockApp::new(None)
}

#[cfg(not(feature = "test-tube"))]
pub type TestMockApp = cosmwasm_testing_util::MultiTestMockApp;
#[cfg(feature = "test-tube")]
pub type TestMockApp = cosmwasm_testing_util::TestTubeMockApp;

pub struct MockApp {
    pub app: TestMockApp,
    pub owner: Addr,
    pub validator_addr: Addr,
    pub bridge_addr: Addr,
    pub cw20_addr: Addr,
    pub token_factory_addr: Addr,
    pub token_fee_addr: Addr,
    pub relayer_fee_addr: Addr,
}

impl MockApp {
    pub fn new(boc: Option<HexBinary>) -> Self {
        let (mut app, accounts) = TestMockApp::new(&[
            ("admin", &coins(100_000_000_000_000_000u128, "orai")),
            ("token_fee", &[]),
            ("relayer_fee", &[]),
        ]);
        let admin = Addr::unchecked(&accounts[0]);
        let token_fee_addr = Addr::unchecked(&accounts[1]);
        let relayer_fee_addr = Addr::unchecked(&accounts[2]);
        let validator_id;
        let bridge_id;
        #[cfg(not(feature = "test-tube"))]
        {
            validator_id = app.upload(Box::new(
                cosmwasm_testing_util::ContractWrapper::new_with_empty(
                    cw_tonbridge_validator::contract::execute,
                    cw_tonbridge_validator::contract::instantiate,
                    cw_tonbridge_validator::contract::query,
                ),
            ));
            bridge_id = app.upload(Box::new(
                cosmwasm_testing_util::ContractWrapper::new_with_empty(
                    crate::contract::execute,
                    crate::contract::instantiate,
                    crate::contract::query,
                ),
            ));
        }
        #[cfg(feature = "test-tube")]
        {
            validator_id = app.upload(include_bytes!("./testdata/cw-tonbridge-validator.wasm"));
            bridge_id = app.upload(include_bytes!("./testdata/cw-tonbridge-bridge.wasm"));
        }

        let validator_addr = app
            .instantiate(
                validator_id,
                admin.clone(),
                &tonbridge_validator::msg::InstantiateMsg { boc },
                &vec![],
                "validator",
            )
            .unwrap();

        let token_factory_addr = app.create_tokenfactory(admin.clone()).unwrap();

        let bridge_addr = app
            .instantiate(
                bridge_id,
                admin.clone(),
                &tonbridge_bridge::msg::InstantiateMsg {
                    validator_contract_addr: validator_addr.clone(),
                    bridge_adapter: "EQAE8anZidQFTKcsKS_98iDEXFkvuoa1YmVPxQC279zAoV7R".to_string(),
                    token_fee_receiver: token_fee_addr.clone(),
                    relayer_fee_receiver: relayer_fee_addr.clone(),
                    swap_router_contract: "router".to_string(),
                    token_factory_addr: Some(token_factory_addr.clone()),
                    osor_entrypoint_contract: Addr::unchecked("osor_entrypoint_contract"),
                },
                &vec![],
                "bridge",
            )
            .unwrap();

        let cw20_addr = app.create_token(admin.as_str(), "DUMMY", 10000000000000001u128);
        app.set_token_balances(
            admin.as_str(),
            &[("DUMMY", &[(bridge_addr.as_str(), 10000000000000001u128)])],
        )
        .unwrap();

        Self {
            app,
            owner: admin,
            validator_addr,
            bridge_addr,
            cw20_addr,
            token_factory_addr,
            token_fee_addr,
            relayer_fee_addr,
        }
    }
}
