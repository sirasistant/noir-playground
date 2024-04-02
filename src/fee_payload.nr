use crate::private_context::PrivateContext;
use dep::aztec::protocol_types::{traits::{Hash, Serialize}};
use crate::entrypoint::FunctionCall;
use crate::hash::poseidon_hash;

// 2 * 4 (function call) + 1
global FEE_PAYLOAD_SIZE: Field = 9;

global MAX_FEE_FUNCTION_CALLS = 1;

// docs:start:fee-payload-struct
struct FeePayload {
  function_calls: [FunctionCall; MAX_FEE_FUNCTION_CALLS],
  nonce: Field,
}
// docs:end:fee-payload-struct

impl Serialize<FEE_PAYLOAD_SIZE> for FeePayload {
  // Serializes the entrypoint struct
  fn serialize(self) -> [Field; FEE_PAYLOAD_SIZE] {
    let mut fields: BoundedVec<Field, FEE_PAYLOAD_SIZE> = BoundedVec::new();
    for i in 0..MAX_FEE_FUNCTION_CALLS {
      fields.extend_from_array(self.function_calls[i].serialize());
    }
    fields.push(self.nonce);
    fields.storage
  }
}

impl Hash for FeePayload {
  fn hash(self) -> Field {
    poseidon_hash(
      self.serialize()
    )
  }
}

impl FeePayload {
    fn execute_calls(self, context: &mut PrivateContext) {
        for call in self.function_calls {
            if !call.target_address.is_zero() {
                if call.is_public {
                    context.call_public_function_with_packed_args(
                        call.target_address,
                        call.function_selector,
                        call.args_hash,
                        false,
                        false
                    );
                } else {
                    let _result = context.call_private_function_with_packed_args(
                        call.target_address,
                        call.function_selector,
                        call.args_hash,
                        false,
                        false
                    );
                }
            }
        }
    }
}
