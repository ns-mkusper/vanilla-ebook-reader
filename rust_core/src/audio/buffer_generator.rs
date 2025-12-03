pub fn float_to_pcm_i16(samples: &[f32]) -> Vec<i16> {
    samples
        .iter()
        .map(|sample| {
            let clamped = sample.clamp(-1.0, 1.0);
            (clamped * i16::MAX as f32) as i16
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_with_clamp() {
        let input = vec![-1.5, -0.5, 0.0, 0.5, 1.5];
        let pcm = float_to_pcm_i16(&input);
        assert_eq!(pcm[0], -i16::MAX);
        assert!(pcm[1] < 0);
        assert_eq!(pcm[2], 0);
        assert!(pcm[3] > 0);
        assert_eq!(pcm[4], i16::MAX);
    }
}
