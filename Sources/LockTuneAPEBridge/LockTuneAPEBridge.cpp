#include "LockTuneAPEBridge.h"

#include <MAC/All.h>
#include <MAC/CharacterHelper.h>
#include <MAC/MACLib.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <new>
#include <vector>

struct LTAPEDecoder {
    APE::IAPEDecompress *decoder;
    int32_t channels;
    int32_t bits_per_sample;
    int32_t block_align;
    bool floating_point;
    std::vector<unsigned char> scratch;
};

static float sample_to_float(const unsigned char *bytes, int32_t bits, bool floating_point) {
    if (floating_point && bits == 32) {
        float value = 0;
        std::memcpy(&value, bytes, sizeof(value));
        return std::isfinite(value) ? value : 0;
    }
    switch (bits) {
    case 8:
        return (static_cast<int32_t>(*bytes) - 128) / 128.0f;
    case 16: {
        int16_t value = 0;
        std::memcpy(&value, bytes, sizeof(value));
        return value / 32768.0f;
    }
    case 24: {
        int32_t value = static_cast<int32_t>(bytes[0])
            | (static_cast<int32_t>(bytes[1]) << 8)
            | (static_cast<int32_t>(bytes[2]) << 16);
        if ((value & 0x00800000) != 0) value |= static_cast<int32_t>(0xff000000);
        return value / 8388608.0f;
    }
    case 32: {
        int32_t value = 0;
        std::memcpy(&value, bytes, sizeof(value));
        return static_cast<float>(value / 2147483648.0);
    }
    default:
        return 0;
    }
}

LTAPEDecoder *lt_ape_decoder_open(
    const char *utf8_path,
    LTAPEAudioFormat *format,
    int32_t *error_code
) {
    if (error_code) *error_code = ERROR_BAD_PARAMETER;
    if (!utf8_path || !format) return nullptr;

    auto *utfn_path = APE::CAPECharacterHelper::GetUTFNFromUTF8(
        reinterpret_cast<const APE::str_utf8 *>(utf8_path)
    );
    if (!utfn_path) return nullptr;
    int decoder_error = ERROR_UNDEFINED;
    auto *ape = CreateIAPEDecompress(utfn_path, &decoder_error, true, false, false);
    delete[] utfn_path;
    if (!ape) {
        if (error_code) *error_code = decoder_error;
        return nullptr;
    }

    auto *result = new (std::nothrow) LTAPEDecoder;
    if (!result) {
        delete ape;
        if (error_code) *error_code = ERROR_INSUFFICIENT_MEMORY;
        return nullptr;
    }
    result->decoder = ape;
    result->channels = static_cast<int32_t>(ape->GetInfo(APE::IAPEDecompress::APE_INFO_CHANNELS));
    result->bits_per_sample = static_cast<int32_t>(ape->GetInfo(APE::IAPEDecompress::APE_INFO_BITS_PER_SAMPLE));
    result->block_align = static_cast<int32_t>(ape->GetInfo(APE::IAPEDecompress::APE_INFO_BLOCK_ALIGN));
    const auto flags = ape->GetInfo(APE::IAPEDecompress::APE_INFO_FORMAT_FLAGS);
    result->floating_point = (flags & APE_FORMAT_FLAG_FLOATING_POINT) != 0;

    format->sample_rate = static_cast<double>(ape->GetInfo(APE::IAPEDecompress::APE_INFO_SAMPLE_RATE));
    format->channel_count = result->channels;
    format->total_frames = ape->GetInfo(APE::IAPEDecompress::APE_DECOMPRESS_TOTAL_BLOCKS);
    if (format->sample_rate <= 0 || format->channel_count <= 0 || format->total_frames <= 0
        || result->block_align <= 0) {
        delete result->decoder;
        delete result;
        if (error_code) *error_code = ERROR_INVALID_INPUT_FILE;
        return nullptr;
    }
    if (error_code) *error_code = ERROR_SUCCESS;
    return result;
}

int64_t lt_ape_decoder_read_float(
    LTAPEDecoder *decoder,
    float *interleaved_samples,
    int64_t maximum_frames,
    int32_t *error_code
) {
    if (error_code) *error_code = ERROR_BAD_PARAMETER;
    if (!decoder || !interleaved_samples || maximum_frames <= 0) return 0;

    const auto byte_count = static_cast<size_t>(maximum_frames)
        * static_cast<size_t>(decoder->block_align);
    decoder->scratch.resize(byte_count);
    int64_t frames_read = 0;
    APE::IAPEDecompress::APE_GET_DATA_PROCESSING processing { true, false, false };
    const int result = decoder->decoder->GetData(
        decoder->scratch.data(), maximum_frames, &frames_read, &processing
    );
    if (result != ERROR_SUCCESS) {
        if (error_code) *error_code = result;
        return 0;
    }

    const int32_t bytes_per_sample = decoder->block_align / decoder->channels;
    const int64_t sample_count = frames_read * decoder->channels;
    for (int64_t sample = 0; sample < sample_count; ++sample) {
        interleaved_samples[sample] = sample_to_float(
            decoder->scratch.data() + sample * bytes_per_sample,
            decoder->bits_per_sample,
            decoder->floating_point
        );
    }
    if (error_code) *error_code = ERROR_SUCCESS;
    return frames_read;
}

int32_t lt_ape_decoder_seek(LTAPEDecoder *decoder, int64_t frame) {
    if (!decoder) return ERROR_BAD_PARAMETER;
    return decoder->decoder->Seek(std::max<int64_t>(0, frame));
}

void lt_ape_decoder_close(LTAPEDecoder *decoder) {
    if (!decoder) return;
    delete decoder->decoder;
    delete decoder;
}
