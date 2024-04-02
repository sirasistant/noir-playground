use dep::aztec::protocol_types::{abis::function_selector::FunctionSelector, address::AztecAddress, traits::{Hash, Serialize}};
use crate::hash::poseidon_hash;
use crate::private_context::PrivateContext;
use crate::entrypoint::FunctionCall;

// FUNCTION_CALL_SIZE * ACCOUNT_MAX_CALLS + 1
global APP_PAYLOAD_SIZE: u64 = 17;

global ACCOUNT_MAX_CALLS: u64 = 1;

// Note: If you change the following struct you have to update default_entrypoint.ts
// docs:start:app-payload-struct
struct AppPayload {
  function_calls: [FunctionCall; ACCOUNT_MAX_CALLS],
  nonce: Field,
}
// docs:end:app-payload-struct

impl Serialize<APP_PAYLOAD_SIZE> for AppPayload {
  // Serializes the entrypoint struct
  fn serialize(self) -> [Field; APP_PAYLOAD_SIZE] {
    let mut fields: BoundedVec<Field, APP_PAYLOAD_SIZE> = BoundedVec::new();
    for call in self.function_calls {
      fields.extend_from_array(call.serialize());
    }
    fields.push(self.nonce);
    fields.storage
  }
}

impl Hash for AppPayload {
  fn hash(self) -> Field {
    poseidon_hash(
      self.serialize()
    )
  }
}

impl AppPayload {
    // Executes all private and public calls
    // docs:start:entrypoint-execute-calls
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
    // docs:end:entrypoint-execute-calls
}
