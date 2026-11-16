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

// MARK: - PDF Merge/Split Operations

// Create a new empty PDF document
pdf_document* mino_create_pdf_document(fz_context *ctx) {
    if (!ctx) {
        set_error("Invalid context");
        return NULL;
    }

    mino_clear_error();
    pdf_document *doc = NULL;

    fz_try(ctx) {
        doc = pdf_create_document(ctx);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return NULL;
    }

    return doc;
}

// Drop/close a PDF document
void mino_drop_pdf_document(fz_context *ctx, pdf_document *doc) {
    if (ctx && doc) {
        pdf_drop_document(ctx, doc);
    }
}

// Create a graft map for efficient multi-page copying
pdf_graft_map* mino_new_graft_map(fz_context *ctx, pdf_document *dst) {
    if (!ctx || !dst) {
        set_error("Invalid context or destination document");
        return NULL;
    }

    mino_clear_error();
    pdf_graft_map *map = NULL;

    fz_try(ctx) {
        map = pdf_new_graft_map(ctx, dst);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return NULL;
    }

    return map;
}

// Drop/free a graft map
void mino_drop_graft_map(fz_context *ctx, pdf_graft_map *map) {
    if (ctx && map) {
        pdf_drop_graft_map(ctx, map);
    }
}

// Graft (copy) a page from source to destination document
int mino_graft_page(
    fz_context *ctx,
    pdf_graft_map *map,
    int page_to,
    pdf_document *src,
    int page_from
) {
    if (!ctx || !map || !src) {
        set_error("Invalid parameters for page graft");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        pdf_graft_mapped_page(ctx, map, page_to, src, page_from);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Delete a single page from a PDF document
int mino_delete_page(fz_context *ctx, pdf_document *doc, int page) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        pdf_delete_page(ctx, doc, page);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Delete a range of pages from a PDF document
int mino_delete_page_range(fz_context *ctx, pdf_document *doc, int start, int end) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }

    if (start < 0 || end < start) {
        set_error("Invalid page range");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        pdf_delete_page_range(ctx, doc, start, end);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Save a PDF document to file (without image recompression)
int mino_save_pdf(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    int garbage_level
) {
    if (!ctx || !doc || !output_path) {
        set_error("Invalid parameters for save");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        pdf_write_options opts = pdf_default_write_options;
        opts.do_garbage = garbage_level;
        opts.do_compress = 1;
        opts.do_compress_images = 0;  // Don't recompress images
        opts.do_compress_fonts = 1;
        opts.do_clean = 1;
        opts.do_sanitize = 0;
        opts.do_linear = 0;
        opts.do_appearance = 0;

        pdf_save_document(ctx, doc, output_path, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Save a PDF document without cleaning or rewriting content streams
int mino_save_pdf_untouched(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    int garbage_level
) {
    if (!ctx || !doc || !output_path) {
        set_error("Invalid parameters for save");
        return -1;
    }

    mino_clear_error();

    fz_try(ctx) {
        pdf_write_options opts = pdf_default_write_options;
        opts.do_garbage = garbage_level;
        opts.do_compress = 1;
        opts.do_compress_images = 0;
        opts.do_compress_fonts = 1;
        opts.do_clean = 0;
        opts.do_sanitize = 0;
        opts.do_linear = 0;
        opts.do_appearance = 0;

        pdf_save_document(ctx, doc, output_path, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return 0;
}

// Get page count from a pdf_document
int mino_pdf_count_pages(fz_context *ctx, pdf_document *doc) {
    if (!ctx || !doc) {
        return -1;
    }

    int count = 0;
    fz_try(ctx) {
        count = pdf_count_pages(ctx, doc);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }

    return count;
}

// MARK: - Passwords and encryption

int mino_needs_password(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int needs = 0;
    fz_try(ctx) {
        needs = fz_needs_password(ctx, doc);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return 0;
    }
    return needs;
}

int mino_authenticate(fz_context *ctx, fz_document *doc, const char *password) {
    if (!ctx || !doc) return 0;
    int result = 0;
    fz_try(ctx) {
        result = fz_authenticate_password(ctx, doc, password ? password : "");
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return 0;
    }
    return result;
}

int mino_is_encrypted(fz_context *ctx, pdf_document *doc) {
    if (!ctx || !doc) return 0;
    int encrypted = 0;
    fz_try(ctx) {
        encrypted = pdf_dict_get(ctx, pdf_trailer(ctx, doc), PDF_NAME(Encrypt)) != NULL;
    }
    fz_catch(ctx) {
        return 0;
    }
    return encrypted;
}

int mino_save_decrypted(fz_context *ctx, pdf_document *doc, const char *output_path) {
    if (!ctx || !doc || !output_path) {
        set_error("Invalid parameters for save");
        return -1;
    }
    mino_clear_error();
    fz_try(ctx) {
        pdf_write_options opts = pdf_default_write_options;
        opts.do_garbage = 1;
        opts.do_compress = 1;
        opts.do_compress_fonts = 1;
        opts.do_encrypt = PDF_ENCRYPT_NONE;
        pdf_save_document(ctx, doc, output_path, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

int mino_save_encrypted(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    const char *user_password,
    const char *owner_password,
    int permissions
) {
    if (!ctx || !doc || !output_path || !user_password || !owner_password) {
        set_error("Invalid parameters for save");
        return -1;
    }
    if (strlen(user_password) >= 128 || strlen(owner_password) >= 128) {
        set_error("The password is too long");
        return -1;
    }
    mino_clear_error();
    fz_try(ctx) {
        pdf_write_options opts = pdf_default_write_options;
        opts.do_garbage = 1;
        opts.do_compress = 1;
        opts.do_compress_fonts = 1;
        opts.do_encrypt = PDF_ENCRYPT_AES_256;
        opts.permissions = permissions;
        strncpy(opts.upwd_utf8, user_password, sizeof(opts.upwd_utf8) - 1);
        strncpy(opts.opwd_utf8, owner_password, sizeof(opts.opwd_utf8) - 1);
        pdf_save_document(ctx, doc, output_path, &opts);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

// MARK: - Building pages

// Maps the unit square of a stored image to the unit square of the upright
// image, for each EXIF orientation.
static fz_matrix orientation_matrix(int orientation) {
    switch (orientation) {
        case 2: return fz_make_matrix(-1, 0, 0, 1, 1, 0);
        case 3: return fz_make_matrix(-1, 0, 0, -1, 1, 1);
        case 4: return fz_make_matrix(1, 0, 0, -1, 0, 1);
        case 5: return fz_make_matrix(0, -1, -1, 0, 1, 1);
        case 6: return fz_make_matrix(0, -1, 1, 0, 0, 1);
        case 7: return fz_make_matrix(0, 1, 1, 0, 0, 0);
        case 8: return fz_make_matrix(0, 1, -1, 0, 1, 0);
        default: return fz_identity;
    }
}

int mino_add_image_page(
    fz_context *ctx,
    pdf_document *doc,
    const char *image_path,
    float page_w,
    float page_h,
    float x,
    float y,
    float w,
    float h,
    int orientation
) {
    if (!ctx || !doc || !image_path || page_w <= 0 || page_h <= 0) {
        set_error("Invalid parameters for image page");
        return -1;
    }
    mino_clear_error();

    fz_image *image = NULL;
    pdf_obj *image_ref = NULL;
    pdf_obj *resources = NULL;
    pdf_obj *page = NULL;
    fz_buffer *contents = NULL;

    fz_var(image);
    fz_var(image_ref);
    fz_var(resources);
    fz_var(page);
    fz_var(contents);

    fz_try(ctx) {
        image = fz_new_image_from_file(ctx, image_path);
        image_ref = pdf_add_image(ctx, doc, image);

        resources = pdf_new_dict(ctx, doc, 1);
        pdf_obj *xobjects = pdf_dict_put_dict(ctx, resources, PDF_NAME(XObject), 1);
        pdf_dict_puts(ctx, xobjects, "Im0", image_ref);

        // Orientation first, then scale and move into the target rectangle.
        fz_matrix m = fz_concat(orientation_matrix(orientation), fz_make_matrix(w, 0, 0, h, x, y));
        contents = fz_new_buffer(ctx, 128);
        fz_append_printf(ctx, contents, "q %g %g %g %g %g %g cm /Im0 Do Q\n", m.a, m.b, m.c, m.d, m.e, m.f);

        fz_rect mediabox = fz_make_rect(0, 0, page_w, page_h);
        page = pdf_add_page(ctx, doc, mediabox, 0, resources, contents);
        pdf_insert_page(ctx, doc, -1, page);
    }
    fz_always(ctx) {
        fz_drop_image(ctx, image);
        pdf_drop_obj(ctx, image_ref);
        pdf_drop_obj(ctx, resources);
        pdf_drop_obj(ctx, page);
        fz_drop_buffer(ctx, contents);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

int mino_add_blank_page(fz_context *ctx, pdf_document *doc, float width, float height) {
    if (!ctx || !doc || width <= 0 || height <= 0) {
        set_error("Invalid parameters for blank page");
        return -1;
    }
    mino_clear_error();

    pdf_obj *resources = NULL;
    pdf_obj *page = NULL;
    fz_buffer *contents = NULL;

    fz_var(resources);
    fz_var(page);
    fz_var(contents);

    fz_try(ctx) {
        resources = pdf_new_dict(ctx, doc, 1);
        contents = fz_new_buffer(ctx, 8);
        fz_append_string(ctx, contents, "\n");
        page = pdf_add_page(ctx, doc, fz_make_rect(0, 0, width, height), 0, resources, contents);
        pdf_insert_page(ctx, doc, -1, page);
    }
    fz_always(ctx) {
        pdf_drop_obj(ctx, resources);
        pdf_drop_obj(ctx, page);
        fz_drop_buffer(ctx, contents);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

int mino_duplicate_page(fz_context *ctx, pdf_document *doc, int page) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }
    mino_clear_error();

    pdf_obj *copy = NULL;
    pdf_obj *ref = NULL;

    fz_var(copy);
    fz_var(ref);

    fz_try(ctx) {
        // Only keys that do not point at other pages. The content and
        // resources are shared with the original, so the file barely grows.
        pdf_obj *keys[] = {
            PDF_NAME(Contents), PDF_NAME(Resources), PDF_NAME(MediaBox), PDF_NAME(CropBox),
            PDF_NAME(BleedBox), PDF_NAME(TrimBox), PDF_NAME(ArtBox), PDF_NAME(Rotate), PDF_NAME(UserUnit)
        };
        pdf_obj *source = pdf_lookup_page_obj(ctx, doc, page);
        copy = pdf_new_dict(ctx, doc, 8);
        pdf_dict_put(ctx, copy, PDF_NAME(Type), PDF_NAME(Page));
        for (int i = 0; i < (int)(sizeof(keys) / sizeof(keys[0])); i++) {
            pdf_obj *value = pdf_dict_get_inheritable(ctx, source, keys[i]);
            if (value) pdf_dict_put(ctx, copy, keys[i], value);
        }
        ref = pdf_add_object(ctx, doc, copy);
        pdf_insert_page(ctx, doc, -1, ref);
    }
    fz_always(ctx) {
        pdf_drop_obj(ctx, copy);
        pdf_drop_obj(ctx, ref);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

// MARK: - Organizing pages

// Returns 1 when `num` is one of the widget object numbers on a kept page.
static int is_kept_widget(int num, const int *widgets, int widget_count) {
    for (int i = 0; i < widget_count; i++) {
        if (widgets[i] == num) return 1;
    }
    return 0;
}

// Removes form fields whose widgets are all gone. Returns 1 when the field stays.
static int prune_field(fz_context *ctx, pdf_obj *field, const int *widgets, int widget_count, int depth) {
    if (depth > 32) return 0;
    pdf_obj *kids = pdf_dict_get(ctx, field, PDF_NAME(Kids));
    if (pdf_is_array(ctx, kids) && pdf_array_len(ctx, kids) > 0) {
        for (int i = pdf_array_len(ctx, kids) - 1; i >= 0; i--) {
            if (!prune_field(ctx, pdf_array_get(ctx, kids, i), widgets, widget_count, depth + 1)) {
                pdf_array_delete(ctx, kids, i);
            }
        }
        return pdf_array_len(ctx, kids) > 0;
    }
    return is_kept_widget(pdf_to_num(ctx, field), widgets, widget_count);
}

int mino_rearrange_pages(fz_context *ctx, pdf_document *doc, int count, const int *pages) {
    if (!ctx || !doc || !pages || count <= 0) {
        set_error("Invalid parameters for rearranging pages");
        return -1;
    }
    mino_clear_error();

    pdf_obj *acroform = NULL;
    pdf_obj *metadata = NULL;
    pdf_obj *lang = NULL;
    int *widgets = NULL;

    fz_var(acroform);
    fz_var(metadata);
    fz_var(lang);
    fz_var(widgets);

    fz_try(ctx) {
        // pdf_rearrange_pages rebuilds the catalog and leaves these out.
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, doc), PDF_NAME(Root));
        acroform = pdf_keep_obj(ctx, pdf_dict_get(ctx, root, PDF_NAME(AcroForm)));
        metadata = pdf_keep_obj(ctx, pdf_dict_get(ctx, root, PDF_NAME(Metadata)));
        lang = pdf_keep_obj(ctx, pdf_dict_get(ctx, root, PDF_NAME(Lang)));

        pdf_rearrange_pages(ctx, doc, count, pages, PDF_CLEAN_STRUCTURE_DROP);

        root = pdf_dict_get(ctx, pdf_trailer(ctx, doc), PDF_NAME(Root));
        if (metadata) pdf_dict_put(ctx, root, PDF_NAME(Metadata), metadata);
        if (lang) pdf_dict_put(ctx, root, PDF_NAME(Lang), lang);

        if (acroform) {
            // Collect the widgets that are still on a page.
            int page_count = pdf_count_pages(ctx, doc);
            int capacity = 64;
            int widget_count = 0;
            widgets = fz_malloc(ctx, capacity * sizeof(int));
            for (int i = 0; i < page_count; i++) {
                pdf_obj *annots = pdf_dict_get(ctx, pdf_lookup_page_obj(ctx, doc, i), PDF_NAME(Annots));
                int len = pdf_array_len(ctx, annots);
                for (int j = 0; j < len; j++) {
                    pdf_obj *annot = pdf_array_get(ctx, annots, j);
                    if (!pdf_name_eq(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Subtype)), PDF_NAME(Widget))) continue;
                    if (widget_count == capacity) {
                        capacity *= 2;
                        widgets = fz_realloc(ctx, widgets, capacity * sizeof(int));
                    }
                    widgets[widget_count++] = pdf_to_num(ctx, annot);
                }
            }

            pdf_obj *fields = pdf_dict_get(ctx, acroform, PDF_NAME(Fields));
            for (int i = pdf_array_len(ctx, fields) - 1; i >= 0; i--) {
                if (!prune_field(ctx, pdf_array_get(ctx, fields, i), widgets, widget_count, 0)) {
                    pdf_array_delete(ctx, fields, i);
                }
            }
            if (pdf_array_len(ctx, fields) > 0) {
                pdf_dict_put(ctx, root, PDF_NAME(AcroForm), acroform);
            }
        }
    }
    fz_always(ctx) {
        pdf_drop_obj(ctx, acroform);
        pdf_drop_obj(ctx, metadata);
        pdf_drop_obj(ctx, lang);
        fz_free(ctx, widgets);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

int mino_get_page_rotation(fz_context *ctx, pdf_document *doc, int page) {
    if (!ctx || !doc) return 0;
    int rotation = 0;
    fz_try(ctx) {
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, doc, page);
        rotation = pdf_to_int(ctx, pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(Rotate)));
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return 0;
    }
    rotation %= 360;
    if (rotation < 0) rotation += 360;
    return rotation;
}

int mino_set_page_rotation(fz_context *ctx, pdf_document *doc, int page, int rotation) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }
    mino_clear_error();
    rotation %= 360;
    if (rotation < 0) rotation += 360;
    fz_try(ctx) {
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, doc, page);
        pdf_dict_put_int(ctx, page_obj, PDF_NAME(Rotate), rotation);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

// MARK: - Overlays

// Puts page `src_index` of `overlay` on top of page `dst_index` of `doc`.
static void overlay_one_page(
    fz_context *ctx,
    pdf_document *doc,
    pdf_graft_map *map,
    pdf_document *overlay,
    int src_index,
    int dst_index,
    int serial
) {
    fz_buffer *content = NULL;
    fz_buffer *part = NULL;
    fz_buffer *head = NULL;
    fz_buffer *tail = NULL;
    pdf_obj *resources = NULL;
    pdf_obj *xobject = NULL;
    pdf_obj *head_ref = NULL;
    pdf_obj *tail_ref = NULL;
    pdf_obj *contents = NULL;
    pdf_obj *copied_resources = NULL;

    fz_var(content);
    fz_var(part);
    fz_var(head);
    fz_var(tail);
    fz_var(resources);
    fz_var(xobject);
    fz_var(head_ref);
    fz_var(tail_ref);
    fz_var(contents);
    fz_var(copied_resources);

    fz_try(ctx) {
        // The overlay page becomes a Form XObject in the document.
        pdf_obj *src_page = pdf_lookup_page_obj(ctx, overlay, src_index);
        pdf_obj *src_contents = pdf_dict_get(ctx, src_page, PDF_NAME(Contents));
        if (pdf_is_array(ctx, src_contents)) {
            content = fz_new_buffer(ctx, 1024);
            int parts = pdf_array_len(ctx, src_contents);
            for (int i = 0; i < parts; i++) {
                part = pdf_load_stream(ctx, pdf_array_get(ctx, src_contents, i));
                fz_append_buffer(ctx, content, part);
                fz_append_byte(ctx, content, '\n');
                fz_drop_buffer(ctx, part);
                part = NULL;
            }
        } else if (src_contents) {
            content = pdf_load_stream(ctx, src_contents);
        } else {
            content = fz_new_buffer(ctx, 1);
        }

        fz_rect bbox = pdf_dict_get_inheritable_rect(ctx, src_page, PDF_NAME(MediaBox));
        pdf_obj *src_resources = pdf_dict_get_inheritable(ctx, src_page, PDF_NAME(Resources));
        if (src_resources) {
            resources = pdf_graft_mapped_object(ctx, map, src_resources);
        } else {
            resources = pdf_new_dict(ctx, doc, 1);
        }
        xobject = pdf_new_xobject(ctx, doc, bbox, fz_identity, resources, content);

        // The page needs a resource dictionary of its own to name the XObject in.
        pdf_obj *page = pdf_lookup_page_obj(ctx, doc, dst_index);
        pdf_obj *page_resources = pdf_dict_get(ctx, page, PDF_NAME(Resources));
        if (!page_resources) {
            pdf_obj *inherited = pdf_dict_get_inheritable(ctx, page, PDF_NAME(Resources));
            copied_resources = inherited ? pdf_copy_dict(ctx, inherited) : pdf_new_dict(ctx, doc, 2);
            pdf_dict_put(ctx, page, PDF_NAME(Resources), copied_resources);
            page_resources = pdf_dict_get(ctx, page, PDF_NAME(Resources));
        }
        pdf_obj *xobjects = pdf_dict_get(ctx, page_resources, PDF_NAME(XObject));
        if (!xobjects) {
            xobjects = pdf_dict_put_dict(ctx, page_resources, PDF_NAME(XObject), 2);
        }
        char name[32];
        snprintf(name, sizeof(name), "MinoL%d", serial);
        while (pdf_dict_gets(ctx, xobjects, name)) {
            serial += 1000;
            snprintf(name, sizeof(name), "MinoL%d", serial);
        }
        pdf_dict_puts(ctx, xobjects, name, xobject);

        // Overlay coordinates (origin bottom left, y up) -> the page as it is
        // shown (origin top left, y down) -> the page's own coordinates.
        fz_rect page_box;
        fz_matrix page_ctm;
        pdf_page_obj_transform(ctx, page, &page_box, &page_ctm);
        fz_rect shown = fz_transform_rect(page_box, page_ctm);
        float shown_w = shown.x1 - shown.x0;
        float shown_h = shown.y1 - shown.y0;
        float overlay_w = bbox.x1 - bbox.x0;
        float overlay_h = bbox.y1 - bbox.y0;
        if (overlay_w <= 0 || overlay_h <= 0) {
            fz_throw(ctx, FZ_ERROR_ARGUMENT, "overlay page has no size");
        }
        fz_matrix m = fz_translate(-bbox.x0, -bbox.y0);
        m = fz_concat(m, fz_scale(shown_w / overlay_w, shown_h / overlay_h));
        m = fz_concat(m, fz_make_matrix(1, 0, 0, -1, shown.x0, shown.y0 + shown_h));
        m = fz_concat(m, fz_invert_matrix(page_ctm));

        // Wrap what is there in q ... Q, so its graphics state can't leak into the overlay.
        head = fz_new_buffer(ctx, 8);
        fz_append_string(ctx, head, "q\n");
        tail = fz_new_buffer(ctx, 128);
        fz_append_printf(ctx, tail, "\nQ\nq %g %g %g %g %g %g cm /%s Do Q\n", m.a, m.b, m.c, m.d, m.e, m.f, name);
        head_ref = pdf_add_stream(ctx, doc, head, NULL, 0);
        tail_ref = pdf_add_stream(ctx, doc, tail, NULL, 0);

        contents = pdf_new_array(ctx, doc, 4);
        pdf_array_push(ctx, contents, head_ref);
        pdf_obj *old = pdf_dict_get(ctx, page, PDF_NAME(Contents));
        if (pdf_is_array(ctx, old)) {
            int len = pdf_array_len(ctx, old);
            for (int i = 0; i < len; i++) {
                pdf_array_push(ctx, contents, pdf_array_get(ctx, old, i));
            }
        } else if (old) {
            pdf_array_push(ctx, contents, old);
        }
        pdf_array_push(ctx, contents, tail_ref);
        pdf_dict_put(ctx, page, PDF_NAME(Contents), contents);
    }
    fz_always(ctx) {
        fz_drop_buffer(ctx, content);
        fz_drop_buffer(ctx, part);
        fz_drop_buffer(ctx, head);
        fz_drop_buffer(ctx, tail);
        pdf_drop_obj(ctx, resources);
        pdf_drop_obj(ctx, xobject);
        pdf_drop_obj(ctx, head_ref);
        pdf_drop_obj(ctx, tail_ref);
        pdf_drop_obj(ctx, contents);
        pdf_drop_obj(ctx, copied_resources);
    }
    fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

int mino_overlay_pages(
    fz_context *ctx,
    pdf_document *doc,
    const char *overlay_path,
    int count,
    const int *target_pages
) {
    if (!ctx || !doc || !overlay_path || !target_pages || count < 0) {
        set_error("Invalid parameters for overlay");
        return -1;
    }
    mino_clear_error();

    fz_document *overlay_doc = NULL;
    pdf_graft_map *map = NULL;

    fz_var(overlay_doc);
    fz_var(map);

    fz_try(ctx) {
        overlay_doc = fz_open_document(ctx, overlay_path);
        pdf_document *overlay = pdf_specifics(ctx, overlay_doc);
        if (!overlay) {
            fz_throw(ctx, FZ_ERROR_ARGUMENT, "overlay is not a PDF");
        }
        map = pdf_new_graft_map(ctx, doc);
        int available = pdf_count_pages(ctx, overlay);
        int page_count = pdf_count_pages(ctx, doc);
        for (int i = 0; i < count && i < available; i++) {
            if (target_pages[i] < 0 || target_pages[i] >= page_count) {
                fz_throw(ctx, FZ_ERROR_ARGUMENT, "overlay target page out of range");
            }
            overlay_one_page(ctx, doc, map, overlay, i, target_pages[i], i);
        }
    }
    fz_always(ctx) {
        pdf_drop_graft_map(ctx, map);
        fz_drop_document(ctx, overlay_doc);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}

// MARK: - Flattening

int mino_bake(fz_context *ctx, pdf_document *doc, int bake_annotations, int bake_widgets) {
    if (!ctx || !doc) {
        set_error("Invalid context or document");
        return -1;
    }
    mino_clear_error();
    fz_try(ctx) {
        pdf_bake_document(ctx, doc, bake_annotations, bake_widgets);
    }
    fz_catch(ctx) {
        set_error(fz_caught_message(ctx));
        return -1;
    }
    return 0;
}
