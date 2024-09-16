#[cfg(test)]
mod tests {

    use cosmwasm_std::{testing::mock_dependencies, HexBinary};
    use tonbridge_parser::types::VerifiedBlockInfo;

    use crate::validator::Validator;

    const BLOCK_BOCS_SMALL: &str = include_str!("./testdata/bocs.hex");
    const BLOCK_BOCS_LARGE: &str = include_str!("./testdata/bocs_large.hex");
    const KEY_BLOCK_WITH_NEXT_VAL: &str = include_str!("./testdata/keyblock_with_next_val.hex");

    #[test]
    fn test_default_verified_blocks_info() {
        let default_block_info = VerifiedBlockInfo::default();
        assert_eq!(default_block_info.verified, false);
    }

    #[test]
    fn test_candidate_root_block() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_SMALL).unwrap().to_vec();

        let mut validator = Validator::default();
        validator
            .parse_candidates_root_block(deps.as_mut().storage, &boc)
            .unwrap();
        let root_hash = HexBinary::from(validator.signature_validator.root_hash);
        println!("root hash: {:?}", root_hash);

        let validators: Vec<_> = validator
            .get_candidates_for_validators(deps.as_ref().storage)
            .unwrap()
            .into_iter()
            .filter(|c| c.c_type != 0)
            .collect();

        // choose two random indexes for testing
        assert_eq!(
            validators
                .iter()
                .find(|val| HexBinary::from(val.pubkey).to_hex()
                    == "89462f768d318759a230f72ef92bdbcd02a09c791d40e6a01a53f42409e248a1"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(
            validators
                .iter()
                .find(|val| HexBinary::from(val.pubkey).to_hex()
                    == "76627b87a5717e9caab3a8044a8f75fd8da98b512c057e56defea91529f9b573"
                        .to_string())
                .is_some(),
            true,
        );
        assert_eq!(validators.len(), 14usize);
    }

    #[test]
    fn test_candidate_root_block_large() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(BLOCK_BOCS_LARGE).unwrap().to_vec();

        let mut validator = Validator::default();
        validator
            .parse_candidates_root_block(deps.as_mut().storage, &boc)
            .unwrap();

        let validators: Vec<_> = validator
            .get_candidates_for_validators(deps.as_ref().storage)
            .unwrap()
            .into_iter()
            .filter(|c| c.c_type != 0)
            .collect();

        validator.init_validators(deps.as_mut().storage).unwrap();

        // choose two random indexes for testing
        assert_eq!(validators.len(), 732usize);
    }

    #[test]
    fn test_candidate_root_block_large_with_next_validator() {
        let mut deps = mock_dependencies();
        let boc = HexBinary::from_hex(KEY_BLOCK_WITH_NEXT_VAL)
            .unwrap()
            .to_vec();

        let mut validator = Validator::default();
        validator
            .parse_candidates_root_block(deps.as_mut().storage, &boc)
            .unwrap();

        validator.init_validators(deps.as_mut().storage).unwrap();
        assert_eq!(validator.next_validator_updated(), true);

        let list_vals = validator.get_validators(deps.as_ref().storage).unwrap();
        assert_eq!(list_vals.len(), 1079);
    }
}
