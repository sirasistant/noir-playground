use dep::std::hash::{pedersen_hash_with_separator, sha256, poseidon2::{Poseidon2, Poseidon2Hasher}};

pub fn pedersen_hash<N>(inputs: [Field; N], hash_index: u32) -> Field {
    dep::std::hash::pedersen_hash_with_separator(inputs, hash_index)
}

pub fn poseidon_hash<N>(inputs: [Field; N]) -> Field {
    Poseidon2::hash(inputs, inputs.len())
}
