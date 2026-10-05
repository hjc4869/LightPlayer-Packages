using FFmpeg.AutoGen.Abstractions;
#if FFMPEG_STATIC
using FFmpeg.AutoGen.Bindings.StaticallyLinked;
#else
using FFmpeg.AutoGen.Bindings.DynamicallyLoaded;
#endif
using System.Runtime.InteropServices;

internal static unsafe class Program
{
    private static int Main(string[] args)
    {
        try
        {
#if FFMPEG_STATIC
            StaticallyLinkedBindings.Initialize();
#else
            DynamicallyLoadedBindings.Initialize();
#endif
            Require(ffmpeg.avcodec_license().Contains("LGPL", StringComparison.Ordinal), "FFmpeg is not LGPL");
            Console.WriteLine($"FFmpeg {ffmpeg.av_version_info()}; CPU flags 0x{ffmpeg.av_get_cpu_flags():x}");

            foreach (string name in new[] { "h264", "hevc", "av1", "libdav1d", "libjxl", "libjxl_anim", "png", "apng", "webp", "tiff", "mjpeg", "pgssub", "aac", "pcm_s16le" })
                Require(ffmpeg.avcodec_find_decoder_by_name(name) != null, $"Missing decoder {name}");
            foreach (string name in new[] { "hls", "dash", "mov", "matroska", "mpegts", "wav", "sup", "jpeg_pipe", "png_pipe", "webp_pipe", "tiff_pipe", "jpegxl_pipe", "jpegxl_anim" })
                Require(ffmpeg.av_find_input_format(name) != null, $"Missing demuxer {name}");
            foreach (string name in new[] { "aac_mf", "ac3_mf", "av1_mf", "h264_mf", "hevc_mf", "mp3_mf" })
                Require(ffmpeg.avcodec_find_encoder_by_name(name) != null, $"Missing Media Foundation encoder {name}");
            foreach (string name in new[] { "h264", "hevc", "av1", "vp9", "mpeg2video", "vc1", "wmv3" })
            {
                AVCodec* codec = ffmpeg.avcodec_find_decoder_by_name(name);
                bool found = false;
                for (int index = 0; ; index++)
                {
                    AVCodecHWConfig* config = ffmpeg.avcodec_get_hw_config(codec, index);
                    if (config == null) break;
                    found |= config->device_type == AVHWDeviceType.AV_HWDEVICE_TYPE_D3D11VA;
                }
                Require(found, $"Missing D3D11VA configuration for {name}");
            }

            void* protocolState = null;
            var protocols = new List<string>();
            string? protocol;
            while ((protocol = ffmpeg.avio_enum_protocols(&protocolState, 0)) != null)
                protocols.Add(protocol);
            Require(protocols.SequenceEqual(new[] { "file" }), "Unexpected network protocols");

            string directory = Path.Combine(Path.GetTempPath(), $"ffmpeg-static-{Guid.NewGuid():N}");
            Directory.CreateDirectory(directory);
            try
            {
                string wave = Path.Combine(directory, "sample.wav");
                WriteWave(wave);
                Decode(wave, false);
                if (args.Contains("--hardware", StringComparer.Ordinal))
                {
                    ffmpeg.av_log_set_level(ffmpeg.AV_LOG_VERBOSE);
                    string video = Path.Combine(directory, "hardware.h264");
                    EncodeHardware(video);
                    Decode(video, true);
                }
            }
            finally
            {
                Directory.Delete(directory, true);
            }
            Console.WriteLine("NativeAOT FFmpeg consumer passed");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }

    private static void WriteWave(string path)
    {
        using var writer = new BinaryWriter(File.Create(path));
        const int sampleCount = 1600;
        writer.Write("RIFF"u8);
        writer.Write(36 + sampleCount * 2);
        writer.Write("WAVEfmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(16000);
        writer.Write(32000);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(sampleCount * 2);
        for (int index = 0; index < sampleCount; index++) writer.Write((short)(index % 100));
    }

    private static void Decode(string path, bool hardware)
    {
        AVFormatContext* format = null;
        AVCodecContext* context = null;
        AVBufferRef* device = null;
        AVPacket* packet = ffmpeg.av_packet_alloc();
        AVFrame* frame = ffmpeg.av_frame_alloc();
        int decoded = 0;
        try
        {
            Require(packet != null && frame != null, "Frame or packet allocation failed");
            Check(ffmpeg.avformat_open_input(&format, path, null, null), "open input");
            Check(ffmpeg.avformat_find_stream_info(format, null), "read stream info");
            AVCodec* codec = null;
            int stream = ffmpeg.av_find_best_stream(format, hardware ? AVMediaType.AVMEDIA_TYPE_VIDEO : AVMediaType.AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
            Check(stream, "find stream");
            context = ffmpeg.avcodec_alloc_context3(codec);
            Require(context != null, "Decoder allocation failed");
            Check(ffmpeg.avcodec_parameters_to_context(context, format->streams[stream]->codecpar), "copy parameters");
            if (hardware)
            {
                Check(ffmpeg.av_hwdevice_ctx_create(&device, AVHWDeviceType.AV_HWDEVICE_TYPE_D3D11VA, null, null, 0), "create D3D11VA device");
                context->hw_device_ctx = ffmpeg.av_buffer_ref(device);
                Require(context->hw_device_ctx != null, "Device reference failed");
            }
            Check(ffmpeg.avcodec_open2(context, codec, null), "open decoder");
            int result;
            while ((result = ffmpeg.av_read_frame(format, packet)) >= 0)
            {
                if (packet->stream_index == stream)
                {
                    Check(ffmpeg.avcodec_send_packet(context, packet), "send packet");
                    decoded += ReceiveFrames(context, frame, hardware);
                }
                ffmpeg.av_packet_unref(packet);
            }
            Require(result == ffmpeg.AVERROR_EOF, $"Input read failed: {result}");
            Check(ffmpeg.avcodec_send_packet(context, null), "flush decoder");
            decoded += ReceiveFrames(context, frame, hardware);
            Require(decoded > 0, "No frames decoded");
            Console.WriteLine($"Decoded {decoded} {(hardware ? "D3D11VA video" : "PCM audio")} frames");
        }
        finally
        {
            ffmpeg.av_frame_free(&frame);
            ffmpeg.av_packet_free(&packet);
            ffmpeg.avcodec_free_context(&context);
            ffmpeg.av_buffer_unref(&device);
            ffmpeg.avformat_close_input(&format);
        }
    }

    private static int ReceiveFrames(AVCodecContext* context, AVFrame* frame, bool hardware)
    {
        int count = 0;
        int result;
        while ((result = ffmpeg.avcodec_receive_frame(context, frame)) >= 0)
        {
            if (hardware)
                Require(frame->format == (int)AVPixelFormat.AV_PIX_FMT_D3D11, "Decoder fell back to software");
            else
                Require(frame->nb_samples > 0 && frame->sample_rate == 16000, "Invalid decoded audio");
            count++;
            ffmpeg.av_frame_unref(frame);
        }
        if (result != ffmpeg.AVERROR(ffmpeg.EAGAIN) && result != ffmpeg.AVERROR_EOF) Check(result, "receive frame");
        return count;
    }

    private static void EncodeHardware(string path)
    {
        AVCodec* codec = ffmpeg.avcodec_find_encoder_by_name("h264_mf");
        AVCodecContext* context = ffmpeg.avcodec_alloc_context3(codec);
        AVFrame* frame = ffmpeg.av_frame_alloc();
        AVPacket* packet = ffmpeg.av_packet_alloc();
        AVDictionary* options = null;
        using var output = File.Create(path);
        try
        {
            Require(context != null && frame != null && packet != null, "Encoder allocation failed");
            context->width = 320;
            context->height = 180;
            context->pix_fmt = AVPixelFormat.AV_PIX_FMT_NV12;
            context->profile = ffmpeg.AV_PROFILE_H264_MAIN;
            context->time_base = new AVRational { num = 1, den = 30 };
            context->framerate = new AVRational { num = 30, den = 1 };
            context->bit_rate = 500000;
            context->gop_size = 12;
            context->max_b_frames = 0;
            Check(ffmpeg.av_dict_set(&options, "hw_encoding", "1", 0), "set hardware encoder option");
            Check(ffmpeg.avcodec_open2(context, codec, &options), "open hardware Media Foundation encoder");
            frame->format = (int)context->pix_fmt;
            frame->width = context->width;
            frame->height = context->height;
            Check(ffmpeg.av_frame_get_buffer(frame, 32), "allocate encoder frame");
            for (int index = 0; index < 30; index++)
            {
                Check(ffmpeg.av_frame_make_writable(frame), "make frame writable");
                new Span<byte>(frame->data[0], frame->linesize[0] * frame->height).Fill((byte)(32 + index));
                new Span<byte>(frame->data[1], frame->linesize[1] * frame->height / 2).Fill(128);
                frame->pts = index;
                Check(ffmpeg.avcodec_send_frame(context, frame), "send encoder frame");
                ReceivePackets(context, packet, output);
            }
            Check(ffmpeg.avcodec_send_frame(context, null), "flush encoder");
            ReceivePackets(context, packet, output);
            Require(output.Length > 0, "Hardware encoder returned no packets");
            Console.WriteLine($"Media Foundation hardware encoded {output.Length} H.264 bytes");
        }
        finally
        {
            ffmpeg.av_dict_free(&options);
            ffmpeg.av_packet_free(&packet);
            ffmpeg.av_frame_free(&frame);
            ffmpeg.avcodec_free_context(&context);
        }
    }

    private static void ReceivePackets(AVCodecContext* context, AVPacket* packet, Stream output)
    {
        int result;
        while ((result = ffmpeg.avcodec_receive_packet(context, packet)) >= 0)
        {
            output.Write(new ReadOnlySpan<byte>(packet->data, packet->size));
            ffmpeg.av_packet_unref(packet);
        }
        if (result != ffmpeg.AVERROR(ffmpeg.EAGAIN) && result != ffmpeg.AVERROR_EOF) Check(result, "receive packet");
    }

    private static void Check(int result, string operation)
    {
        if (result >= 0) return;
        byte* buffer = stackalloc byte[256];
        ffmpeg.av_strerror(result, buffer, 256);
        throw new InvalidOperationException($"{operation}: {Marshal.PtrToStringUTF8((nint)buffer)} ({result})");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}