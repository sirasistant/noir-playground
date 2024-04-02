use dep::aztec::prelude::{AztecAddress, FunctionSelector};
use dep::aztec::protocol_types::constants::{
    PRIVATE_CALL_STACK_ITEM_LENGTH, ENQUEUE_PUBLIC_FUNCTION_CALL_RETURN_LENGTH,
    MAX_NEW_NOTE_HASHES_PER_CALL, MAX_NEW_L2_TO_L1_MSGS_PER_CALL, MAX_NEW_NULLIFIERS_PER_CALL,
    MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL, MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL,
    MAX_PUBLIC_DATA_READS_PER_CALL, MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL,
    MAX_NOTE_HASH_READ_REQUESTS_PER_CALL, MAX_NULLIFIER_READ_REQUESTS_PER_CALL,
    MAX_NULLIFIER_NON_EXISTENT_READ_REQUESTS_PER_CALL, MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL,
    RETURN_VALUES_LENGTH
};
use crate::private_call_stack_item::PrivateCallStackItem;
use crate::public_call_stack_item::PublicCallStackItem;
use dep::aztec::protocol_types::{
    abis::{
    call_context::CallContext, function_data::FunctionData, read_request::ReadRequest,
    side_effect::{SideEffect, SideEffectLinkedToNoteHash}
},
    contrakt::{storage_read::StorageRead, storage_update_request::StorageUpdateRequest},
    grumpkin_private_key::GrumpkinPrivateKey, header::Header,
    messaging::l2_to_l1_message::L2ToL1Message, utils::reader::Reader, traits::is_empty
};
use crate::public_circuit_public_inputs::PublicCircuitPublicInputs;

#[oracle(enqueuePublicFunctionCall)]
fn enqueue_public_function_call_oracle(
    _contract_address: AztecAddress,
    _function_selector: FunctionSelector,
    _args_hash: Field,
    _side_effect_counter: u32,
    _is_static_call: bool,
    _is_delegate_call: bool
) -> [Field; ENQUEUE_PUBLIC_FUNCTION_CALL_RETURN_LENGTH] {}

unconstrained pub fn enqueue_public_function_call_internal(
    contract_address: AztecAddress,
    function_selector: FunctionSelector,
    args_hash: Field,
    side_effect_counter: u32,
    is_static_call: bool,
    is_delegate_call: bool
) -> [Field; ENQUEUE_PUBLIC_FUNCTION_CALL_RETURN_LENGTH] {
    enqueue_public_function_call_oracle(
        contract_address,
        function_selector,
        args_hash,
        side_effect_counter,
        is_static_call,
        is_delegate_call
    )
}

#[oracle(callPrivateFunction)]
fn call_private_function_oracle(
    _contract_address: AztecAddress,
    _function_selector: FunctionSelector,
    _args_hash: Field,
    _start_side_effect_counter: u32,
    _is_static_call: bool,
    _is_delegate_call: bool
) -> [Field; PRIVATE_CALL_STACK_ITEM_LENGTH] {}

unconstrained pub fn call_private_function_internal(
    contract_address: AztecAddress,
    function_selector: FunctionSelector,
    args_hash: Field,
    start_side_effect_counter: u32,
    is_static_call: bool,
    is_delegate_call: bool
) -> PrivateCallStackItem {
    let fields = call_private_function_oracle(
        contract_address,
        function_selector,
        args_hash,
        start_side_effect_counter,
        is_static_call,
        is_delegate_call
    );

    PrivateCallStackItem::deserialize(fields)
}

struct PublicInputs {
    private_call_stack_hashes : [Field; MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL],
    public_call_stack_hashes :  [Field; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL],
    side_effect_counter: u32,
}

struct PrivateContext {
    private_call_stack_hashes : BoundedVec<Field, MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL>,
    public_call_stack_hashes : BoundedVec<Field, MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL>,
    side_effect_counter: u32,
}

impl PrivateContext {
    pub fn new() -> PrivateContext {
        PrivateContext {
            private_call_stack_hashes: BoundedVec::new(),
            public_call_stack_hashes: BoundedVec::new(),
            side_effect_counter: 0
        }
    }

    pub fn finish(self) -> PublicInputs {
        PublicInputs {
            private_call_stack_hashes: self.private_call_stack_hashes.storage,
            public_call_stack_hashes: self.public_call_stack_hashes.storage,
            side_effect_counter: self.side_effect_counter
        }
    }

    pub fn call_private_function_with_packed_args(
        &mut self,
        contract_address: AztecAddress,
        function_selector: FunctionSelector,
        args_hash: Field,
        is_static_call: bool,
        is_delegate_call: bool
    ) -> [Field; RETURN_VALUES_LENGTH] {
        let mut is_static_call = is_static_call;
        let item = call_private_function_internal(
            contract_address,
            function_selector,
            args_hash,
            self.side_effect_counter,
            is_static_call,
            is_delegate_call
        );

        assert_eq(item.public_inputs.call_context.side_effect_counter, self.side_effect_counter);
        assert_eq(item.public_inputs.start_side_effect_counter, self.side_effect_counter);
        self.side_effect_counter = item.public_inputs.end_side_effect_counter + 1;

        assert(contract_address.eq(item.contract_address));
        assert(function_selector.eq(item.function_data.selector));

        assert(args_hash == item.public_inputs.args_hash);

        // Assert that the call context of the enqueued call generated by the oracle matches our request.
        assert(item.public_inputs.call_context.is_delegate_call == is_delegate_call);
        assert(item.public_inputs.call_context.is_static_call == is_static_call);

        self.private_call_stack_hashes.push(item.hash());

        item.public_inputs.return_values
    }

    pub fn call_public_function_with_packed_args(
        &mut self,
        contract_address: AztecAddress,
        function_selector: FunctionSelector,
        args_hash: Field,
        is_static_call: bool,
        is_delegate_call: bool
    ) {
        let mut is_static_call = is_static_call;
        let fields = enqueue_public_function_call_internal(
            contract_address,
            function_selector,
            args_hash,
            self.side_effect_counter,
            is_static_call,
            is_delegate_call
        );

        let mut reader = Reader::new(fields);

        // Note: Not using PublicCirclePublicInputs::deserialize here, because everything below args_hash is 0 and
        // there is no more data in fields because there is only ENQUEUE_PUBLIC_FUNCTION_CALL_RETURN_SIZE fields!
        let item = PublicCallStackItem {
            contract_address: AztecAddress::from_field(reader.read()),
            function_data: reader.read_struct(FunctionData::deserialize),
            public_inputs: PublicCircuitPublicInputs {
                call_context: reader.read_struct(CallContext::deserialize),
                args_hash: reader.read(),
                return_values: [0; RETURN_VALUES_LENGTH],
                nullifier_read_requests: [ReadRequest::empty(); MAX_NULLIFIER_READ_REQUESTS_PER_CALL],
                nullifier_non_existent_read_requests: [ReadRequest::empty(); MAX_NULLIFIER_NON_EXISTENT_READ_REQUESTS_PER_CALL],
                contract_storage_update_requests: [StorageUpdateRequest::empty(); MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL],
                contract_storage_reads: [StorageRead::empty(); MAX_PUBLIC_DATA_READS_PER_CALL],
                public_call_stack_hashes: [0; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL],
                new_note_hashes: [SideEffect::empty(); MAX_NEW_NOTE_HASHES_PER_CALL],
                new_nullifiers: [SideEffectLinkedToNoteHash::empty(); MAX_NEW_NULLIFIERS_PER_CALL],
                new_l2_to_l1_msgs: [L2ToL1Message::empty(); MAX_NEW_L2_TO_L1_MSGS_PER_CALL],
                start_side_effect_counter: 0,
                end_side_effect_counter: 0,
                unencrypted_logs_hash: 0,
                unencrypted_log_preimages_length: 0,
                historical_header: Header::empty(),
                prover_address: AztecAddress::zero(),
                revert_code: 0
            },
            is_execution_request: true
        };
        reader.finish();

        assert(contract_address.eq(item.contract_address));
        assert(function_selector.eq(item.function_data.selector));

        assert_eq(item.public_inputs.call_context.side_effect_counter, self.side_effect_counter);
        // We increment the sideffect counter by one, to account for the call itself being a side effect.
        self.side_effect_counter = self.side_effect_counter + 1;

        assert(args_hash == item.public_inputs.args_hash);

        // Assert that the call context of the enqueued call generated by the oracle matches our request.
        assert(item.public_inputs.call_context.is_delegate_call == is_delegate_call);
        assert(item.public_inputs.call_context.is_static_call == is_static_call);

        self.public_call_stack_hashes.push(item.hash());
    }
}
