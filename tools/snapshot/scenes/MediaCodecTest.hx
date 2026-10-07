import ashui.core.render.Snapshot;
import ashui.media.Codec;
import ashui.media.MediaChannel.ChannelState;
import ashui.media.Stream;
import haxe.Int64;
import haxe.io.Bytes;
import media.AudioData;
import media.AudioDataInit;
import media.AudioSampleFormat;
import media.CodecConfiguration;
import media.EncodedAudioChunk;
import media.EncodedVideoChunk;
import media.MediaDemuxer;
import media.MediaMuxer;
import media.StreamReadStatus;
import media.VideoFrame;
import media.VideoFrameBufferInit;
import media.VideoPixelFormat;

/** Real codec workers and bounded queues; no window or simulated media clock. **/
class MediaCodecTest {
	static var checks = 0;
	static function check(label:String, ok:Bool):Void {
		if (!ok) throw 'FAIL $label';
		checks++; Sys.println('ok $label');
	}
	static function step(deadline:Float):Void {
		if (Sys.time() > deadline) throw "Native codec pipeline timed out";
		Sys.sleep(0.001);
	}

	static function queues():Void {
		var stream = Stream.bytes({maxItems: 1, maxBytes: 16});
		check("an empty stream is pending", stream.poll() == Pending);
		var bytes = Bytes.ofString("first");
		check("a bounded stream accepts its first block", stream.tryWrite(bytes));
		bytes.set(0, 0);
		check("a full queue reports backpressure", !stream.tryWrite(Bytes.ofString("second")) && stream.state.get() == Backpressured);
		check("byte writes copy and preserve block boundaries", stream.poll() == Ready && stream.read().toString() == "first");
		check("a rejected write can be retried after draining", stream.tryWrite(Bytes.ofString("second")) && stream.state.get() == Open);
		stream.finish(); check("finish enters the FSM draining state", stream.state.get() == Draining);
		check("finish drains accepted data before EOF", stream.poll() == Ready && stream.read().toString() == "second" && stream.poll() == Ended && stream.state.get() == ChannelState.Ended);
		stream.close(); stream.close(); check("stream close is idempotent", stream.state.get() == Closed && stream.disposed);
		var rejected = false; try stream.tryWrite(bytes) catch (_:Dynamic) rejected = true;
		check("closed streams reject writes", rejected);
		var video = Stream.video({maxItems: 1, maxBytes: 16});
		var frame = VideoFrame.create(Bytes.alloc(16), new VideoFrameBufferInit(RGBA, Int64.ofInt(2), Int64.ofInt(2), Int64.ofInt(77)));
		video.tryWrite(frame); frame.close();
		var retained = video.read(); video.close();
		check("streams retain input and transfer independent output ownership", Int64.toInt(retained.timestamp()) == 77);
		retained.close();
		var bad = Stream.bytes({maxItems: 1, maxBytes: 4});
		rejected = false; try bad.tryWrite(Bytes.alloc(5)) catch (_:Dynamic) rejected = true;
		check("native stream errors become reactive failures", rejected && bad.state.get() == Failed && bad.error.get() != null);
		bad.close();
		var cleanup:Void->Void = null;
		var scoped = ashui.reactive.Owner.root(new ashui.layout.LayoutTree(), dispose -> { cleanup = dispose; return Stream.bytes(); });
		cleanup(); check("owner cleanup closes native channels", scoped.disposed && scoped.state.get() == Closed);
	}

	static function audio():Void {
		var encoder = Codec.audioEncoder({sampleRate: 48000, channels: 1, bitrate: 96000, limits: {maxItems: 2, maxBytes: 65536}});
		var decoder:Codec<EncodedAudioChunk, AudioData> = null;
		var config:Null<CodecConfiguration> = null;
		var pending:Null<AudioData> = null;
		var chunk:Null<EncodedAudioChunk> = null;
		var input = 0, encoded = 0, decoded = 0, samples = 0;
		var metadata = true;
		var encoderFinished = false, decoderFinished = false;
		var deadline = Sys.time() + 15;
		try {
			while (decoder == null || decoder.poll() != Ended) {
				if (input < 12 && pending == null) {
					var pcm = Bytes.alloc(2048);
					for (i in 0...1024) pcm.setUInt16(i * 2, Std.int(Math.sin((input * 1024 + i) * Math.PI * 880 / 48000) * 8000) & 0xffff);
					pending = AudioData.create(new AudioDataInit(S16, 48000, Int64.ofInt(1024), Int64.ofInt(1), Int64.ofInt(Std.int(input * 1024 * 1000000.0 / 48000)), pcm));
				}
				if (pending != null && encoder.tryWrite(pending)) { pending.close(); pending = null; input++; }
				if (input == 12 && !encoderFinished) { encoder.finish(); encoderFinished = true; }
				if (chunk == null && encoder.poll() == Ready) {
					if (decoder == null) { config = encoder.getConfiguration(); decoder = Codec.audioDecoder(config, {maxItems: 2, maxBytes: 65536}); }
					chunk = encoder.read(); encoded++;
				}
				if (chunk != null && decoder.tryWrite(chunk)) { chunk.close(); chunk = null; }
				if (encoder.poll() == Ended && chunk == null && decoder != null && !decoderFinished) { decoder.finish(); decoderFinished = true; }
				if (decoder != null) while (decoder.poll() == Ready) {
					var pcm = decoder.read();
					metadata = metadata && pcm.sampleRate() == 48000 && Int64.toInt(pcm.numberOfChannels()) == 1;
					samples += Int64.toInt(pcm.numberOfFrames()); decoded++; pcm.close();
				}
				step(deadline);
			}
			check("AAC encoding and decoding flush real native output", encoded > 0 && decoded > 0 && samples >= 1024 && encoder.state.get() == ChannelState.Ended && decoder.state.get() == ChannelState.Ended);
			check("AAC decoded PCM keeps its sample rate and channels", metadata);
		} catch (e:Dynamic) {
			if (pending != null) pending.close(); if (chunk != null) chunk.close();
			if (config != null) config.close(); if (decoder != null) decoder.close(); encoder.close(); throw e;
		}
		config.close(); decoder.close(); encoder.close();
	}

	static function pixels(index:Int):VideoFrame {
		var bytes = Bytes.alloc(64 * 64 * 4);
		for (y in 0...64) for (x in 0...64) {
			var at = (y * 64 + x) * 4;
			bytes.set(at, x * 3); bytes.set(at + 1, y * 3); bytes.set(at + 2, index * 15); bytes.set(at + 3, 255);
		}
		var init = new VideoFrameBufferInit(BGRA, Int64.ofInt(64), Int64.ofInt(64), Int64.ofInt(Std.int(index * 1000000.0 / 15)));
		init.duration(Int64.ofInt(66667));
		return VideoFrame.create(bytes, init);
	}

	static function video():Void {
		var dir = Snapshot.dir(); sys.FileSystem.createDirectory(dir);
		var path = sys.FileSystem.fullPath(dir) + '/codec-${Std.int(Sys.time())}-${Std.random(1000000)}.mp4';
		var encoder = Codec.videoEncoder({width: 64, height: 64, framerate: 15, bitrate: 200000, limits: {maxItems: 2, maxBytes: 1048576}});
		var writer:MediaMuxer = 0;
		var config:CodecConfiguration = 0;
		var frame:VideoFrame = 0, chunk:EncodedVideoChunk = 0;
		var index = 0, packets = 0;
		var finished = false;
		var deadline = Sys.time() + 20;
		try {
			while (encoder.poll() != Ended || chunk != 0) {
				if (index < 12 && frame == 0) frame = pixels(index);
				if (frame != 0 && encoder.tryWrite(frame)) { frame.close(); frame = 0; index++; }
				if (index == 12 && !finished) { encoder.finish(); finished = true; }
				if (chunk == 0 && encoder.poll() == Ready) {
					if (writer == 0) {
						config = encoder.getConfiguration();
						writer = MediaMuxer.video(path, config, Int64.ofInt(0), Int64.ofInt(66667), 2, Int64.ofInt(1048576));
					}
					chunk = encoder.read(); packets++;
				}
				if (chunk != 0 && writer.writeVideoChunk(chunk)) { chunk.close(); chunk = 0; }
				step(deadline);
			}
			writer.endVideoTrack(); writer.finish();
			while (!writer.finished()) step(deadline);
			writer.close(); writer = 0; config.close(); config = 0; encoder.close();
			check("H.264 encoding writes a finalized MP4", packets == 12 && sys.FileSystem.stat(path).size > 0);
		} catch (e:Dynamic) {
			if (frame != 0) frame.close(); if (chunk != 0) chunk.close(); if (writer != 0) writer.close(); if (config != 0) config.close(); encoder.close(); throw e;
		}
		var reader = MediaDemuxer.open(path, 2, Int64.ofInt(1048576));
		check("MP4 demux metadata exposes the encoded track", reader.hasVideo() && !reader.hasAudio() && reader.duration() > 0.7);
		var config = reader.getVideoConfiguration();
		var decoder = Codec.videoDecoder(config, {maxItems: 2, maxBytes: 1048576}); config.close();
		var decoded = 0, pending:EncodedVideoChunk = 0;
		var ended = false, last = -1;
		var metadata = true;
		try {
			while (decoder.poll() != Ended) {
				if (pending == 0 && reader.videoStatus() == Ready) pending = reader.readVideoChunk();
				if (pending != 0 && decoder.tryWrite(pending)) { pending.close(); pending = 0; }
				if (!ended && pending == 0 && reader.videoStatus() == Ended) { decoder.finish(); ended = true; }
				while (decoder.poll() == Ready) {
					var decodedFrame = decoder.read();
					metadata = metadata && Int64.toInt(decodedFrame.displayWidth()) == 64 && Int64.toInt(decodedFrame.displayHeight()) == 64 && Int64.toInt(decodedFrame.timestamp()) >= last;
					last = Int64.toInt(decodedFrame.timestamp()); decoded++; decodedFrame.close();
				}
				step(deadline);
			}
			check("incremental demux and video decoding reach EOF", decoded == 12 && last > 700000);
			check("decoded H.264 frames preserve dimensions and timing", metadata);
		} catch (e:Dynamic) { if (pending != 0) pending.close(); decoder.close(); reader.close(); throw e; }
		decoder.close(); reader.close();
	}

	static function main():Void {
		queues(); audio(); video();
		Snapshot.event('media-codecs $checks checks passed');
		Sys.println('$checks codec/stream checks passed');
	}
}
