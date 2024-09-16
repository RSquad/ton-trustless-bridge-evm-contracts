#[cfg(test)]
mod tests {
    use cosmwasm_std::{testing::mock_dependencies, Api, HexBinary, StdError};
    use tonbridge_parser::{
        to_bytes32,
        types::{Bytes32, KeyBlockValidators, ValidatorDescription, Vdata},
        EMPTY_HASH,
    };
    use tonlib::{
        cell::TonCellError,
        responses::{
            ConfigParam, ConfigParams, ConfigParamsValidatorSet, ValidatorDescr, Validators,
        },
    };

    use crate::{
        error::ContractError,
        signature_validator::{ISignatureValidator, SignatureValidator},
        state::{validator_set, SIGNATURE_CANDIDATE_VALIDATOR, SIGNED_BLOCKS},
    };

    const ED25519_MESSAGE_HEX: &str = "af82";
    const ED25519_SIGNATURE_HEX: &str = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a";
    const ED25519_PUBLIC_KEY_HEX: &str =
        "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025";

    fn convert_byte32(str: &str) -> Bytes32 {
        HexBinary::from_hex(str)
            .unwrap()
            .as_slice()
            .try_into()
            .unwrap()
    }

    #[test]
    fn test_signature_verify() {
        let deps = mock_dependencies();
        let message = HexBinary::from_hex(ED25519_MESSAGE_HEX).unwrap();
        let signature = HexBinary::from_hex(ED25519_SIGNATURE_HEX).unwrap();
        let public_key = HexBinary::from_hex(ED25519_PUBLIC_KEY_HEX).unwrap();
        let verfied = deps
            .api
            .ed25519_verify(&message, &signature, &public_key)
            .unwrap();

        println!("verified {}", verfied);
    }

    #[test]
    fn test_parse_validators() {
        let mut deps = mock_dependencies();
        let mut validators: KeyBlockValidators = KeyBlockValidators::default();
        validators.current = vec![
            ValidatorDescription {
                c_type: 1,
                weight: 3,
                adnl_addr: EMPTY_HASH,
                pubkey: to_bytes32(
                    &HexBinary::from_hex(
                        "3827e3ec4a5b93141efb9ced816d13248bf1fa1506f03b5a69e109657682e12c",
                    )
                    .unwrap(),
                )
                .unwrap(),
                node_id: to_bytes32(
                    &HexBinary::from_hex(
                        "3827e3ec4a5b93141efb9ced816d13248bf1fa1506f03b5a69e109657682e12c",
                    )
                    .unwrap(),
                )
                .unwrap(),
            },
            ValidatorDescription {
                c_type: 1,
                weight: 1,
                adnl_addr: EMPTY_HASH,
                pubkey: to_bytes32(
                    &HexBinary::from_hex(
                        "8e803f1f6dfed804d600be94330482a827921f18a8074e5a36bc9e977b9b2f5d",
                    )
                    .unwrap(),
                )
                .unwrap(),
                node_id: to_bytes32(
                    &HexBinary::from_hex(
                        "8e803f1f6dfed804d600be94330482a827921f18a8074e5a36bc9e977b9b2f5d",
                    )
                    .unwrap(),
                )
                .unwrap(),
            },
        ];
        let mut sig_val = SignatureValidator::default();

        SIGNATURE_CANDIDATE_VALIDATOR
            .save(
                deps.as_mut().storage,
                0,
                &ValidatorDescription {
                    c_type: 1,
                    weight: 2,
                    adnl_addr: EMPTY_HASH,
                    pubkey: to_bytes32(
                        &HexBinary::from_hex(
                            "3827e3ec4a5b93141efb9ced816d13248bf1fa1506f03b5a69e109657682e12c",
                        )
                        .unwrap(),
                    )
                    .unwrap(),
                    node_id: to_bytes32(
                        &HexBinary::from_hex(
                            "3827e3ec4a5b93141efb9ced816d13248bf1fa1506f03b5a69e109657682e12c",
                        )
                        .unwrap(),
                    )
                    .unwrap(),
                },
            )
            .unwrap();

        sig_val
            .parse_validators(deps.as_mut().storage, &mut validators)
            .unwrap();

        assert_eq!(sig_val.candidates_total_weight, 4u64);
        assert_eq!(sig_val.has_candidate_next, false);
        assert_eq!(sig_val.has_next, false);
        assert_eq!(sig_val.root_hash, EMPTY_HASH);
        assert_eq!(sig_val.sum_largest_candidates_total_weights, 4);
        assert_eq!(sig_val.sum_largest_total_weights, 0);
    }

    #[test]
    fn test_is_signed_by_validator() {
        let mut deps = mock_dependencies();
        let sig_val = SignatureValidator::default();
        let is_signed =
            sig_val.is_signed_by_validator(deps.as_mut().storage, EMPTY_HASH, EMPTY_HASH);

        assert_eq!(is_signed, false);

        SIGNED_BLOCKS
            .save(
                deps.as_mut().storage,
                &[EMPTY_HASH, EMPTY_HASH].concat(),
                &true,
            )
            .unwrap();

        let is_signed =
            sig_val.is_signed_by_validator(deps.as_mut().storage, EMPTY_HASH, EMPTY_HASH);
        assert_eq!(is_signed, true);
    }

    #[test]
    fn test_init_validators() {
        let mut deps = mock_dependencies();
        let mut sig_val = SignatureValidator::default();
        let root_hash =
            HexBinary::from_hex("5d5215c4dd5e2dc3e8b0640339303135cd7296c577e37d1f0e1781cde6fb9629")
                .unwrap();
        let total_weight = 2;
        let first_candidate_pubkey =
            convert_byte32("3827e3ec4a5b93141efb9ced816d13248bf1fa1506f03b5a69e109657682e12c");

        SIGNATURE_CANDIDATE_VALIDATOR
            .save(
                deps.as_mut().storage,
                0,
                &ValidatorDescription {
                    c_type: 1,
                    weight: total_weight,
                    adnl_addr: EMPTY_HASH,
                    pubkey: first_candidate_pubkey,
                    node_id: first_candidate_pubkey,
                },
            )
            .unwrap();

        sig_val.root_hash = to_bytes32(&root_hash).unwrap();
        sig_val.candidates_total_weight = total_weight;
        sig_val.sum_largest_candidates_total_weights = total_weight;
        let rh = sig_val.init_validators(deps.as_mut().storage).unwrap();

        assert_eq!(rh, to_bytes32(&root_hash).unwrap());
        assert_eq!(sig_val.root_hash, EMPTY_HASH);
        assert_eq!(sig_val.candidates_total_weight, 0);
        assert_eq!(sig_val.has_candidate_next, false);
        assert_eq!(sig_val.has_next, false);
        assert_eq!(sig_val.total_weight, total_weight);
        assert_eq!(sig_val.sum_largest_total_weights, total_weight);
        assert_eq!(sig_val.sum_largest_candidates_total_weights, 0);

        assert_eq!(
            validator_set()
                .load(deps.as_mut().storage, &first_candidate_pubkey)
                .unwrap()
                .pubkey,
            first_candidate_pubkey
        );
    }

    #[test]
    fn test_verify_signature() {
        // TODO: use the signatures that we have pubkeys that match.
        let signatures = [
            Vdata {
                node_id: convert_byte32(
                    "80de0302ef8970b077e702b227a1bae646530b6b3630d1dd0d81541971757ff3",
                ),
                r: convert_byte32(
                    "5efa07dac65c347fa70fde65312a0a0a8a1f76aae9adbec6058a80e7f5202e5e",
                ),
                s: convert_byte32(
                    "3946227c0d480cb4794bc7d6a5c4d5d0c2d80b08bb937b063b6eecb7ec9e7a08",
                ),
            },
            Vdata {
                node_id: convert_byte32(
                    "4ff320aca951fac7e49be0c5d375e21a88be531193dfab791a9fed2ebeea4eb2",
                ),
                r: convert_byte32(
                    "e623088e43a0151925583e2a3b861e9270cab4cc223a2e01b856f123e6d0dbc9",
                ),
                s: convert_byte32(
                    "341bacfc1bfbc28aadaf914cf93c9bf43f2e4f7bccdebbf3e62c98f82d697004",
                ),
            },
        ];

        let root_hash =
            convert_byte32("292edb12dadb1b56db5c44687bf1311dcac38089f8b895b11bf0c8fbd605989e");
        let file_hash =
            convert_byte32("dfd3c0f265e62f340cb8020a0a3b5d0503d71ca84d5f40b2372e858147c03ba1");

        let mut deps = mock_dependencies();
        let validator = SignatureValidator::default();

        // case 1: current weight should be 0 since there's no validator set stored yet matching these signatures
        let current_weight = validator
            .verify_validators(
                &mut deps.storage,
                &deps.api,
                root_hash,
                file_hash,
                &signatures,
            )
            .unwrap();
        assert_eq!(current_weight, 0);

        // case 2: when a block is re-checked, we also verify using validators and increment the weight
        SIGNED_BLOCKS
            .save(
                deps.as_mut().storage,
                &[signatures[0].node_id, root_hash].concat(),
                &true,
            )
            .unwrap();

        let mut first_val = ValidatorDescription::default();
        first_val.weight = 2;
        first_val.node_id = signatures[0].node_id;
        validator_set()
            .save(deps.as_mut().storage, &signatures[0].node_id, &first_val)
            .unwrap();

        let current_weight = validator
            .verify_validators(
                &mut deps.storage,
                &deps.api,
                root_hash,
                file_hash,
                &signatures,
            )
            .unwrap();
        assert_eq!(current_weight, 2);
    }

    #[test]
    fn test_set_validator_set() {
        let mut deps = mock_dependencies();
        let mut sig_val = SignatureValidator::default();
        let deps_mut = deps.as_mut();

        // case 1: empty valset
        let err = sig_val
            .set_validator_set(deps_mut.storage, deps_mut.api)
            .unwrap_err();
        assert_eq!(
            err.to_string(),
            StdError::generic_err("current validator_set is empty").to_string()
        );

        // case 2: empty weight
        let mut first_val = ValidatorDescription::default();
        first_val.weight = 0;
        first_val.node_id =
            convert_byte32("80de0302ef8970b077e702b227a1bae646530b6b3630d1dd0d81541971757ff3");
        validator_set()
            .save(deps_mut.storage, &first_val.node_id, &first_val)
            .unwrap();

        let err = sig_val
            .set_validator_set(deps_mut.storage, deps_mut.api)
            .unwrap_err();
        assert_eq!(
            err.to_string(),
            StdError::generic_err("current validator_set has zero weight").to_string()
        );

        // case 3, not enough votes
        first_val.weight = 3;
        validator_set()
            .save(deps_mut.storage, &first_val.node_id, &first_val)
            .unwrap();
        sig_val.sum_largest_total_weights = 3;
        let err = sig_val
            .set_validator_set(deps_mut.storage, deps_mut.api)
            .unwrap_err();
        assert_eq!(
            err.to_string(),
            StdError::generic_err(&format!(
                "not enough votes. Wanted {:?}; has {:?}",
                sig_val.sum_largest_total_weights * 2,
                0,
            ))
            .to_string()
        );

        // case 4: happy case
        let root_hash =
            convert_byte32("292edb12dadb1b56db5c44687bf1311dcac38089f8b895b11bf0c8fbd605989e");
        let total_weight = 4;
        SIGNED_BLOCKS
            .save(
                deps_mut.storage,
                &[first_val.node_id, root_hash].concat(),
                &true,
            )
            .unwrap();

        SIGNATURE_CANDIDATE_VALIDATOR
            .save(deps_mut.storage, 0, &first_val)
            .unwrap();

        sig_val.root_hash = root_hash;
        sig_val.candidates_total_weight = total_weight;
        sig_val.sum_largest_candidates_total_weights = total_weight;
        let rh = sig_val
            .set_validator_set(deps_mut.storage, deps_mut.api)
            .unwrap();
        assert_eq!(rh, root_hash);
        assert_eq!(sig_val.root_hash, EMPTY_HASH);
        assert_eq!(sig_val.total_weight, total_weight);
        assert_eq!(sig_val.sum_largest_total_weights, total_weight);
        assert_eq!(sig_val.candidates_total_weight, 0);
        assert_eq!(sig_val.sum_largest_candidates_total_weights, 0);

        assert_eq!(
            validator_set()
                .load(deps.as_mut().storage, &first_val.node_id)
                .unwrap()
                .pubkey,
            first_val.pubkey
        );
    }

    #[test]
    fn test_load_validator_from_config_param() {
        let mut config_params = ConfigParams::default();

        // case 1: config param not found
        let err =
            SignatureValidator::load_validator_from_config_param(&config_params, 36).unwrap_err();

        assert_eq!(
            err.to_string(),
            ContractError::TonCellError(TonCellError::cell_parser_error("config param not found"))
                .to_string()
        );

        // case 2: has param number 36 but no config param
        config_params.config.insert("24".to_string(), None);
        let err =
            SignatureValidator::load_validator_from_config_param(&config_params, 36).unwrap_err();
        assert_eq!(
            err.to_string(),
            ContractError::TonCellError(TonCellError::cell_parser_error(
                "Validation infos not found"
            ))
            .to_string()
        );

        // case 3: happy case
        let mut validators = Validators::default();
        let mut val_descr = ValidatorDescr::default();
        val_descr.public_key =
            convert_byte32("292edb12dadb1b56db5c44687bf1311dcac38089f8b895b11bf0c8fbd605989e")
                .to_vec();
        val_descr.adnl_addr = val_descr.public_key.clone();
        validators.list.insert("0".to_string(), val_descr.clone());
        config_params.config.insert(
            "24".to_string(),
            Some(ConfigParam::ConfigParams36(ConfigParamsValidatorSet {
                number: 36,
                validators,
            })),
        );

        let validator_set =
            SignatureValidator::load_validator_from_config_param(&config_params, 36).unwrap();

        assert_eq!(validator_set.len(), 1);
        assert_eq!(validator_set[0].pubkey.to_vec(), val_descr.public_key);
    }
}
