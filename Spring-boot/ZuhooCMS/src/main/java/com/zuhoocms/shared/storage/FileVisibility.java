package com.zuhoocms.shared.storage;

/** PUBLIC files are served to anyone at /api/public/files/{id}; PRIVATE ones need auth or a signature. */
public enum FileVisibility {
    PUBLIC,
    PRIVATE
}
