use std::slice;
use image::io::Reader as ImageReader;
use std::io::Cursor;
use visioncortex::{ColorImage, PathSimplifyMode};
use vtracer::{Config, ColorMode, Hierarchical};

#[repr(C)]
pub struct VtracerParams {
    pub color_precision: i32,
    pub filter_speckle: i32,
    pub corner_threshold: i32,
    pub length_threshold: f64,
    pub splice_threshold: i32,
    pub layer_difference: i32,
    /// 0=spline, 1=polygon, 2=none
    pub mode: i32,
}

/// PNG/JPEG バイト列を SVG 文字列バッファに変換する。
/// 成功時: 0 を返し *out_svg_ptr / *out_svg_len に SVG バッファをセット。
/// 呼び出し側は vtracer_free_svg(*out_svg_ptr, *out_svg_len) で必ず解放すること。
/// エラー時: 非ゼロを返す。out_svg_ptr は変更しない。
///
/// 戻り値: 0=OK, 1=invalid_args, 2=decode_failed, 3=conversion_failed
#[no_mangle]
pub unsafe extern "C" fn vtracer_convert(
    image_bytes: *const u8,
    image_len: usize,
    params: *const VtracerParams,
    out_svg_ptr: *mut *mut u8,
    out_svg_len: *mut usize,
) -> i32 {
    if image_bytes.is_null() || params.is_null() || out_svg_ptr.is_null() || out_svg_len.is_null() {
        return 1;
    }

    let bytes = slice::from_raw_parts(image_bytes, image_len);
    let params = &*params;

    let color_image = match decode_image(bytes) {
        Some(img) => img,
        None => return 2,
    };

    let config = build_config(params);

    let svg_file = match vtracer::convert(color_image, config) {
        Ok(f) => f,
        Err(_) => return 3,
    };

    let svg_string = svg_file.to_string();
    let mut boxed = svg_string.into_bytes().into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    *out_svg_ptr = ptr;
    *out_svg_len = len;
    0
}

/// vtracer_convert が書き出したバッファを解放する。
#[no_mangle]
pub unsafe extern "C" fn vtracer_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    drop(Box::from_raw(slice::from_raw_parts_mut(ptr, len)));
}

fn decode_image(bytes: &[u8]) -> Option<ColorImage> {
    let cursor = Cursor::new(bytes);
    let reader = ImageReader::new(cursor).with_guessed_format().ok()?;
    let dynamic_img = reader.decode().ok()?;
    let rgba = dynamic_img.to_rgba8();
    let width = rgba.width() as usize;
    let height = rgba.height() as usize;
    let pixels = rgba.into_raw();
    Some(ColorImage { pixels, width, height })
}

fn build_config(p: &VtracerParams) -> Config {
    let mode = match p.mode {
        1 => PathSimplifyMode::Polygon,
        2 => PathSimplifyMode::None,
        _ => PathSimplifyMode::Spline,
    };
    Config {
        color_mode: ColorMode::Color,
        hierarchical: Hierarchical::Stacked,
        filter_speckle: p.filter_speckle.max(0) as usize,
        color_precision: p.color_precision,
        layer_difference: p.layer_difference,
        mode,
        corner_threshold: p.corner_threshold,
        length_threshold: p.length_threshold,
        max_iterations: 10,
        splice_threshold: p.splice_threshold,
        path_precision: Some(2),
    }
}
