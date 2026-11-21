#include "../Sources/early_glance.hpp"
#include <cassert>
#include <cstdio>

int main() {
    EarlyGlance result;
    assert(!result.fresh(0));
    result.record(true, 1.0);
    result.record(true, 1.2);
    assert(!result.fresh(1.2));
    result.record(true, 1.4);
    assert(result.fresh(1.6));
    assert(!result.fresh(1.9));
    result.record(true, 2.0);
    assert(!result.fresh(2.0));
    result.record(true, 2.2);
    result.record(true, 2.4);
    assert(result.fresh(2.4));
    result.record(false, 2.5);
    assert(!result.fresh(2.5));
    puts("PASS: three recent matches required; gaps and mismatches invalidate preparation");
}
