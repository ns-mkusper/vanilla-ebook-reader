pub mod library;
pub mod model;
pub mod playback;
pub mod text;

pub use library::{Library, LibraryConfig, LibraryLoader};
pub use model::{AudioChapter, ChapterId, Ebook, EbookId, TextChapter, TextContent, TextFormat};
pub use playback::{
    AudioBackend, PlaybackCommand, PlaybackController, PlaybackEvent, PlaybackState,
};
pub use text::{sentence_segments, SentenceSegment};
