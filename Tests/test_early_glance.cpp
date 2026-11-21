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
    assert(result.canKeepWarming(3.9, 0));
    assert(!result.canKeepWarming(4.0, 0));
    result.record(true, 3.6);
    result.record(true, 3.8);
    result.record(true, 4.0);
    assert(result.canKeepWarming(4.4, 0));
    assert(!result.canKeepWarming(4.5, 0));
    result.record(true, 9.6);
    result.record(true, 9.8);
    result.record(true, 9.98);
    assert(result.canKeepWarming(9.99, 0));
    assert(!result.canKeepWarming(10.0, 0));
    result.record(false, 9.99);
    assert(!result.canKeepWarming(9.99, 0));
    puts("PASS: three fresh matches required; presence extends warmup only within the hard limit");
}
