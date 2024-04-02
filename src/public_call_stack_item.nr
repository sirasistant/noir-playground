use dep::aztec::protocol_types::abis::{function_data::FunctionData};
use dep::aztec::protocol_types::address::AztecAddress;
use dep::aztec::protocol_types::traits::Hash;
use dep::aztec::protocol_types::constants::GENERATOR_INDEX__CALL_STACK_ITEM;
use crate::hash::{poseidon_hash, pedersen_hash};
use crate::public_circuit_public_inputs::PublicCircuitPublicInputs;

struct PublicCallStackItem {
    contract_address: AztecAddress,
    public_inputs: PublicCircuitPublicInputs,
    function_data: FunctionData,
    // True if this call stack item represents a request to execute a function rather than a
    // fulfilled execution. Used when enqueuing calls from private to public functions.
    is_execution_request: bool,
}

impl Hash for PublicCallStackItem {
    fn hash(self) -> Field {
        let item = if self.is_execution_request {
            self.as_execution_request()
        } else {
            self
        };

        poseidon_hash([
            item.contract_address.to_field(),
            item.function_data.hash(),
            item.public_inputs.hash(),
        ])
        // pedersen_hash(
        //     [
        //     item.contract_address.to_field(),
        //     item.function_data.hash(),
        //     item.public_inputs.hash(),
        // ], GENERATOR_INDEX__CALL_STACK_ITEM
        // )
    }
}

impl PublicCallStackItem {
    fn as_execution_request(self) -> Self {
        let public_inputs = self.public_inputs;
        let mut request_public_inputs: PublicCircuitPublicInputs = dep::std::unsafe::zeroed();
        request_public_inputs.call_context = public_inputs.call_context;
        request_public_inputs.args_hash = public_inputs.args_hash;

        let call_stack_item = PublicCallStackItem {
            contract_address: self.contract_address,
            function_data: self.function_data,
            is_execution_request: true,
            public_inputs: request_public_inputs
        };
        call_stack_item
    }
}
