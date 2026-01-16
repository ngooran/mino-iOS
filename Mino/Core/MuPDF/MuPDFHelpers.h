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

#ifdef __cplusplus
}
#endif

#endif /* MuPDFHelpers_h */
