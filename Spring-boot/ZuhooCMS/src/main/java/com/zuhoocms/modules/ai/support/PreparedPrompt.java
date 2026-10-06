package com.zuhoocms.modules.ai.support;

/** A prompt plus whatever else was assembled in the same loading transaction, usually a DTO that must be mapped while its entity is still attached; returned as one from {@link AiTransactionBoundary#load}. */
public record PreparedPrompt<T>(T payload, String prompt) {}
