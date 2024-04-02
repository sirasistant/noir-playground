mod private_context;
mod private_call_stack_item;
mod public_call_stack_item;
mod hash;
mod app_payload;
mod entrypoint;
mod fee_payload;
mod public_circuit_public_inputs;

use dep::aztec::protocol_types::{abis::function_selector::FunctionSelector, address::AztecAddress, traits::{Hash, Serialize}};
use hash::poseidon_hash;
use private_context::{PrivateContext, PublicInputs};
use app_payload::AppPayload;
use fee_payload::FeePayload;

fn main(fee_payload: FeePayload, app_payload: AppPayload) -> pub PublicInputs {
    let mut context = PrivateContext::new();

    fee_payload.execute_calls(&mut context);
    app_payload.execute_calls(&mut context);

    context.finish()
}
