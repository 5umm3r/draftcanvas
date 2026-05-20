#ifndef VTRACER_FFI_H
#define VTRACER_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VtracerParams {
    int32_t color_precision;
    int32_t filter_speckle;
    int32_t corner_threshold;
    double  length_threshold;
    int32_t splice_threshold;
    int32_t layer_difference;
    /// 0=spline, 1=polygon, 2=none
    int32_t mode;
} VtracerParams;

/// PNG/JPEG バイト列を SVG 文字列バッファに変換する。
/// 戻り値: 0=OK, 1=invalid_args, 2=decode_failed, 3=conversion_failed
/// 成功時は vtracer_free(*out_svg_ptr, *out_svg_len) で解放すること。
int32_t vtracer_convert(
    const uint8_t *image_bytes,
    size_t image_len,
    const VtracerParams *params,
    uint8_t **out_svg_ptr,
    size_t *out_svg_len
);

/// vtracer_convert が確保したバッファを解放する。
void vtracer_free(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* VTRACER_FFI_H */
