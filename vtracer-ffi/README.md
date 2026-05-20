# vtracer-ffi

vtracer (https://github.com/visioncortex/vtracer) の C ABI ラッパー。
DraftCanvas の ImageVectorizer から `libvtracer_ffi.a` として静的リンクする。

## 事前条件

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

## Universal binary ビルド

```bash
cd vtracer-ffi
bash build_universal.sh
```

出力先: `DraftCanvas/Vendor/vtracer/libvtracer_ffi.a`

ビルド後 `libvtracer_ffi.a` と `vtracer_ffi.h` を git commit すること。

## API

```c
int32_t vtracer_convert(
    const uint8_t *image_bytes, size_t image_len,
    const VtracerParams *params,
    uint8_t **out_svg_ptr, size_t *out_svg_len
);
void vtracer_free(uint8_t *ptr, size_t len);
```

戻り値: 0=OK, 1=invalid_args, 2=decode_failed, 3=conversion_failed
