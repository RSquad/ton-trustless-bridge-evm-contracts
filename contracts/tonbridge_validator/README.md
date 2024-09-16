# Reference:

https://docs.ton.org/trustless-interaction-with-ton_v1.1_23-05-15.pdf

## Implementation notes:

in validator.rs, both 4.1 and 4.2 in the above paper are implemented.

### 4.2:

4.2 is used when a block is new, and needs to be validated without having any proof from the newer blocks (cuz it is the newest)

The first initial validator set along with the initital block are cached and validated when initiating the contract by providing a valid block data (boc is the block data in the boc form).

Then, afterwards, when there's an updated validator set, we need to:

1. Call `parse_candidates_root_block` to parse the block and collect the list of validator candidates.
2. Call `verify_validators` to verify the validator candidates' signatures.

If succeeded for both steps -> the new block is verified

Admin can call `reset_validator_set` to manually update a new validator set

### 4.1:

4.1 is used when there's an **older** block (older than blocks we have validated using 4.2) from the masterchain that we want to validate.

1. 