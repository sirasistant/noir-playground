use dep::aztec::protocol_types::{abis::function_selector::FunctionSelector, address::AztecAddress, traits::{Hash, Serialize}};

// 1 (ARGS_HASH) + 1 (FUNCTION_SELECTOR) + 1 (TARGET_ADDRESS) + 1 (IS_PUBLIC)
global FUNCTION_CALL_SIZE: Field = 4;

struct FunctionCall {
  args_hash: Field,
  function_selector: FunctionSelector,
  target_address: AztecAddress,
  is_public: bool,
}

impl Serialize<FUNCTION_CALL_SIZE> for FunctionCall {
  fn serialize(self) -> [Field; FUNCTION_CALL_SIZE] {
    [self.args_hash, self.function_selector.to_field(), self.target_address.to_field(), self.is_public as Field]
  }
}
