use std::time::Duration;

#[derive(Debug, Clone)]
pub struct SyncPoint {
    pub text_index: usize,
    pub timestamp: Duration,
}

#[derive(Debug, Clone, Default)]
pub struct SyncMap {
    points: Vec<SyncPoint>,
}

impl SyncMap {
    pub fn push_point(&mut self, text_index: usize, timestamp: Duration) {
        self.points.push(SyncPoint {
            text_index,
            timestamp,
        });
    }

    pub fn resolve_index(&self, timestamp: Duration) -> Option<usize> {
        self.points
            .iter()
            .rev()
            .find(|point| point.timestamp <= timestamp)
            .map(|point| point.text_index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_to_closest_prior_point() {
        let mut map = SyncMap::default();
        map.push_point(0, Duration::from_millis(0));
        map.push_point(5, Duration::from_millis(100));
        map.push_point(10, Duration::from_millis(300));

        assert_eq!(map.resolve_index(Duration::from_millis(50)), Some(0));
        assert_eq!(map.resolve_index(Duration::from_millis(150)), Some(5));
        assert_eq!(map.resolve_index(Duration::from_millis(400)), Some(10));
    }
}
