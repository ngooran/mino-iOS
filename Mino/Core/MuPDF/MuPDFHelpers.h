//
//  MuPDFHelpers.h
//  Mino
//
//  C helper functions for MuPDF Swift integration
//

#ifndef MuPDFHelpers_h
#define MuPDFHelpers_h

#include <stdint.h>
#include "mupdf/fitz.h"
#include "mupdf/pdf.h"

#ifdef __cplusplus
extern "C" {
#endif

// Context management
fz_context* mino_create_context(void);
void mino_drop_context(fz_context *ctx);

// Document operations
fz_document* mino_open_document(fz_context *ctx, const char *path);
void mino_drop_document(fz_context *ctx, fz_document *doc);
int mino_count_pages(fz_context *ctx, fz_document *doc);
pdf_document* mino_pdf_specifics(fz_context *ctx, fz_document *doc);

// Compression operations
int mino_compress_pdf(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    int jpeg_quality,
    int target_dpi,
    int garbage_level
);

// Image rewriting
int mino_rewrite_images(
    fz_context *ctx,
    pdf_document *doc,
    int jpeg_quality,
    int target_dpi,
    int dpi_threshold
);

// File utilities
int64_t mino_get_file_size(const char *path);

// Page rendering
fz_pixmap* mino_render_page(
    fz_context *ctx,
    fz_document *doc,
    int page_number,
    float zoom
);

int mino_get_page_size(
    fz_context *ctx,
    fz_document *doc,
    int page_number,
    float *width,
    float *height
);

void mino_drop_pixmap(fz_context *ctx, fz_pixmap *pix);

// Pixmap data access
int mino_pixmap_width(fz_context *ctx, fz_pixmap *pix);
int mino_pixmap_height(fz_context *ctx, fz_pixmap *pix);
unsigned char* mino_pixmap_samples(fz_context *ctx, fz_pixmap *pix);
int mino_pixmap_stride(fz_context *ctx, fz_pixmap *pix);

// Error handling
const char* mino_get_last_error(void);
void mino_clear_error(void);

// MARK: - PDF Merge/Split Operations

// Create a new empty PDF document
pdf_document* mino_create_pdf_document(fz_context *ctx);

// Drop/close a PDF document (not the generic fz_document)
void mino_drop_pdf_document(fz_context *ctx, pdf_document *doc);

// Create a graft map for efficient multi-page copying
pdf_graft_map* mino_new_graft_map(fz_context *ctx, pdf_document *dst);

// Drop/free a graft map
void mino_drop_graft_map(fz_context *ctx, pdf_graft_map *map);

// Graft (copy) a page from source to destination document
// page_to: destination page index (-1 to append at end)
// page_from: source page index (0-based)
// Returns 0 on success, -1 on error
int mino_graft_page(
    fz_context *ctx,
    pdf_graft_map *map,
    int page_to,
    pdf_document *src,
    int page_from
);

// Delete a single page from a PDF document
// page: 0-based page index
// Returns 0 on success, -1 on error
int mino_delete_page(fz_context *ctx, pdf_document *doc, int page);

// Delete a range of pages from a PDF document
// start: first page to delete (0-based, inclusive)
// end: last page to delete (0-based, exclusive)
// Returns 0 on success, -1 on error
int mino_delete_page_range(fz_context *ctx, pdf_document *doc, int start, int end);

// Save a PDF document to file (without image recompression)
// garbage_level: 0-4 for garbage collection level
// Returns 0 on success, -1 on error
int mino_save_pdf(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    int garbage_level
);

// Get page count from a pdf_document (not fz_document)
int mino_pdf_count_pages(fz_context *ctx, pdf_document *doc);


// MARK: - Passwords and encryption

// Returns 1 when the document needs a password before it can be read.
int mino_needs_password(fz_context *ctx, fz_document *doc);

// Tries a password. Returns 0 when it is wrong; otherwise MuPDF's result bits:
// 1 = no password needed, 2 = user password accepted, 4 = owner password accepted.
int mino_authenticate(fz_context *ctx, fz_document *doc, const char *password);

// Returns 1 when the document is encrypted (with or without an open password).
int mino_is_encrypted(fz_context *ctx, pdf_document *doc);

// Saves a copy without encryption. The document must be authenticated first.
int mino_save_decrypted(fz_context *ctx, pdf_document *doc, const char *output_path);

// Saves a copy encrypted with AES-256.
// permissions: MuPDF PDF_PERM_* bits that stay allowed.
int mino_save_encrypted(
    fz_context *ctx,
    pdf_document *doc,
    const char *output_path,
    const char *user_password,
    const char *owner_password,
    int permissions
);

// MARK: - Building pages

// Appends a page of page_w x page_h points showing the image file, placed in
// the rectangle (x, y, w, h) with y measured from the bottom of the page.
// JPEG data is embedded as it is. orientation is the EXIF value 1-8.
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
);

// Appends an empty page.
int mino_add_blank_page(fz_context *ctx, pdf_document *doc, float width, float height);

// Appends a copy of a page (0-based) that shares the original's content.
// The copy has no annotations, links or form fields.
int mino_duplicate_page(fz_context *ctx, pdf_document *doc, int page);

// MARK: - Organizing pages

// Keeps the listed pages (0-based, each at most once) in the given order and
// removes the others. Bookmarks, links and form fields that belong to the
// remaining pages are kept; those pointing at removed pages are dropped.
int mino_rearrange_pages(fz_context *ctx, pdf_document *doc, int count, const int *pages);

// Page rotation in degrees (0, 90, 180, 270), including inherited values.
int mino_get_page_rotation(fz_context *ctx, pdf_document *doc, int page);
int mino_set_page_rotation(fz_context *ctx, pdf_document *doc, int page, int rotation);

// MARK: - Overlays

// Draws pages of another PDF on top of pages of this document, as Form
// XObjects. Overlay page i goes onto page target_pages[i] (0-based) and is
// stretched to that page's visible size, whatever its rotation or crop box.
// The existing page content is not rewritten. Used for the invisible text
// layer of Recognize Text.
int mino_overlay_pages(
    fz_context *ctx,
    pdf_document *doc,
    const char *overlay_path,
    int count,
    const int *target_pages
);

// MARK: - Flattening

// Makes annotations and/or form fields part of the page content, so they
// can no longer be moved, edited or removed. Links are kept.
int mino_bake(fz_context *ctx, pdf_document *doc, int bake_annotations, int bake_widgets);

#ifdef __cplusplus
}
#endif

#endif /* MuPDFHelpers_h */
