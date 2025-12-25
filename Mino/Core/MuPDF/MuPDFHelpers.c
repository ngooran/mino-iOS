//
//  MuPDFHelpers.c
//  Mino
//
//  C helper functions implementation for MuPDF Swift integration
//

#include "mupdf/fitz.h"
#include "mupdf/pdf.h"
#include "MuPDFHelpers.h"
#include <stdio.h>
#include <string.h>

// Thread-local error message storage
static __thread char last_error[256] = {0};

// Store error message
static void set_error(const char *msg) {
    if (msg) {
        strncpy(last_error, msg, sizeof(last_error) - 1);
        last_error[sizeof(last_error) - 1] = '\0';
    }
}

// Get last error message
const char* mino_get_last_error(void) {
    return last_error[0] ? last_error : NULL;
}

// Clear error message
void mino_clear_error(void) {
    last_error[0] = '\0';
}

// Create a new MuPDF context
fz_context* mino_create_context(void) {
    mino_clear_error();
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (!ctx) {
        set_error("Failed to create MuPDF context");
        return NULL;
    }

    fz_try(ctx) {
        fz_register_document_handlers(ctx);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        fz_drop_context(ctx);
        return NULL;
    }

    return ctx;
}

// Drop/free context
void mino_drop_context(fz_context *ctx) {
    if (ctx) {
        fz_drop_context(ctx);
    }
}

// Open a document
fz_document* mino_open_document(fz_context *ctx, const char *path) {
    if (!ctx || !path) {
        set_error("Invalid context or path");
        return NULL;
    }

    mino_clear_error();
    fz_document *doc = NULL;

    fz_try(ctx) {
        doc = fz_open_document(ctx, path);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return NULL;
    }

    return doc;
}

// Drop/close document
void mino_drop_document(fz_context *ctx, fz_document *doc) {
    if (ctx && doc) {
        fz_drop_document(ctx, doc);
    }
}

// Get page count
int mino_count_pages(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) {
        return -1;
    }

    int count = 0;
    fz_try(ctx) {
        count = fz_count_pages(ctx, doc);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return count;
}

// Get PDF-specific document handle
pdf_document* mino_pdf_specifics(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) {
        return NULL;
    }
    return pdf_specifics(ctx, doc);
}

// Rewrite images in the PDF with compression settings
int mino_rewrite_images(
    fz_context *ctx,
    pdf_document *doc,
    int jpeg_quality,
    int target_dpi,
    int dpi_threshold
) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }

    mino_clear_error();

    // Convert quality integer to string (MuPDF uses strings for quality)
    char quality_str[16];
    snprintf(quality_str, sizeof(quality_str), "%d", jpeg_quality);

    fz_try(ctx) {
        // Set up image rewriter options - zero initialize
        pdf_image_rewriter_options opts = {0};

        // Color lossy images (already JPEG)
        opts.color_lossy_image_subsample_threshold = dpi_threshold;
        opts.color_lossy_image_subsample_to = target_dpi;
        opts.color_lossy_image_recompress_quality = quality_str;
        opts.color_lossy_image_recompress_method = FZ_RECOMPRESS_JPEG;
        opts.color_lossy_image_subsample_method = FZ_SUBSAMPLE_AVERAGE;

        // Color lossless images (PNG, etc.) - convert to JPEG
        opts.color_lossless_image_subsample_threshold = dpi_threshold;
        opts.color_lossless_image_subsample_to = target_dpi;
        opts.color_lossless_image_recompress_quality = quality_str;
        opts.color_lossless_image_recompress_method = FZ_RECOMPRESS_JPEG;
        opts.color_lossless_image_subsample_method = FZ_SUBSAMPLE_AVERAGE;

        // Grayscale lossy images
        opts.gray_lossy_image_subsample_threshold = dpi_threshold;
        opts.gray_lossy_image_subsample_to = target_dpi;
        opts.gray_lossy_image_recompress_quality = quality_str;
        opts.gray_lossy_image_recompress_method = FZ_RECOMPRESS_JPEG;
        opts.gray_lossy_image_subsample_method = FZ_SUBSAMPLE_AVERAGE;

        // Grayscale lossless images
        opts.gray_lossless_image_subsample_threshold = dpi_threshold;
        opts.gray_lossless_image_subsample_to = target_dpi;
        opts.gray_lossless_image_recompress_quality = quality_str;
        opts.gray_lossless_image_recompress_method = FZ_RECOMPRESS_JPEG;
        opts.gray_lossless_image_subsample_method = FZ_SUBSAMPLE_AVERAGE;

        // Rewrite images in the document
        pdf_rewrite_images(ctx, doc, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Compress and save PDF
int mino_compress_pdf(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    int jpeg_quality,
    int target_dpi,
    int garbage_level
) {
    if (!ctx || !doc || !output_path) {
        set_error("Invalid parameters");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        // Rewrite images first
        int dpi_threshold = target_dpi + 50; // Allow some headroom
        mino_rewrite_images(ctx, doc, jpeg_quality, target_dpi, dpi_threshold);

        // Set up write options from the default constant
        pdf_write_options opts = pdf_default_write_options;

        opts.do_garbage = garbage_level;        // 0-4, 4 is maximum
        opts.do_compress = 1;                   // Compress streams
        opts.do_compress_images = 1;            // Compress images
        opts.do_compress_fonts = 1;             // Compress fonts
        opts.do_clean = 1;                      // Clean content streams
        opts.do_sanitize = 1;                   // Sanitize content
        opts.do_linear = 0;                     // Don't linearize (faster)
        opts.do_appearance = 0;                 // Don't regenerate appearances

        // Save the document
        pdf_save_document(ctx, doc, output_path, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Get file size
int64_t mino_get_file_size(const char *path) {
    if (!path) return -1;

    FILE *f = fopen(path, "rb");
    if (!f) return -1;

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return -1;
    }

    int64_t size = ftell(f);
    fclose(f);

    return size;
}

// Render a page to pixmap
fz_pixmap* mino_render_page(
    fz_context *ctx,
    fz_document *doc,
    int page_number,
    float zoom
) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return NULL;
    }

    mino_clear_error();
    fz_pixmap *pix = NULL;
    fz_page *page = NULL;
    fz_device *dev = NULL;

    fz_try(ctx) {
        // Load the page
        page = fz_load_page(ctx, doc, page_number);

        // Get page bounds
        fz_rect bounds = fz_bound_page(ctx, page);

        // Create transformation matrix with zoom
        fz_matrix transform = fz_scale(zoom, zoom);

        // Transform the bounds
        fz_irect bbox = fz_round_rect(fz_transform_rect(bounds, transform));

        // Create pixmap with RGB colorspace and alpha
        pix = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), bbox, NULL, 1);

        // Clear to white
        fz_clear_pixmap_with_value(ctx, pix, 255);

        // Create draw device
        dev = fz_new_draw_device(ctx, transform, pix);

        // Render page
        fz_run_page(ctx, page, dev, fz_identity, NULL);

        // Close device
        fz_close_device(ctx, dev);
    }
    fz_always(ctx) {
        fz_drop_device(ctx, dev);
        fz_drop_page(ctx, page);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        fz_drop_pixmap(ctx, pix);
        return NULL;
    }

    return pix;
}

// Get page dimensions
int mino_get_page_size(
    fz_context *ctx,
    fz_document *doc,
    int page_number,
    float *width,
    float *height
) {
    if (!ctx || !doc || !width || !height) {
        set_error("Invalid parameters");
        return -1;
    }

    mino_clear_error();
    fz_page *page = NULL;

    fz_try(ctx) {
        page = fz_load_page(ctx, doc, page_number);
        fz_rect bounds = fz_bound_page(ctx, page);
        *width = bounds.x1 - bounds.x0;
        *height = bounds.y1 - bounds.y0;
    }
    fz_always(ctx) {
        fz_drop_page(ctx, page);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Drop pixmap
void mino_drop_pixmap(fz_context *ctx, fz_pixmap *pix) {
    if (ctx && pix) {
        fz_drop_pixmap(ctx, pix);
    }
}

// Pixmap data accessors
int mino_pixmap_width(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) return 0;
    return fz_pixmap_width(ctx, pix);
}

int mino_pixmap_height(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) return 0;
    return fz_pixmap_height(ctx, pix);
}

unsigned char* mino_pixmap_samples(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) return NULL;
    return fz_pixmap_samples(ctx, pix);
}

int mino_pixmap_stride(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) return 0;
    return fz_pixmap_stride(ctx, pix);
}
