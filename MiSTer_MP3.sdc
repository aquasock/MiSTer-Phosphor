# Project-specific timing constraints, additive to sys/sys_top.sdc (left
# unmodified -- it's the reused framework file). Loaded after it (see
# files.qip's trailing SDC_FILE assignment), so these refine its clock-group
# assignment and add constraints for the framework modules this core reuses
# verbatim but whose own accompanying timing constraints were never copied
# over from the sibling MiSTer-Phosphor project.
#
# This file was written after running TimeQuest for the first time on this
# project and finding real (if largely misleading) violations -- see
# docs/MP3.md's timing-closure section for the full investigation writeup.

# sys_top.sdc's own set_clock_groups groups this project's *whole* PLL (both
# general[0]=clk_sys and general[1]=clk_video_pll) into ONE clock group
# together, since its glob `*|pll|pll_inst|altera_pll_i|*[*].*` matches both
# outputs -- so TimeQuest checks every clk_sys<->clk_video_pll path as an
# ordinary synchronous same-relationship path. It isn't: they're two
# independently divided outputs of the same PLL with no defined phase
# relationship, and this project's only crossing between them (the board
# reset asserting into the clk_video_pll-domain blanked-video timing
# counters in MiSTer_MP3.sv) is a single-bit asynchronous level, not data
# needing a synchronous check. This is what caused the large
# clk_video_pll-domain TNS found on the first STA run.
set_clock_groups -exclusive \
    -group [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -group [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]

# --- Everything below ported from MediaPlayer.sdc (MiSTer-Phosphor), scoped
# to only the framework modules this core actually reuses verbatim:
# rtl/video_config_cdc.sv and the rtl/platform/ HDMI-native-audio cascade
# (hdmi_audio_config, hdmi_i2c_owner, hdmi_i2c_write_watch,
# i2c_register_master, media_audio_clocks, media_audio_rate_control,
# media_hdmi_audio_control, media_native_audio). Everything in
# MediaPlayer.sdc specific to Phosphor's own MPEG-2 framebuffer, OSD
# compositor, media_ui_scene, or media_session_control does NOT apply here
# -- this core has none of those modules -- and is intentionally omitted.

# Configuration mailbox (video_config_cdc): data is held fixed from request
# through acknowledgement. Cut only the held bundle and first synchronizer
# stages; every other stage remains fully timed.
set_false_path -from [get_keepers {*video_config_cdc:*|held_data[*]}] -to [get_keepers {*video_config_cdc:*|dst_data[*]}]
set_false_path -to [get_keepers {*video_config_cdc:*|req_sync[0]}]
set_false_path -to [get_keepers {*video_config_cdc:*|ack_sync[0]}]

# Native audio CDCs: only the first synchronizer stages cross clocks.
set_false_path -to [get_keepers {*media_native_audio:*|select_sync[0]}]
set_false_path -to [get_keepers {*media_native_audio:*|lock_sync[0]}]
set_false_path -to [get_keepers {*media_native_audio:*|mute_movie_sync[0]}]

# Asynchronous sources entering only these async-assert/sync-release
# chains; stage-to-stage release paths remain fully timed. Phosphor's own
# equivalent block also cuts media_session_control/reset_mpeg2_sync --
# confirmed absent from this project's RTL (grepped, no matches), so those
# two stay unported. `reset_req` is NOT Phosphor-specific the way those two
# are: it's declared directly in sys/sys_top.v (line ~590), the generic
# MiSTer framework's own board-reset-derived signal, present in every core
# that reuses this sys/ tree, this one included -- wrongly grouped with the
# Phosphor-only names on the first pass without checking each one
# individually. Lesson: a space-separated get_keepers list ported from
# another project needs each name verified on its own, not accepted or
# rejected as a whole group.
#
# Phosphor's own `media_music_mode` (the third name in that original list,
# also left unported at first as "no analog here") DOES have a real analog:
# this project's own format-dispatch logic drives PLAYER_PCM_RESET the same
# way Phosphor drives its own CD-audio reset from media_music_mode --
# `!wav_active` is asserted for the entire sniffing/replaying window,
# ultimately traced back to the sniff_count/replay_count/format_mode
# registers below, which are ordinary clk_sys-domain control logic, not
# "designated" reset sources, but land on this same async reset net anyway.
# Found by re-running quartus_sta and tracing the actual failing path (was
# `emu|sniff_count[2] -> media_native_audio:*|rd_reset_sync[*]`) once WAV
# playback started driving this rail with real data for the first time,
# not assumed up front.
#
# wr_reset_sync/rd_reset_sync themselves were confirmed absent from the
# post-fit netlist before any format actually drove real PCM through this
# rail (this core drove no real data into media_native_audio's CD-audio
# input path yet, so Quartus's optimizer removed that whole cascade despite
# the source's own (* preserve *) attribute -- preserve stops a register
# being removed as "redundant", not from being swept once truly
# unreachable) -- both chains are included below now that WAV activates
# this path for real.
# A second, previously-missed contributor to this same net: PLAYER_PCM_RESET
# (`decoder_reset || !(wav_active||flac_active)`) also folds in this
# project's own `reset` (`RESET || status[0] || buttons[1]`, i.e. the
# OSD/joypad reset request) and `new_file` (`img_mounted[0] &&
# !img_mounted_d`, the new-file-loaded edge). Both are exactly the same
# class of async, level-type "start fresh" source as reset_req/init_reset_n
# above, just not enumerated yet -- found by re-running quartus_sta and
# tracing the actual failing recovery path's real register fan-in
# (`hps_io|status[0]`, `hps_io|cfg[1]` [=buttons[1]], `hps_io|img_mounted[0]`,
# `emu|img_mounted_d`) rather than assuming the first pass's source list was
# complete. `RESET` itself is a raw top-level port, not a register, so it
# can't appear as a recovery "launch" source (no keeper to point at) --
# unconstrained-input handling for that pin is a separate, pre-existing
# condition shared by every MiSTer core built on this same sys/ framework,
# not something introduced or fixed here.
set native_audio_async_reset_srcs [get_keepers {reset_req *sysmem|init_reset_n* *emu:emu|sniff_count* *emu:emu|replay_count* *emu:emu|format_mode* *hps_io:hps_io|status[0] *hps_io:hps_io|cfg[1] *hps_io:hps_io|img_mounted[0] *emu:emu|img_mounted_d *emu:emu|switch_pending *emu:emu|album_loop_pending *flac_album_control:album_control|restart *flac_album_control:album_control|busy}]
if {[get_collection_size $native_audio_async_reset_srcs] < 2} {error "Missing an expected native-audio async reset source (reset_req or the platform power-up reset)"}
foreach chain {wr_reset_sync rd_reset_sync ref_reset_sync movie_reset_sync out_reset_sync} {
    set target [format {*media_native_audio:*|%s[*]} $chain]
    set_false_path -from $native_audio_async_reset_srcs -to [get_keepers $target]
}

# The real fix for this project's two largest STA violations (both close to
# -400 TNS on the first run): media_audio_clocks' altclkctrl selector output
# is fed by two independently-running PLLs (the "music"/native_audio clock
# and the "movie"/pll_audio clock) that are mutually exclusive in real
# hardware -- exactly one is ever actually selected -- but TimeQuest has no
# way to know that from the netlist alone, so it was checking a synchronous
# relationship between two genuinely unrelated, always-running clocks
# through the mux. Declaring the two generated clocks physically exclusive
# tells it not to.
set music_master [get_clocks {*native_audio|clocks|cd_pll|*|divclk}]
set movie_master [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|*|divclk}]
set music_mux_out [get_pins -compatibility_mode {*native_audio|clocks|selector|auto_generated|sd2|outclk}]
set music_mux_in [get_pins -compatibility_mode {*native_audio|clocks|selector|auto_generated|sd2|inclk[3]}]
set movie_mux_in [get_pins -compatibility_mode {*native_audio|clocks|selector|auto_generated|sd2|inclk[2]}]
foreach collection [list $music_master $movie_master $music_mux_out $music_mux_in $movie_mux_in] {
    if {[get_collection_size $collection] != 1} {error "Native audio clock selector constraint must resolve exactly one node"}
}
create_generated_clock -name audio_mux_cd -master_clock $music_master -source $music_mux_in -divide_by 1 $music_mux_out
create_generated_clock -name audio_mux_movie -master_clock $movie_master -source $movie_mux_in -divide_by 1 -add $music_mux_out
set_clock_groups -physically_exclusive -group [get_clocks audio_mux_cd] -group [get_clocks audio_mux_movie]

# Gate requests (media_audio_clocks) cross through three preserved stages
# before the hard gate; the opposite-clock enable is unreachable at the
# selected gate since the same held select bit chooses both the PLL and its
# synchronized gate request.
set_false_path -to [get_keepers {*media_audio_clocks:*|cd_gate_sync[0]}]
set_false_path -to [get_keepers {*media_audio_clocks:*|movie_gate_sync[0]}]
set_false_path -from [get_keepers {*media_audio_clocks:*|movie_gate_sync[2]}] -to [get_clocks audio_mux_cd]
set_false_path -from [get_keepers {*media_audio_clocks:*|cd_gate_sync[2]}] -to [get_clocks audio_mux_movie]

# Intel documents these first-stage DCFIFO ACLR exceptions when both
# write_aclr_synch and read_aclr_synch are enabled (audio_pcm_fifo.sv's
# dcfifo uses both). The generated instance names include version-dependent
# suffixes, so match only the documented wraclr/rdaclr synchronizer stage-0
# structure rather than the whole FIFO.
set_false_path -to [get_keepers {*|dcfifo:*|dcfifo_*:auto_generated|dffpipe_*:wraclr|dffe*a[0]}]
set_false_path -to [get_keepers {*|dcfifo:*|dcfifo_*:auto_generated|dffpipe_*:rdaclr|dffe*a[0]}]
