use std::fmt::Write;

const HUMIDIFI_IX_DATA_KEY: u64 = 0xC3EBBAE2FF2FFF3A;
const POS_INC: u64 = 0x0001_0001_0001_0001;

fn obfuscate_instruction_data(data: &mut [u8]) {
    let mut qwords = data.chunks_exact_mut(8);
    let mut pos_mask: u64 = 0;
    for chunk in qwords.by_ref() {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(chunk);
        let mut enc = u64::from_le_bytes(bytes);
        enc ^= HUMIDIFI_IX_DATA_KEY;
        enc ^= pos_mask;
        chunk.copy_from_slice(&enc.to_le_bytes());
        pos_mask = pos_mask.wrapping_add(POS_INC);
    }

    let remainder = qwords.remainder();
    if !remainder.is_empty() {
        let mut tmp = [0u8; 8];
        tmp[..remainder.len()].copy_from_slice(remainder);
        let mut rem_val = u64::from_le_bytes(tmp);
        rem_val ^= HUMIDIFI_IX_DATA_KEY;
        rem_val ^= pos_mask;
        let rem_enc = rem_val.to_le_bytes();
        remainder.copy_from_slice(&rem_enc[..remainder.len()]);
    }
}

fn hex(data: &[u8]) -> String {
    let mut s = String::new();
    for (i, b) in data.iter().enumerate() {
        if i > 0 { s.push(' '); }
        let _ = write!(&mut s, "{:02x}", b);
    }
    s
}

fn main() {
    let mut data: Vec<u8> = (1u8..=17).collect();
    println!("before: {}", hex(&data));
    obfuscate_instruction_data(&mut data);
    println!("after:  {}", hex(&data));
    obfuscate_instruction_data(&mut data);
    println!("again:  {}", hex(&data));
}

