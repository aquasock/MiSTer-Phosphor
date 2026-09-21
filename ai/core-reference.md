# CONTROLLED STANDARDS REFERENCE

> **Project:** MiSTer-Media-Player  
> **Purpose:** Fast, clause-level standards reference for the active MPEG-2 decoder, the released v0.7.0 ARM media pipeline, the approved native-interlaced milestone, and the adopted NARA MPD-D2 release media target.
> **Authority:** The cited controlled document always outranks this summary.

This file contains external rules and controlled external profiles, not project history or implementation advice. It is deliberately limited to sources that support the current H.262 decoder or approved work: native frame and field cadence, interlaced frame presentation, MPEG-2 Program Stream framing, PES parsing, PTS/DTS timing, ARM-side MPEG-1 Layer II audio decoding, and the NARA MPD-D2 profile adopted by the user as the release media target. Adoption makes that profile a project acceptance target; it does not turn it into the normative DVD-Video application specification.

---

## 1. AI operating rules

```yaml
schema_version: 3

authority_order:
  - exact_application_specification
  - formal_standard_or_recommendation
  - official_corrigendum_or_amendment
  - official_industry_specification
  - official_government_production_profile
  - official_vendor_or_platform_specification

never_primary_authority:
  - forum_post
  - wiki
  - blog
  - reverse_engineering_note
  - source_code_comment
  - AI_output

rules:
  - "Cite an exact clause, table, figure, annex, field, or page for every controlled conclusion."
  - "Keep one externally defined rule or tightly coupled rule set per record."
  - "Do not copy long passages from standards; store concise conclusions."
  - "Do not turn implementation choices, tests, resource use, or debugging history into standards claims."
  - "Re-open the source when an edition, application profile, edge case, or observed behavior changes."
  - "A newer generic standard does not silently replace an application-pinned edition."
  - "Treat a record verified against an older free edition as a baseline until its current-edition delta is checked."
```

---

## 2. Active source catalog

```yaml
- source_id: H262
  priority: P0
  authority: ITU-T / ISO/IEC
  document: "ITU-T H.262 — Generic coding of moving pictures and associated audio information: Video"
  equivalent: "ISO/IEC 13818-2:2013"
  current_edition: "ITU-T H.262 (02/2012), including Amendment 1 (03/2013)"
  current_url: "https://www.itu.int/rec/T-REC-H.262"
  consulted_baseline: "ITU-T H.262 (02/2000), official freely available consolidated edition"
  consulted_url: "https://www.itu.int/rec/T-REC-H.262-200002-S/en"
  use_for:
    - "MPEG-2 video syntax and decode semantics"
    - "I, P and B picture reconstruction and presentation"
    - "motion compensation, residuals, slices and macroblocks"
    - "frame-rate signalling and cadence"

- source_id: H222
  priority: P0
  authority: ITU-T / ISO/IEC
  document: "ITU-T H.222.0 — Generic coding of moving pictures and associated audio information: Systems"
  equivalent: "ISO/IEC 13818-1:2025"
  current_edition: "ITU-T H.222.0 (04/2025), v10"
  current_access: PAID
  current_url: "https://www.itu.int/rec/T-REC-H.222.0-202504-I"
  consulted_baseline: "ITU-T H.222.0 (06/2021), v8, official freely available edition"
  consulted_url: "https://www.itu.int/rec/T-REC-H.222.0-202106-S/en"
  current_delta_status: "Recheck before claiming conformance to the 2025 edition."
  use_for:
    - "MPEG-2 Program Stream packs and termination"
    - "system headers, PES packets and stream identifiers"
    - "SCR, PTS, DTS and 90 kHz presentation timing"
    - "program stream maps"

- source_id: MPEG1-AUDIO
  priority: P0
  authority: ISO/IEC
  document: "ISO/IEC 11172-3:1993 — Coding of moving pictures and associated audio for digital storage media at up to about 1,5 Mbit/s — Part 3: Audio"
  current_edition: "Edition 1, 1993, with Technical Corrigendum 1:1996"
  status: "Published; current edition under systematic review"
  access: PAID
  official_url: "https://www.iso.org/standard/22412.html"
  use_for:
    - "MPEG-1 Audio Layer II frame syntax and decoding"
    - "sampling-frequency and bitrate signalling"
    - "ARM-side compressed-audio decoding for the first v0.7.0 embedded-audio profile"

- source_id: MPEG2-CONFORMANCE
  priority: P1
  authority: ISO/IEC
  document: "ISO/IEC 13818-4:2004 — Conformance testing"
  edition: "Edition 2, with applicable corrigenda"
  access: PAID
  official_url: "https://www.iso.org/standard/40092.html"
  use_for:
    - "formal coded-data and decoder conformance claims"
    - "future standardized test-sequence work"

- source_id: NARA-MPD-D2
  priority: P1
  authority: U.S. National Archives and Records Administration
  document: "DVD from Motion Picture Film Original [MPD-D2]"
  profile_status: "Official NARA distribution-copy product profile"
  page_reviewed_on: 2023-12-22
  consulted_on: 2026-08-29
  official_url: "https://www.archives.gov/preservation/products/products/mpd-d2"
  use_for:
    - "project release media target"
    - "720x480 29.97 interlaced top-field-first MPEG-2 Program Stream qualification"
    - "stereo 48 kHz AC-3 release-profile qualification"
```

The 2021 H.222.0 edition is the controlled text consulted for the records below. It is newer and more useful than the previously catalogued paywalled-only systems reference, but it does not eliminate the need to check the 2025 delta before a current-edition conformance claim.

---

## 3. Active routing

| Question | Consult first | Fast records |
|---|---|---|
| Native 23.976/24/25/29.97/30 cadence | H.262 sequence header | H262-027 |
| Native interlaced frame structure and field output | H.262 picture coding extension and output process | H262-028 through H262-035 |
| Program Stream pack boundaries and clean termination | H.222.0 2.5.3 | H222-001 through H222-003 |
| PES length, stream selection and optional headers | H.222.0 2.4.3.6–2.4.3.7 | H222-004 through H222-006 |
| Picture presentation timestamps and reorder timing | H.222.0 2.4.3.7 | H222-007 and H222-011 |
| SCR and clock-domain meaning | H.222.0 2.5.2 | H222-008 |
| Program Stream Map video identification | H.222.0 2.5.4 | H222-009 |
| PES payload alignment assumptions | H.222.0 2.4.3.7 | H222-010 |
| Existing video decode behavior | H.262 clauses and Annex B | H262-001 through H262-026 |
| MPEG-1 Layer II audio decode | ISO/IEC 11172-3 | Re-open the controlled text for every syntax-level conclusion |
| Adopted DVD-from-film release media profile | NARA MPD-D2 | NARA-001 |

### Explicitly deferred

The following are not active v0.7.0 reference scope and should be expanded only when their feature milestone is approved:

```yaml
- boundary: DVD_VIDEO
  required_sources: "Authorized DVD Format/Logo Licensing Corporation Part 2 and Part 3 books"
  note: "NARA MPD-D2 is the adopted release media target, but DVD navigation, menus, VOB application constraints and exact legacy profiles still cannot be inferred from NARA or generic MPEG."

- boundary: DVD_FILESYSTEM
  required_sources: "UDF 1.02 / ECMA-167 plus the applicable DVD profile; ECMA TR/71 and TR/112 as aids"

- boundary: CSS
  required_sources: "Authorized DVD CCA CSS material"
  note: "Do not substitute reverse-engineering notes for restricted normative material."

- boundary: AUDIO_AFTER_MPEG1_LAYER_II
  required_sources: "ISO/IEC 13818-3 for MPEG-2 audio extensions and ATSC A/52 for AC-3, constrained by the future application profile"
  note: "The approved first ARM-audio profile activates MPEG-1 Layer II only; AC-3 and MPEG-2 audio extensions remain deferred."

- boundary: TRANSPORT_STREAM
  required_sources: "H.222.0 transport-system clauses"
  note: "Transport Stream is not part of the approved Program Stream milestone."
```

---

## 4. Fast lookup index

```yaml
H262-001: "Decoded pel = clipped prediction + residual"
H262-002: "Reference frames and P-picture reference use"
H262-003: "Motion prediction source and vector addressing"
H262-004: "Half-sample interpolation"
H262-005: "Controlled implicit-zero P prediction"
H262-006: "4:2:0 block order"
H262-007: "Macroblock width"
H262-008: "Slice vertical position"
H262-009: "Macroblock address progression"
H262-010: "First non-intra coefficient VLC"
H262-011: "P motion-forward-only macroblock type"
H262-012: "motion_code zero VLC"
H262-013: "macroblock_address_increment one VLC"
H262-014: "Macroblock increment table and escape"
H262-015: "Skipped P-frame macroblocks"
H262-016: "Controlled f_code 3 vector +32"
H262-017: "4:2:0 chroma-vector scaling"
H262-018: "P motion+coded macroblock type"
H262-019: "coded_block_pattern 63"
H262-020: "Controlled non-intra level +7 and EOB"
H262-021: "4:2:0 coded-block selection"
H262-022: "General frame-motion vector reconstruction"
H262-023: "Chroma division and exact half-sample arithmetic"
H262-024: "Non-intra Escape coefficient"
H262-025: "Slice endpoints, start address and coverage"
H262-026: "B-picture intra macroblock types"
H262-027: "Frame-rate code and extension"
H262-028: "Interlaced sequences may contain frame pictures"
H262-029: "Interlaced-sequence frame-picture macroblock height"
H262-030: "Frame picture structure"
H262-031: "Authored first-field order"
H262-032: "Frame-DCT and frame-prediction subset"
H262-033: "Interlaced-frame repeat and 4:2:0 signalling"
H262-034: "Interlaced sequence field-period output"
H262-035: "Interlaced 4:2:0 sample organization"
H262-036: "Stream-defined quantization matrices"
H262-037: "Weighted inverse quantization"
H262-038: "Progressive film frame field duration"
H262-039: "Quantized non-intra B macroblock types"
H262-040: "Motion predictor reset after intra"
H222-001: "Program Stream framing and end code"
H222-002: "Pack header, SCR, mux rate and stuffing"
H222-003: "System-header framing and length"
H222-004: "PES framing and Program Stream length rule"
H222-005: "Relevant Program Stream stream_id values"
H222-006: "PES optional-header and timestamp flags"
H222-007: "PTS/DTS units, wrap and video association"
H222-008: "System clock and SCR representation"
H222-009: "Program Stream Map and MPEG-2 video type"
H222-010: "PES data-alignment indicator"
H222-011: "Decode-order and presentation-order timing"
NARA-001: "Adopted NARA MPD-D2 DVD-from-film release media profile"
```

---

## 5. Established H.262 records

All records in this section are `VERIFIED`, `HIGH` confidence, and apply to the decoder subset stated in the conclusion. The source edition is H.262 (02/2012) for H262-001 through H262-013 and the official H.262 (02/2000) consolidated edition for H262-014 through H262-027. The current edition remains the controlling source when a difference exists.

```yaml
- record_id: H262-001
  source_id: H262
  source_reference: "7.6.8"
  controlled_conclusion: "Reconstruct each decoded pel by adding residual f[y][x] to prediction p[y][x], then saturate to the inclusive 8-bit range 0..255."

- record_id: H262-002
  source_id: H262
  source_reference: "3.111; 7.6.2.2"
  controlled_conclusion: "A reference frame is a reconstructed I or P frame; P-frame prediction uses the applicable previously reconstructed reference frame."

- record_id: H262-003
  source_id: H262
  source_reference: "7.6.4"
  controlled_conclusion: "Motion-compensated prediction samples come from the applicable reference picture locations selected by the decoded motion vector and prediction rules."

- record_id: H262-004
  source_id: H262
  source_reference: "7.6.4"
  controlled_conclusion: "A half-sample motion component uses the specified neighboring reference samples and prescribed interpolation rounding."

- record_id: H262-005
  source_id: H262
  source_reference: "7.6.3.5"
  controlled_conclusion: "In the controlled non-intra P macroblock case with no transmitted forward vector, the implicit prediction behavior resolves to a zero vector and colocated reference prediction."

- record_id: H262-006
  source_id: H262
  source_reference: "6.1.3; Figure 6-10"
  controlled_conclusion: "A 4:2:0 macroblock contains six blocks in order Y0, Y1, Y2, Y3, Cb, Cr."

- record_id: H262-007
  source_id: H262
  source_reference: "6.3.3"
  controlled_conclusion: "Macroblock width is ceil(horizontal_size/16), equivalently (horizontal_size+15)/16 with integer division."

- record_id: H262-008
  source_id: H262
  source_reference: "6.3.16"
  controlled_conclusion: "slice_vertical_position identifies the macroblock row; the extension supplies high-order row bits for sufficiently large vertical sizes."

- record_id: H262-009
  source_id: H262
  source_reference: "6.3.17"
  controlled_conclusion: "At slice start, previous_macroblock_address is initialized from slice row and macroblock width; each decoded increment advances from that basis."

- record_id: H262-010
  source_id: H262
  source_reference: "7.2.2.2; Annex B Table B.14"
  controlled_conclusion: "A coded non-intra block's first coefficient uses the modified first-coefficient interpretation; EOB is illegal as that first coefficient, and later coefficients use ordinary Table B.14 interpretation."

- record_id: H262-011
  source_id: H262
  source_reference: "Annex B Table B.3"
  controlled_conclusion: "For a non-scalable P picture, VLC 001 is motion-forward-only: forward motion is present and pattern, intra and quant flags are clear."

- record_id: H262-012
  source_id: H262
  source_reference: "Annex B Table B.10"
  controlled_conclusion: "The one-bit VLC 1 represents motion_code zero."

- record_id: H262-013
  source_id: H262
  source_reference: "Annex B Table B.1"
  controlled_conclusion: "The one-bit VLC 1 represents macroblock_address_increment one."

- record_id: H262-014
  source_id: H262
  source_reference: "6.3.17; Annex B Table B.1"
  controlled_conclusion: "Table B.1 maps increments 1..33 to 1, 011, 010, 0011, 0010, 00011, 00010, 0000111, 0000110, 00001011, 00001010, 00001001, 00001000, 00000111, 00000110, 0000010111, 0000010110, 0000010101, 0000010100, 0000010011, 0000010010, 00000100011, 00000100010, 00000100001, 00000100000, 00000011111, 00000011110, 00000011101, 00000011100, 00000011011, 00000011010, 00000011001, and 00000011000 respectively. macroblock_escape is 00000001000 and adds 33 before the following escape or terminal increment code; MPEG-1 macroblock_stuffing is unavailable here."

- record_id: H262-015
  source_id: H262
  source_reference: "6.3.17; 7.6.6; 7.6.6.2"
  controlled_conclusion: "Except at slice start, an address gap identifies skipped macroblocks. In a P frame picture they use frame prediction, reset predictors to zero, use vector (0,0), and carry no residual; a slice's first and last macroblocks cannot be skipped."

- record_id: H262-016
  source_id: H262
  source_reference: "7.6.3.1; Annex B Table B.10"
  controlled_conclusion: "For the controlled case motion_code +8 (VLC 0000010110), f_code 3, residual 3 and zero predictor reconstructs to +32 half-luma-sample units without wrap."

- record_id: H262-017
  source_id: H262
  source_reference: "7.6.3.7"
  controlled_conclusion: "For 4:2:0, divide reconstructed luma motion-vector components by two to obtain chroma components; controlled luma (+32,0) becomes chroma (+16,0)."

- record_id: H262-018
  source_id: H262
  source_reference: "Annex B Table B.3"
  controlled_conclusion: "In a non-scalable P picture, macroblock_type VLC 1 sets forward motion and coded pattern while clearing quant and intra, so both motion and residual syntax follow."

- record_id: H262-019
  source_id: H262
  source_reference: "Annex B Table B.9"
  controlled_conclusion: "VLC 001100 is coded_block_pattern 63, selecting all six Y0/Y1/Y2/Y3/Cb/Cr blocks in 4:2:0."

- record_id: H262-020
  source_id: H262
  source_reference: "7.2.2.2; Annex B Table B.14"
  controlled_conclusion: "For the controlled non-intra first coefficient, VLC 0000001010 is run 0 level 7, sign 0 makes it positive, and the following ordinary code 10 is EOB."

- record_id: H262-021
  source_id: H262
  source_reference: "6.3.17.4; Annex B Table B.9"
  controlled_conclusion: "For 4:2:0, cbp bit (5-i) selects block i. Controlled mappings include 32=1010, 3=001101, 12=10011, and 21=00011001; cbp 0 is not used for 4:2:0."

- record_id: H262-022
  source_id: H262
  source_reference: "7.6.3.1; Annex B Table B.10"
  controlled_conclusion: "For each component r_size=f_code-1 and f=2^r_size. Reconstruct the differential from signed motion_code and residual, add the applicable PMV, then wrap to [-16f,16f-1]; f_code 3 therefore permits [-64,+63]."

- record_id: H262-023
  source_id: H262
  source_reference: "Arithmetic operators; 7.6.3.7; 7.6.4"
  controlled_conclusion: "4:2:0 chroma scaling divides toward zero; reference integer addressing uses DIV 2 toward minus infinity, a remainder selects half-sample interpolation, and interpolation uses the specified nearest rounding."

- record_id: H262-024
  source_id: H262
  source_reference: "7.2.2.3; Annex B Table B.14"
  controlled_conclusion: "Table B.14 Escape is 000001 followed by six-bit run and twelve-bit two's-complement signed_level; apply the run before placing the level and reject forbidden levels or position overflow."

- record_id: H262-025
  source_id: H262
  source_reference: "6.1.2; 6.1.2.2; 6.3.16; 6.3.17; Table 8-5"
  controlled_conclusion: "A slice is a non-empty, non-overlapping run within one macroblock row. Reset previous address to row*width-1 at each slice; its first increment positions the first coded macroblock and does not create leading skips. Restricted slice structure requires complete picture coverage."

- record_id: H262-026
  source_id: H262
  source_reference: "6.3.17; Annex B Table B.4"
  controlled_conclusion: "In a non-scalable B picture, VLC 00011 is intra without quant and 000001 is intra with quant. Both clear motion and pattern; the quantized form alone carries quantiser_scale_code, and both carry six 4:2:0 intra blocks."

- record_id: H262-027
  source_id: H262
  source_reference: "6.3.3; Table 6-4"
  controlled_conclusion: "frame_rate_code values are 1=24000/1001, 2=24, 3=25, 4=30000/1001, 5=30, 6=50, 7=60000/1001 and 8=60 frames/s; 0 is forbidden and 9..15 reserved. The final rate is the table value times (frame_rate_extension_n+1)/(frame_rate_extension_d+1)."
  conformance_effect: "Cadence must distinguish fractional 24000/1001 and 30000/1001 rates from integer 24 and 30 rather than treating either pair as interchangeable."

- record_id: H262-028
  source_id: H262
  source_reference: "6.3.5"
  controlled_conclusion: "When progressive_sequence is zero, a coded sequence may contain frame pictures and field pictures, and a frame picture may represent either a progressive or an interlaced frame."
  conformance_effect: "Do not reject a complete frame picture solely because the sequence is interlaced; apply the picture-level structure and progressive-frame rules."

- record_id: H262-029
  source_id: H262
  source_reference: "6.3.3"
  controlled_conclusion: "For a frame picture in a sequence with progressive_sequence equal to zero, encoded luminance macroblock height is 2*((vertical_size+31)/32); the displayable region is top-aligned."
  conformance_effect: "A 480-line interlaced frame picture occupies 30 macroblock rows, matching the existing 720x480 full-frame storage geometry while retaining interlaced semantics."

- record_id: H262-030
  source_id: H262
  source_reference: "6.3.10; Table 6-14"
  controlled_conclusion: "picture_structure values 01 and 10 identify top- and bottom-field pictures respectively, while 11 identifies a complete frame picture; 00 is reserved."
  conformance_effect: "The first native-interlaced subset admits only picture_structure 11 and must continue to reject separately coded field pictures."

- record_id: H262-031
  source_id: H262
  source_reference: "6.3.10"
  controlled_conclusion: "In an interlaced-sequence frame picture, top_field_first equal to one outputs the reconstructed top field first; zero outputs the reconstructed bottom field first."
  conformance_effect: "Native presentation must preserve the authored TFF or BFF value rather than deriving field order from line parity or a fixed display preference."

- record_id: H262-032
  source_id: H262
  source_reference: "6.3.10; 6.3.17.1"
  controlled_conclusion: "frame_pred_frame_dct equal to one restricts a frame picture to frame DCT and frame prediction. frame_motion_type is then absent and prediction is decoded as frame-based."
  conformance_effect: "This flag defines a bounded interlaced-frame subset that can reuse the existing frame-DCT macroblock raster and excludes field-DCT and field-motion syntax."

- record_id: H262-033
  source_id: H262
  source_reference: "6.3.10"
  controlled_conclusion: "For 4:2:0, chroma_420_type shall equal progressive_frame. When progressive_sequence and progressive_frame are both zero, repeat_first_field shall be zero and the reconstructed frame outputs as exactly two fields."
  conformance_effect: "The first interlaced subset requires chroma_420_type=0, progressive_frame=0, and repeat_first_field=0; any other combination remains outside the milestone."

- record_id: H262-034
  source_id: H262
  source_reference: "6.3.3; Table 6-4; 7.1"
  controlled_conclusion: "For progressive_sequence equal to zero, reconstructed frames are broken into fields and output at regular field-period intervals; the field period is one half of the reciprocal of the signalled frame rate."
  conformance_effect: "A frame_rate_code 4 stream is presented as 30000/1001 frames per second and 60000/1001 authored fields per second, with field rather than frame publication cadence."

- record_id: H262-035
  source_id: H262
  source_reference: "6.1.1.8; Figures 6-1 through 6-3"
  controlled_conclusion: "In 4:2:0 interlaced frames, chrominance has half the frame width and height; its samples retain the same spatial frame locations whether the interlaced frame is represented by one frame picture or two field pictures, and their vertical relation to field luminance differs from progressive-frame sampling."
  conformance_effect: "Native field presentation must use interlaced 4:2:0 chroma expansion and cannot reuse progressive vertical chroma pairing without qualification."
- record_id: H262-036
  source_id: H262
  source_reference: "H.262 (02/2000), 6.3.11; 7.3.1"
  controlled_conclusion: "Sequence headers reset both matrices; extensions preserve unloaded matrices. Downloads use default zigzag order. For 4:2:0, luma and chroma share weights."
  conformance_effect: "Load generic weights before their dependent transform transactions."

- record_id: H262-037
  source_id: H262
  source_reference: "H.262 (02/2000), 7.4.2.3; 7.4.3; 7.4.4"
  controlled_conclusion: "Non-DC reconstruction uses ((2QF+k)*W*scale)/32, truncating toward zero; k is zero for intra and sign(QF) otherwise. Saturation precedes mismatch control."
  conformance_effect: "Preserve DC handling and both scan and scale modes."

- record_id: H262-038
  source_id: H262
  source_reference: "H.262 (02/2000), 6.3.10; 7.1"
  controlled_conclusion: "In interlaced sequences, progressive frames output two fields, or three when repeat_first_field is set; top_field_first identifies the first field, repeated third."
  conformance_effect: "Retain order, duration and progressive chroma per picture."

- record_id: H262-039
  source_id: H262
  source_reference: "H.262 (02/2000), Table B-4"
  controlled_conclusion: "Non-intra B codes 00010, 000011 and 000010 carry quantizer and pattern, using bidirectional, forward and backward prediction respectively."
  conformance_effect: "Parse quantizer changes before the existing motion and residual syntax."

- record_id: H262-040
  source_id: H262
  source_reference: "H.262 (02/2000), 7.6.3.4"
  controlled_conclusion: "An intra macroblock without concealment motion vectors resets all motion-vector predictors to zero."
  conformance_effect: "Clear forward and backward components before subsequent prediction."

```

---

## 6. H.222.0 records for v0.7.0

These records are verified against the official free H.222.0 (06/2021) text. Recheck the 2025 edition delta before advertising conformance to v10.

```yaml
- record_id: H222-001
  source_id: H222
  title: "Program Stream framing and termination"
  source_reference: "2.5.3.1; Table 2-37; 2.5.3.2"
  controlled_conclusion: "A Program Stream is a sequence of packs while the next code is pack_start_code and terminates with MPEG_program_end_code 0x000001B9."
  conformance_effect: "Accept consecutive packs and distinguish a normative program end from truncation or an unrelated start code."

- record_id: H222-002
  source_id: H222
  title: "Pack header, SCR, mux rate and stuffing"
  source_reference: "2.5.3.3; Tables 2-38 and 2-39; 2.5.3.4"
  controlled_conclusion: "A pack begins with 0x000001BA. Its MPEG-2 header starts with fixed bits 01, carries the 33-bit SCR base, 9-bit SCR extension, marker bits, 22-bit program_mux_rate, and a 3-bit stuffing length permitting at most seven 0xFF bytes. program_mux_rate is non-zero and measured in units of 50 bytes/s."
  conformance_effect: "Parse the complete pack header and skip exactly the signalled stuffing before inspecting the optional system header or PES packets."

- record_id: H222-003
  source_id: H222
  title: "System-header framing and length"
  source_reference: "2.5.3.5; Table 2-40; 2.5.3.6"
  controlled_conclusion: "A system header begins with 0x000001BB. header_length counts all bytes following that field, and future extensions may increase the header beyond fields understood by an older parser."
  conformance_effect: "Honor header_length and skip unsupported remaining bytes without losing the next packet boundary."

- record_id: H222-004
  source_id: H222
  title: "PES packet framing and Program Stream length"
  source_reference: "2.4.3.6; Table 2-21; 2.4.3.7"
  controlled_conclusion: "A PES packet starts with prefix 0x000001, an 8-bit stream_id and a 16-bit PES_packet_length counting bytes after the length field. Length zero is permitted only for video carried in Transport Stream packets, not Program Stream packets."
  conformance_effect: "Require a bounded PES_packet_length in Program Stream input and use it to delimit header plus payload."

- record_id: H222-005
  source_id: H222
  title: "Program Stream stream identifiers"
  source_reference: "2.4.3.7; Table 2-22"
  controlled_conclusion: "Relevant stream_id ranges are 0xE0..0xEF for video and 0xC0..0xDF for audio; 0xBC is program_stream_map, 0xBD private_stream_1, 0xBE padding_stream, 0xBF private_stream_2, and 0xFF program_stream_directory."
  conformance_effect: "Select supported video PES packets while consuming or skipping every other packet according to its declared length and syntax class."

- record_id: H222-006
  source_id: H222
  title: "PES optional header and timestamp flags"
  source_reference: "2.4.3.6; Table 2-21; 2.4.3.7"
  controlled_conclusion: "A normal PES optional header begins with fixed bits 10. PTS_DTS_flags 00 means neither timestamp, 10 means PTS only, 11 means PTS and DTS, and 01 is forbidden. PES_header_data_length counts optional-header and stuffing bytes after that field; timestamp marker bits are one. Defined special stream IDs omit this normal optional-header form."
  conformance_effect: "Interpret the flag combinations exactly, validate fixed and marker bits, and locate payload by the declared header-data length rather than a fixed offset."

- record_id: H222-007
  source_id: H222
  title: "PTS/DTS units, wrap and H.262 picture association"
  source_reference: "2.4.3.7"
  controlled_conclusion: "PTS and DTS are 33-bit values in units of the system clock divided by 300, i.e. 90 kHz, and wrap modulo 2^33. For H.262 video, a timestamp applies to the access unit containing the first picture_start_code that begins in that PES packet."
  conformance_effect: "Associate timestamps with the correct coded picture, compare them modulo 2^33, and preserve separate decode and presentation meanings when both are present."

- record_id: H222-008
  source_id: H222
  title: "System clock and SCR representation"
  source_reference: "2.5.2.1; 2.5.2.2"
  controlled_conclusion: "The nominal system clock is 27 MHz. SCR is represented as SCR_base*300+SCR_extension, with the base modulo 2^33 and extension modulo 300, and relates the Program Stream byte-arrival schedule to program_mux_rate."
  conformance_effect: "Keep the 27 MHz SCR representation distinct from 90 kHz PTS/DTS units and perform conversion without dropping the fractional 300-count component."

- record_id: H222-009
  source_id: H222
  title: "Program Stream Map and MPEG-2 video stream type"
  source_reference: "2.5.4.1; 2.5.4.2; Table 2-34; Annex A"
  controlled_conclusion: "A Program Stream Map carries current/version fields, descriptor lengths, an elementary-stream map and CRC-32. stream_type 0x02 identifies H.262 video or constrained MPEG-1 video."
  conformance_effect: "When a map is present, use declared lengths to traverse it, recognize stream_type 0x02, and interpret its CRC-32 according to Annex A."

- record_id: H222-010
  source_id: H222
  title: "PES data-alignment indicator"
  source_reference: "2.4.3.7"
  controlled_conclusion: "data_alignment_indicator equal to one says the PES header is immediately followed by the syntax element identified by the applicable alignment descriptor or default; zero leaves alignment undefined."
  conformance_effect: "Do not assume every PES payload begins on a picture or other access-unit boundary when the indicator is zero."

- record_id: H222-011
  source_id: H222
  title: "Decode-order and presentation-order timing"
  source_reference: "2.4.3.7"
  controlled_conclusion: "For B pictures, and for I/P pictures in low_delay sequences, presentation time equals decoding time. For an I/P picture in a sequence without low_delay, its presentation time equals the decoding time of the next I/P picture in bitstream order."
  conformance_effect: "Do not derive display time from decode completion alone when H.262 picture reordering is active; preserve the timestamp-defined presentation order."
```

---

## 7. Adopted project release profile

The following official external production profile is adopted as the project's release media target. It defines the required media essence and container baseline; it is not a substitute for the separately controlled DVD-Video application, filesystem, navigation, menu or CSS specifications.

```yaml
- record_id: NARA-001
  title: "Adopted NARA MPD-D2 DVD-from-film release media profile"
  status: VERIFIED
  verified_date: 2026-08-29
  confidence: HIGH
  source_id: NARA-MPD-D2
  source_edition: "Official web profile reviewed December 22, 2023"
  source_reference: "Nature of Source Material; File Properties; File Specifications"
  controlled_conclusion: "The MPD-D2 distribution-copy profile uses VOB files carrying MPEG-2 Program Stream essence at Main Profile and Main Level, made from temporary 8 Mbps SD MPEG-2 source, with 720x480 constant-bit-rate video at 29.97 frames per second, interlaced top-field-first and single-pass encoded. Audio is two-channel stereo AC-3 at 256 Kbps constant bitrate, 48 kHz, with a listed 16-bit sample size."
  applicability: "Project release media target for U.S. DVD-from-motion-picture-film playback; controls qualifying VOB/Program Stream video and audio essence."
  exceptions:
    - "Does not define or qualify DVD filesystem access, IFO navigation, menus, subpictures, CSS, optical-drive behavior or every DVD-Video application constraint."
    - "Does not constrain H.262 picture_structure, motion_type, macroblock dct_type, GOP design or quantization matrices; do not infer a frame-picture-only or ordinary-motion-only subset from this profile."
    - "Does not establish that every commercial DVD uses this profile or expand the target to PAL/576i."
  conformance_effect: "Release qualification shall include retained streams that match every listed media property, exercise the implemented H.262 syntax envelope and verify correct complete playback, field order, cadence, decoded HDMI stereo and AC-3 S/PDIF passthrough. Any profile-permitted syntax not qualified by those streams remains an explicit release limitation, and the deferred DVD application features shall not be claimed."
```

---

## 8. Record template

```yaml
- record_id: "<DOMAIN>-<NNN>"
  title: "One atomic controlled rule"
  status: VERIFIED
  verified_date: YYYY-MM-DD
  confidence: HIGH
  source_id: "<catalog ID>"
  source_edition: "Exact edition consulted"
  source_reference: "Exact clause/table/figure/annex/page"
  controlled_conclusion: "Concise externally defined rule"
  applicability: "Exact conditions"
  exceptions: []
  conformance_effect: "Observable condition to verify"
```

---

## 9. Maintenance boundary

- Keep controlled conclusions, source identity, exact references, applicability, exceptions and observable conformance effects here.
- Keep architecture, resource tradeoffs, timing results, tests, failures, deployment policy and chronological history in the appropriate project-control files.
- Never invent a clause number or upgrade an older-edition result into a current-edition claim.
- Restore detailed source routing only when a corresponding milestone becomes active; do not pre-load speculative catalogs.
- Audit records changed since the prior release before each tagged release.

```yaml
catalog_verified_on: 2026-08-29
official_catalog_pages_checked:
  - "ITU-T H.262 recommendation database and official 02/2000 text"
  - "ITU-T H.222.0 current 04/2025 record and official free 06/2021 text"
  - "ISO/IEC 13818-4 catalog record"
  - "U.S. National Archives MPD-D2 official profile, reviewed 2023-12-22"
known_access_gaps:
  - "H.222.0 (04/2025) text is not loaded; new H222 records are verified against the official 06/2021 edition."
  - "Authorized DVD application and CSS books are not loaded and are not represented by clause-level records; NARA MPD-D2 does not replace them."
```
