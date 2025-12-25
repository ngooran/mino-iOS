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

// Error handling
const char* mino_get_last_error(void);
void mino_clear_error(void);

#ifdef __cplusplus
}
#endif

#endif /* MuPDFHelpers_h */
