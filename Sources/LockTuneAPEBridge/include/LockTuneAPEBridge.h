#ifndef LOCKTUNE_APE_BRIDGE_H
#define LOCKTUNE_APE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LTAPEDecoder LTAPEDecoder;

typedef struct {
    double sample_rate;
    int32_t channel_count;
    int64_t total_frames;
} LTAPEAudioFormat;

LTAPEDecoder *lt_ape_decoder_open(
    const char *utf8_path,
    LTAPEAudioFormat *format,
    int32_t *error_code
);

int64_t lt_ape_decoder_read_float(
    LTAPEDecoder *decoder,
    float *interleaved_samples,
    int64_t maximum_frames,
    int32_t *error_code
);

int32_t lt_ape_decoder_seek(LTAPEDecoder *decoder, int64_t frame);
void lt_ape_decoder_close(LTAPEDecoder *decoder);

#ifdef __cplusplus
}
#endif

#endif
