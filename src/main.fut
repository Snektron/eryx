import "big_sum"
import "big_mul"
import "big_montgomery"
import "big_util"

entry big_add = big_add
entry big_sub = big_sub
entry big_mul = big_mul

entry big_montgomery_invert = big_montgomery_invert
entry big_montgomery_compute_r2 = big_montgomery_compute_r2
entry big_montgomery_multiply = big_montgomery_multiply
entry big_montgomery_convert_to = big_montgomery_convert_to
entry big_montgomery_convert_from = big_montgomery_convert_from

entry big_small_constant = big_small_constant

entry big_clone [n] (as: [n]u64): [n]u64 =
    copy as