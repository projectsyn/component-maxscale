commodore_args += -a maxscale-$(instance)

.PHONY: test-nolimits
test-nolimits: instance = no_container_limits
test-nolimits: test

.PHONY: test-default
test-default: instance = defaults
test-default: test

.PHONY: test-affinity
test-affinity: instance = affinity
test-affinity: test

