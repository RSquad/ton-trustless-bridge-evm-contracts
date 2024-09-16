#[cfg(test)]
mod tests {

    use cosmwasm_schema::cw_serde;
    use cosmwasm_std::{
        from_json,
        testing::{mock_dependencies, mock_env, mock_info},
        Addr, HexBinary, StdError,
    };
    use cw_controllers::AdminError;
    use std::{fs::File, io::Read};
    use tonbridge_parser::{
        to_bytes32,
        types::{Bytes32, VdataHex, VerifiedBlockInfo},
        EMPTY_HASH,
    };
    use tonbridge_validator::msg::{
        ConfigResponse, ExecuteMsg, InstantiateMsg, QueryMsg, UserFriendlyValidator,
    };

    use crate::{
        contract::{execute, instantiate, query},
        error::ContractError,
        state::{OWNER, VALIDATOR, VERIFIED_BLOCKS},
        validator::Validator,
    };

    const BLOCK_BOCS_SMALL: &str = include_str!("testdata/bocs.hex");
    const BLOCK_BOCS_LARGE: &str = include_str!("testdata/bocs_large.hex");
    // const KEY_BLOCK_WITH_NEXT_VAL: &str = include_str!("testdata/keyblock_with_next_val.hex");
    const NEW_KEYBLOCK_BOCS: &str = include_str!("testdata/new_keyblock_bocs.hex");

    #[cw_serde]
    pub struct VdataSring {
        node_id: String,
        r: String,
        s: String,
    }

    #[test]
    fn test_instantiate_contract() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_SMALL).unwrap();

        instantiate(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &[]),
            InstantiateMsg { boc: Some(boc) },
        )
        .unwrap();

        let validators_bin = query(
            deps.as_ref(),
            mock_env(),
            QueryMsg::GetValidators {
                start_after: None,
                limit: Some(30),
                order: None,
            },
        )
        .unwrap();

        let validators: Vec<UserFriendlyValidator> = from_json(&validators_bin).unwrap();

        // choose two random indexes for testing
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "89462f768d318759a230f72ef92bdbcd02a09c791d40e6a01a53f42409e248a1"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "76627b87a5717e9caab3a8044a8f75fd8da98b512c057e56defea91529f9b573"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(validators.len(), 14usize);

        let config: ConfigResponse =
            from_json(&query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()).unwrap();
        assert_eq!(
            config,
            ConfigResponse {
                owner: Some("admin".to_string())
            }
        )
    }

    #[test]
    fn test_change_owner() {
        let mut deps = mock_dependencies();

        instantiate(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &[]),
            InstantiateMsg { boc: None },
        )
        .unwrap();

        // case1: failed, unauthorized
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::UpdateOwner {
                new_owner: Addr::unchecked("new_owner"),
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            ContractError::AdminError(AdminError::NotAdmin {}).to_string()
        );

        // case 2: success
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::UpdateOwner {
                new_owner: Addr::unchecked("new_owner"),
            },
        )
        .unwrap();

        let config: ConfigResponse =
            from_json(&query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()).unwrap();
        assert_eq!(
            config,
            ConfigResponse {
                owner: Some("new_owner".to_string())
            }
        )
    }
    #[test]
    fn test_prepare_new_key_block() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_SMALL).unwrap();

        VALIDATOR
            .save(deps.as_mut().storage, &Validator::default())
            .unwrap();

        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::PrepareNewKeyBlock { keyblock_boc: boc },
        )
        .unwrap();

        let validators_bin = query(
            deps.as_ref(),
            mock_env(),
            QueryMsg::GetCandidatesForValidators {
                start_after: None,
                limit: Some(30),
                order: None,
            },
        )
        .unwrap();

        let validators: Vec<UserFriendlyValidator> = from_json(&validators_bin).unwrap();

        // choose two random indexes for testing
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "89462f768d318759a230f72ef92bdbcd02a09c791d40e6a01a53f42409e248a1"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "76627b87a5717e9caab3a8044a8f75fd8da98b512c057e56defea91529f9b573"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(validators.len(), 14usize);
    }

    #[test]
    fn test_verify_key_block() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_SMALL).unwrap();
        let next_boc = HexBinary::from_hex(NEW_KEYBLOCK_BOCS).unwrap();

        VALIDATOR
            .save(deps.as_mut().storage, &Validator::default())
            .unwrap();

        // case 1: empty root hash
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::VerifyKeyBlock {
                root_hash: EMPTY_HASH.as_slice().try_into().unwrap(),
                file_hash: EMPTY_HASH.as_slice().try_into().unwrap(),
                vdata: vec![],
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            ContractError::Std(StdError::generic_err("wrong root_hash or file_hash")).to_string()
        );

        // prepare keyblock to populate new root hash
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::PrepareNewKeyBlock {
                keyblock_boc: boc.clone(),
            },
        )
        .unwrap();

        // case 2: even after preparing keyblock, if file hash is empty -> still return error
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::VerifyKeyBlock {
                root_hash: EMPTY_HASH.as_slice().try_into().unwrap(),
                file_hash: EMPTY_HASH.as_slice().try_into().unwrap(),
                vdata: vec![],
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            ContractError::Std(StdError::generic_err("wrong root_hash or file_hash")).to_string()
        );

        // -----case3: happy case-----

        // first init validator
        instantiate(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &[]),
            InstantiateMsg { boc: Some(boc) },
        )
        .unwrap();
        // prepare new key_block
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::PrepareNewKeyBlock {
                keyblock_boc: next_boc,
            },
        )
        .unwrap();

        let mut file = File::open("src/testing/testdata/new_keyblock_sig.json").unwrap();
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        let v_data_string: Vec<VdataSring> = serde_json_wasm::from_str(&contents).unwrap();
        let root_hash =
            HexBinary::from_hex("292edb12dadb1b56db5c44687bf1311dcac38089f8b895b11bf0c8fbd605989e")
                .unwrap();
        let file_hash =
            HexBinary::from_hex("dfd3c0f265e62f340cb8020a0a3b5d0503d71ca84d5f40b2372e858147c03ba1")
                .unwrap();

        //parse vdata string to vdata hex
        let v_data_hex: Vec<VdataHex> = v_data_string
            .iter()
            .map(|item| VdataHex {
                node_id: HexBinary::from_hex(&item.node_id).unwrap(),
                r: HexBinary::from_hex(&item.r).unwrap(),
                s: HexBinary::from_hex(&item.s).unwrap(),
            })
            .collect();

        // verify failed, not enough voting power
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::VerifyKeyBlock {
                root_hash: root_hash.clone(),
                file_hash: file_hash.clone(),
                vdata: v_data_hex[0..v_data_hex.len() / 3].to_vec(),
            },
        )
        .unwrap_err();
        assert!(err.to_string().contains("not enough votes"));
        // before verify success, query  failed
        let is_verified_block: bool = from_json(
            &query(
                deps.as_ref(),
                mock_env(),
                QueryMsg::IsVerifiedBlock {
                    root_hash: root_hash.clone(),
                },
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(is_verified_block, false);

        // verify success
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::VerifyKeyBlock {
                root_hash: root_hash.clone(),
                file_hash,
                vdata: v_data_hex.clone(),
            },
        )
        .unwrap();

        // pick random validator and ensure they are signed
        let is_signed_by_validator: bool = from_json(
            &query(
                deps.as_ref(),
                mock_env(),
                QueryMsg::IsSignedByValidator {
                    validator_node_id: v_data_hex[0].node_id.clone(),
                    root_hash: root_hash.clone(),
                },
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(is_signed_by_validator, true);

        let is_verified_block: bool = from_json(
            &query(
                deps.as_ref(),
                mock_env(),
                QueryMsg::IsVerifiedBlock { root_hash },
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(is_verified_block, true);
    }

    #[test]
    fn test_reset_validator_set() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_SMALL).unwrap();

        VALIDATOR
            .save(deps.as_mut().storage, &Validator::default())
            .unwrap();

        OWNER
            .set(deps.as_mut(), Some(Addr::unchecked("admin")))
            .unwrap();

        // suite 1: should fail since not an admin
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::ResetValidatorSet { boc: boc.clone() },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            ContractError::AdminError(AdminError::NotAdmin {}).to_string()
        );

        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::ResetValidatorSet { boc },
        )
        .unwrap();

        // query validator list, should return some validators
        let validators: Vec<UserFriendlyValidator> = from_json(
            &query(
                deps.as_ref(),
                mock_env(),
                QueryMsg::GetValidators {
                    start_after: None,
                    limit: Some(30),
                    order: None,
                },
            )
            .unwrap(),
        )
        .unwrap();

        // choose two random indexes for testing
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "89462f768d318759a230f72ef92bdbcd02a09c791d40e6a01a53f42409e248a1"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(
            validators
                .iter()
                .find(|val| val.pubkey.to_hex()
                    == "76627b87a5717e9caab3a8044a8f75fd8da98b512c057e56defea91529f9b573"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(validators.len(), 14usize);

        // after reset, the candidate list should be empty
        let candidates: Vec<UserFriendlyValidator> = from_json(
            &query(
                deps.as_ref(),
                mock_env(),
                QueryMsg::GetCandidatesForValidators {
                    start_after: None,
                    limit: Some(30),
                    order: None,
                },
            )
            .unwrap(),
        )
        .unwrap();

        assert_eq!(candidates.len(), 0);
    }

    #[test]
    fn test_set_verified_block() {
        let mut deps = mock_dependencies();

        instantiate(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &[]),
            InstantiateMsg { boc: None },
        )
        .unwrap();

        let root_hash =
            HexBinary::from_hex("f7a9db0094cdcb49e027f44e85ce4af164d8acaef2c0c2feaba1577a1d0091d1")
                .unwrap();
        // set failed, no admin
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("relayer", &vec![]),
            ExecuteMsg::SetVerifiedBlock {
                root_hash: root_hash.clone(),
                seq_no: 100,
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            "Generic error: Caller is not admin".to_string()
        );

        // set success
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::SetVerifiedBlock {
                root_hash: root_hash.clone(),
                seq_no: 100,
            },
        )
        .unwrap();
        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            seq_no: 100,
            ..Default::default()
        };
        assert_eq!(
            VERIFIED_BLOCKS
                .load(deps.as_mut().storage, &to_bytes32(&root_hash).unwrap())
                .unwrap(),
            verified_block_info
        );

        // set failed, block already verified
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::SetVerifiedBlock {
                root_hash: root_hash.clone(),
                seq_no: 100,
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            "Generic error: block already verified".to_string()
        );
    }
    #[test]
    fn test_verify_master_chain_block() {
        // https://scan.orai.io/txs/87D34F1686292B1B34EEDD36EA0D6345035C5EC2D5BA2219AA5292ECA03351DB
        let mut deps = mock_dependencies();
        VALIDATOR
            .save(deps.as_mut().storage, &Validator::default())
            .unwrap();

        OWNER
            .set(deps.as_mut(), Some(Addr::unchecked("admin")))
            .unwrap();

        let boc = HexBinary::from_hex(BLOCK_BOCS_LARGE).unwrap();

        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::ResetValidatorSet { boc },
        )
        .unwrap();

        let mut file = File::open("src/testing/testdata/masterchain_block_sig.json").unwrap();
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        let v_data_string: Vec<VdataSring> = serde_json_wasm::from_str(&contents).unwrap();

        //parse vdata string to vdata hex
        let v_data_hex: Vec<VdataHex> = v_data_string
            .iter()
            .map(|item| VdataHex {
                node_id: HexBinary::from_hex(&item.node_id).unwrap(),
                r: HexBinary::from_hex(&item.r).unwrap(),
                s: HexBinary::from_hex(&item.s).unwrap(),
            })
            .collect();

        let block_header = HexBinary::from_hex("b5ee9c72010209010001fa00094603f7a9db0094cdcb49e027f44e85ce4af164d8acaef2c0c2feaba1577a1d0091d1001601241011ef55aaffffff110203040501a09bc7a987000000000401024d18e30000000100ffffffff0000000000000000667b8b4c00002b0e663fe54000002b0e663fe5444ea6e53c0008d5a6024d18df024d092bc400000007000000000000002e0628480101ddd42acf06126e1d8942bdb8080fdd97a7dae4d6df7880ee9625d69da1502a7d00032a8a04c99e099aeb852551a3d8a6efdb41e035cac018611ac5352a6c30393482aa62a5501b3f48c250cea26fd284425c3810466a214872a4b398c9957ce9787f58e264016f016f0708284801016429d9dc8a7cc6e5d82344adf804bfa345c3121b7fb025e29635dbc8360187030007009800002b0e6630a304024d18e2b34aa8d3e01de0b4e6a0f9c052636a095d5dc32d9d25e5a22875bbe4c0ab5016d91bcb8d91d4f573b3acad3fcce8fe3e3f74cfd27099f0776e73aa7467ae0e9b688c0103c99e099aeb852551a3d8a6efdb41e035cac018611ac5352a6c30393482aa62a560d14b21173ec6f4f4448b704abfbae237f3d0f1b13daad08cc039927de7bb12016f0014688c0103501b3f48c250cea26fd284425c3810466a214872a4b398c9957ce9787f58e2648a80218fbb55d4759795d9df7ab9a3dd5dbcc403a2dff4ae5f53ed1d382a635a016f0014").unwrap();
        let file_hash =
            HexBinary::from_hex("36f5e7b74e779744135fa533b18da8a7649786eaf43be6b770d211e28b6493e8")
                .unwrap();

        // case 1: verify false, not enough vote
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::VerifyMasterchainBlockByValidatorSignatures {
                block_header_proof: block_header.clone(),
                file_hash: file_hash.clone(),
                vdata: v_data_hex[0..v_data_hex.len() / 3].to_vec(),
            },
        )
        .unwrap_err();
        assert!(err.to_string().contains("not enough votes to verify block"));

        // case 2: verify success
        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::VerifyMasterchainBlockByValidatorSignatures {
                block_header_proof: block_header,
                file_hash,
                vdata: v_data_hex,
            },
        )
        .unwrap();

        let root_hash: Bytes32 = [
            247, 169, 219, 0, 148, 205, 203, 73, 224, 39, 244, 78, 133, 206, 74, 241, 100, 216,
            172, 174, 242, 192, 194, 254, 171, 161, 87, 122, 29, 0, 145, 209,
        ];

        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            ..Default::default()
        };

        assert_eq!(
            VERIFIED_BLOCKS
                .load(deps.as_mut().storage, &root_hash)
                .unwrap(),
            verified_block_info
        );
    }

    #[test]
    fn test_verify_shard_block() {
        // seqno: 43884169,
        // shard: "2000000000000000",
        // workchain: 0,

        let mut deps = mock_dependencies();
        VALIDATOR
            .save(deps.as_mut().storage, &Validator::default())
            .unwrap();

        OWNER
            .set(deps.as_mut(), Some(Addr::unchecked("admin")))
            .unwrap();

        let shard_proof_links =  vec![
        HexBinary::from_hex("b5ee9c720102140100027a000946039b12663e48d24513dbf303d547e6e6e10b2d637cd11600e78420bf0aed1aad2d001601241011ef55aaffffff110203040528480101a61819c2bcd15aa09958881e6cca7f84ca04aa7d118b237c96519a09446d7b8f00012848010138bf381cf9b9df9f314f1b4dc74127d398814111003bf484502ff419c414a40a0003284801015728228d3059dc5da4c5c0f6a54f8cb0d5a3d15a289d3ea9f4a8810f366be367001524894a33f6fd21a7dee602fb675d6f1144f565e364ae3db6bada5187e98275f39be72b9577bb247071c3e769233d398adc88fdedb2dba7208da38330c4cc0d0a6af3bac2a8a7c00607080928480101b43ef3d7c8e55e1f1510c1855e91323fb3521e63f851300cb3f214261be602eb0004000102284801010f8995cdfdd409bb3d03426397ec1ffc59a4931674ab7b66928dbcfe80b030b600062319cca56a03355600fa49502f90040a0b0c2103d0400d28480101f9ab2fd8292b1eda69d5a9ff670a50bc453989f2c3f746934941e7af5c26ec6a0003210150132201c00e0f2201c010112848010195f2c2c66de2c0ab069b146a5d965907a1cb41e627fb83e6517914dd3ec61e5e000301db5014ecf450123906980001555f0c75a0000001555f0c75a1faea90ae26eaf16e1f45832019c98189ae6b94b62bbf1be8f870bc0e6f37dcb14baf84c282d346327a7fc7b6a54deb707ced7b13a97c939954871045b78e7a51f0000045f8d900000000000000001239068b33061a3a1228480101f4f492b7fed135c3515e810152abc0b0473d4a98f405e79c210b2e21b54ced4100010013468c16d6020ee6b2802028480101c8e6b152e6d84bd2e285d365b1e282838d323e0d6ec730175937d6e4a5de0a2e0003").unwrap(),
        HexBinary::from_hex("b5ee9c7201020801000196000946035d5215c4dd5e2dc3e8b0640339303135cd7296c577e37d1f0e1781cde6fb9629002401241011ef55aaffffff110203040502a09bc7a987000000008001029d9e8a00000001020000000000000000000000006660c34700002aabe18eb40000002aabe18eb43f6f2862d90008bf1b024720d1024711a2c400000007000000000000002e060728480101faf730fbb08aaab8721ee97b13cf7485ddae96d85c8b452606235b7b217e13110002284801010ecfb0afaa56b64afbfcc02bb61b265b54ca24160fffc027a284a08fbf65b9930023284801012505df179b67dc3f8aeeaaa30e6c84776a1970a2bc66005740391d237bb17951001c009800002aabe17f71c4024720d121f89a9e980239acda21facfd549b6fe51a3017be24968197ead7010b301e4a7ef87287d5a3664e7959973a88d6c1913d7dba36ec68e2992b43acbc2f10b91ea009800002aabe17f71fa029d9e890299328dbd84b0ece362aec8cb04f89f7f21b1908dd55542ae9983914d81b7d1e2c3fa09a489788cb156f769cd52eec583817e37752a86e53f042e2ee8782158").unwrap()];
        let mc_block_root_hash =
            HexBinary::from_hex("f7a9db0094cdcb49e027f44e85ce4af164d8acaef2c0c2feaba1577a1d0091d1")
                .unwrap();
        let root_hash: Bytes32 = mc_block_root_hash.as_slice().try_into().unwrap();

        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            ..Default::default()
        };
        // case 1, mc_block_root_hash not verify
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::VerifyShardBlocks {
                shard_proof_links: shard_proof_links.clone(),
                mc_block_root_hash: mc_block_root_hash.clone(),
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            "Generic error: masterchain block root hash is not verified".to_string()
        );

        // case 2: merkle proof not verified
        VERIFIED_BLOCKS
            .save(deps.as_mut().storage, &root_hash, &verified_block_info)
            .unwrap();
        let err = execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::VerifyShardBlocks {
                shard_proof_links: shard_proof_links.clone(),
                mc_block_root_hash: mc_block_root_hash.clone(),
            },
        )
        .unwrap_err();
        assert_eq!(
            err.to_string(),
            "Generic error: merkle proof not verified".to_string()
        );

        // case 3: verify success
        let mc_block_root_hash =
            HexBinary::from_hex("9b12663e48d24513dbf303d547e6e6e10b2d637cd11600e78420bf0aed1aad2d")
                .unwrap();
        let root_hash: Bytes32 = mc_block_root_hash.as_slice().try_into().unwrap();
        VERIFIED_BLOCKS
            .save(deps.as_mut().storage, &root_hash, &verified_block_info)
            .unwrap();

        execute(
            deps.as_mut(),
            mock_env(),
            mock_info("admin", &vec![]),
            ExecuteMsg::VerifyShardBlocks {
                shard_proof_links,
                mc_block_root_hash,
            },
        )
        .unwrap();

        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            seq_no: 43884169,
            start_lt: 0,
            end_lt: 46917711000058,
            ..Default::default()
        };
        assert_eq!(
            VERIFIED_BLOCKS
                .load(
                    deps.as_mut().storage,
                    &to_bytes32(
                        &HexBinary::from_hex(
                            "0299328dbd84b0ece362aec8cb04f89f7f21b1908dd55542ae9983914d81b7d1"
                        )
                        .unwrap()
                    )
                    .unwrap()
                )
                .unwrap(),
            verified_block_info
        );
    }
}
