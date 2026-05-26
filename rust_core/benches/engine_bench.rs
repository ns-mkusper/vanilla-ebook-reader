use criterion::{black_box, criterion_group, criterion_main, Criterion};
use rust_core::engine::{chunk_audio_samples, AudioFrame};

fn chunk_audio_samples_benchmark(c: &mut Criterion) {
    let sample_rate = 16_000;
    let samples = vec![128i16; sample_rate as usize * 3];
    c.bench_function("chunk_audio_samples_three_seconds", |b| {
        b.iter(|| {
            let frames: Vec<AudioFrame> =
                chunk_audio_samples(black_box(samples.clone()), sample_rate, 4096);
            black_box(frames)
        })
    });
}

criterion_group!(benches, chunk_audio_samples_benchmark);
criterion_main!(benches);
