package ashui.media;

import haxe.io.Bytes;
import media.AudioData;
import media.EncodedAudioChunk;
import media.EncodedVideoChunk;
import media.MediaQueue;
import media.VideoFrame;

/** Typed streaming queues backed by hlavi; no implicit frame dropping. **/
class Stream<T> extends MediaChannel<T, T> {
	static function queue(kind:media.MediaPayloadKind, ?limits:MediaLimits):MediaQueue {
		var capacity = MediaChannel.capacity(limits);
		return MediaQueue.create(kind, capacity.items, capacity.bytes);
	}

	public static function audio(?limits:MediaLimits):Stream<AudioData> {
		var q = queue(Audio, limits);
		return new Stream(q.writeAudio, q.poll, q.readAudio, q.finish, q.close);
	}

	public static function video(?limits:MediaLimits):Stream<VideoFrame> {
		var q = queue(Video, limits);
		return new Stream(q.writeVideo, q.poll, q.readVideo, q.finish, q.close);
	}

	public static function audioChunks(?limits:MediaLimits):Stream<EncodedAudioChunk> {
		var q = queue(AudioChunk, limits);
		return new Stream(q.writeAudioChunk, q.poll, q.readAudioChunk, q.finish, q.close);
	}

	public static function videoChunks(?limits:MediaLimits):Stream<EncodedVideoChunk> {
		var q = queue(VideoChunk, limits);
		return new Stream(q.writeVideoChunk, q.poll, q.readVideoChunk, q.finish, q.close);
	}

	/** Copies each byte block on write; preserves block boundaries on read. **/
	public static function bytes(?limits:MediaLimits):Stream<Bytes> {
		var q = queue(media.MediaPayloadKind.Bytes, limits);
		return new Stream(q.writeBytes, q.poll, () -> {
			var bytes = Bytes.alloc(haxe.Int64.toInt(q.byteLength()));
			q.readBytes(bytes);
			return bytes;
		}, q.finish, q.close);
	}
}
