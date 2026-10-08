# walstad loom v0.2.38

Released October 8, 2026. This release brings together the music, motion, ready-defaults, reliability and performance passes.

## Start a living tank

The primary **+ Living tank** action starts a populated Quick Garden. Fresh settings include automatic feeding, gentle lo-fi music, quieter percussion and a comfortable desk environment. Templates and guided setup remain available. Existing saved settings are preserved.

## Softer sound and more individual life

Filtered hats and gentler event layers reduce harshness. Phrasing and environmental musical coupling are more coherent. Fish turns and swimming bouts are smoother and more varied. Bounded, saved musical associations connect comfort, food and alarm to what a fish hears; sleep and stress temper the response. These are simulated behavioral states, not a claim of consciousness or an external AI service.

## Reproduction and restore fixes

Old JSON seed references recover the correct Plant subclass rather than trying to load a GDScript debug string. Coral forms and tip colors survive germination. Specialized geometry is configured before voxel construction. Seedlings use the destination floor height and autonomous germination respects the plant limit. Seed cohorts retain their own age and viability. Reloading replaces dormant seeds and plant-chemical mixtures, including empty saves and legacy migrations.

## Stable highlights and shelf photos

Fish sheen and bank lighting change smoothly, and stacked reflections retain pigment instead of entering the white bloom path. Legacy belly-flash materials are isolated per individual. Opened tanks get a palette-correct shelf photo shortly after construction, busy capture requests retry, and photo writes preserve the last good image. Older saves without photos show a labelled tank illustration until reopened. Taking photos preserves hidden UI panels and recovers cleanly when the camera is busy. Refused or corrupt saves block replacement writes and photos until recovery is resolved. Settings and tank-state workers are reclaimed, writes are atomic, and shutdown drains queued edits; tank saves coalesce independently by file.

## Performance

Simulation and animation share per-frame fish music responses. Broad habitat searches use occupied cells. Plant-chemical totals are cached, and nearby-creature scans avoid allocating empty buckets. These changes preserve behavior while reducing repeated work.

Targeted local CPU measurements include 6,000 repeated music reads improving from 39.4 ms to 1.15 ms, 3,000 sparse broad plant queries from 54.6 ms to 2.38 ms, chemical-total reads using about 32% less time, and neighbour searches about 22% less. These microbenchmarks do not measure overall FPS; benefit varies with tank density and workload.

## Validation and limitations

571 scripts compile with zero failures and zero analyzer warnings. All 237 local smoke tests pass, including the original performance limits, with zero failures and zero timeouts (129 seconds). The former three baseline failures were corrected: the MultiMesh test now checks CPU packing headlessly and GPU round-trips on an actual Metal renderer, the MSAA assertion follows platform safety policy, and the silhouette test checks voxel geometry rather than requiring redundant batches. The known-failure file is empty. Final isolated validation verified the real tank inventory was unchanged.

Parallel tests now have separate user directories. The performance fixture uses reproducible populations and releases the first before measuring the second. Actual rendered comparisons and a thumbnail lifecycle probe supplement the headless checks.

The 1,000-item improvement document is a backlog, not a claim that every item has been implemented. Detailed pass reports record the work and its limits:

- [Music and lo-fi](MUSIC_LOFI_PASS_20261007.md)
- [Soft audio](SOFT_AUDIO_PASS_20261007.md)
- [Swimming and motion](SWIMMING_MOTION_PASS_20261007.md)
- [Experience and ready defaults](EXPERIENCE_AND_READY_DEFAULTS_20261007.md)
- [Seedling reliability and performance](SEEDLING_RELIABILITY_PERFORMANCE_PASS_20261007.md)
- [Ecology restore and query performance](ECOLOGY_RESTORE_QUERY_PASS_20261007.md)


- [Visual edges and shelf photos](VISUAL_EDGES_PASS_20261008.md)
