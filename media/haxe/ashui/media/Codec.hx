package ashui.media;

import media.AudioData;
import media.CodecConfiguration;
import media.EncodedAudioChunk;
import media.EncodedVideoChunk;
import media.VideoFrame;

typedef AudioEncoding = {
	sampleRate:Int,
	channels:Int,
	?codec:String,
	?bitrate:Int,
	?limits:MediaLimits
}

typedef VideoEncoding = {
	width:Int,
	height:Int,
	?codec:String,
	?bitrate:Int,
	?framerate:Float,
	?limits:MediaLimits
}

/** Native worker codecs with typed input/output, bounded queues and reactive FSM states. **/
class Codec<Input, Output> extends MediaChannel<Input, Output> {
	public static inline var AAC = "mp4a.40.2";
	public static inline var H264 = "avc1.42001E";
	var configurationNative:Null<Void->CodecConfiguration>;

	/** After the encoder first reports Ready. Returns an owned configuration; caller must close it. **/
	public function getConfiguration():CodecConfiguration {
		checkOpen();
		if (configurationNative == null) throw "Decoder sessions do not produce an encoder configuration";
		// No configuration before first output is an expected retryable native condition.
		return configurationNative();
	}

	public static function audioEncoder(options:AudioEncoding):Codec<AudioData, EncodedAudioChunk> {
		var capacity = MediaChannel.capacity(options.limits);
		var native = media.AudioEncoder.create(options.codec == null ? AAC : options.codec,
			haxe.Int64.ofInt(options.sampleRate), haxe.Int64.ofInt(options.channels),
			haxe.Int64.ofInt(options.bitrate == null ? 128000 : options.bitrate), capacity.items, capacity.bytes);
		var codec = new Codec(native.tryEncode, native.poll, native.read, native.finish, native.close);
		codec.configurationNative = native.getConfiguration;
		return codec;
	}

	public static function videoEncoder(options:VideoEncoding):Codec<VideoFrame, EncodedVideoChunk> {
		var capacity = MediaChannel.capacity(options.limits);
		var native = media.VideoEncoder.create(options.codec == null ? H264 : options.codec,
			haxe.Int64.ofInt(options.width), haxe.Int64.ofInt(options.height),
			haxe.Int64.ofInt(options.bitrate == null ? 2000000 : options.bitrate),
			options.framerate == null ? 30 : options.framerate, capacity.items, capacity.bytes);
		var codec = new Codec(native.tryEncode, native.poll, native.read, native.finish, native.close);
		codec.configurationNative = native.getConfiguration;
		return codec;
	}

	public static function audioDecoder(configuration:CodecConfiguration, ?limits:MediaLimits):Codec<EncodedAudioChunk, AudioData> {
		var capacity = MediaChannel.capacity(limits);
		var native = media.AudioDecoder.create(capacity.items, capacity.bytes, configuration);
		return new Codec(native.tryDecode, native.poll, native.read, native.finish, native.close);
	}

	public static function videoDecoder(configuration:CodecConfiguration, ?limits:MediaLimits):Codec<EncodedVideoChunk, VideoFrame> {
		var capacity = MediaChannel.capacity(limits);
		var native = media.VideoDecoder.create(capacity.items, capacity.bytes, configuration);
		return new Codec(native.tryDecode, native.poll, native.read, native.finish, native.close);
	}
}
