-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 011: Seed reference data
--
-- Seeds:
--   * Yemen as a country (stable code YE).
--   * 18 body systems with stable codes, English names, and Arabic names
--     where reliable translations are available.
--
-- Idempotent: uses INSERT ... ON CONFLICT (code) DO NOTHING so re-running
-- does not create duplicates.
--
-- No invented therapeutic classes, drug products, manufacturers, suppliers,
-- or scientific references are seeded.
-- Depends on: 002_geography_and_classification.sql.

-- ========================================================================
-- Yemen as a country (ISO 3166-1 alpha-2: YE)
-- ========================================================================
INSERT INTO public.countries (code, name_en, name_ar, is_yemen)
VALUES ('YE', 'Yemen', 'اليمن', TRUE)
ON CONFLICT (code) DO NOTHING;

-- ========================================================================
-- 18 Body Systems
-- Codes are stable and must not change. Arabic names use reliable
-- translations; where no reliable Arabic translation exists, name_ar
-- is left NULL (missing translations are allowed).
-- ========================================================================
INSERT INTO public.body_systems (code, name_en, name_ar, description_en, description_ar, sort_order, is_active) VALUES
    ('NERVOUS_SYSTEM',           'Nervous System',            'الجهاز العصبي',           NULL, NULL, 1, TRUE),
    ('CARDIOVASCULAR_SYSTEM',    'Cardiovascular System',     'الجهاز الدوري',          NULL, NULL, 2, TRUE),
    ('BLOOD_HEMATOPOIETIC',      'Blood and Hematopoietic System', 'الدم وجهاز التكون الدموي', NULL, NULL, 3, TRUE),
    ('RESPIRATORY_SYSTEM',       'Respiratory System',        'الجهاز التنفسي',         NULL, NULL, 4, TRUE),
    ('GASTROINTESTINAL_SYSTEM',  'Gastrointestinal System',   'الجهاز الهضمي',          NULL, NULL, 5, TRUE),
    ('HEPATOBILIARY_SYSTEM',     'Hepatobiliary System',      'الجهاز الكبدي الصفراوي',NULL, NULL, 6, TRUE),
    ('ENDOCRINE_SYSTEM',         'Endocrine System',          'الجهاز الغدد الصماء',     NULL, NULL, 7, TRUE),
    ('RENAL_URINARY_SYSTEM',     'Renal and Urinary System',  'الجهاز البولي والتناسلي',NULL, NULL, 8, TRUE),
    ('REPRODUCTIVE_SYSTEM',      'Reproductive System',       'الجهاز التناسلي',        NULL, NULL, 9, TRUE),
    ('MUSCULOSKELETAL_SYSTEM',   'Musculoskeletal System',    'الجهاز العضلي الهيكلي',  NULL, NULL, 10, TRUE),
    ('SKIN_SYSTEM',              'Skin System',               'الجهاز الجلدي',          NULL, NULL, 11, TRUE),
    ('EYE',                      'Eye',                       'العين',                   NULL, NULL, 12, TRUE),
    ('ENT',                      'Ear, Nose, and Throat',     'الأذن والأنف والحنجرة',  NULL, NULL, 13, TRUE),
    ('IMMUNE_SYSTEM',            'Immune System',             'الجهاز المناعي',         NULL, NULL, 14, TRUE),
    ('ANTI-INFECTIVE_SYSTEM',    'Anti-infective System',     'مكافحة العدوى',          NULL, NULL, 15, TRUE),
    ('ONCOLOGY',                 'Oncology',                  'الأورام',                 NULL, NULL, 16, TRUE),
    ('EMERGENCY_TOXICOLOGY',     'Emergency and Toxicology',  'الطوارئ والسموم',        NULL, NULL, 17, TRUE),
    ('DIAGNOSTIC_MISCELLANEOUS', 'Diagnostic and Miscellaneous', 'التشخيص ومتنوع',      NULL, NULL, 18, TRUE)
ON CONFLICT (code) DO NOTHING;

-- Ensure Yemen is flagged even if the row already existed without the flag.
UPDATE public.countries
SET is_yemen = TRUE
WHERE code = 'YE';
