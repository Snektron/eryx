#!/usr/bin/env python
import sympy
import sys

BASE = 10
MAX_N = 8

def reverse(coeffs):
    return list(reversed(coeffs))

def next_power_of_2(x):
    return 1 if x == 0 else 2**(x - 1).bit_length()

def pad_power_of_2(arr):
    target_len = next_power_of_2(len(arr))
    return arr + (target_len - len(arr)) * [0]

def int_to_arr(val):
    return pad_power_of_2(pad_power_of_2(reverse(list(map(int, str(val))))) + [0])

def arr_to_int(arr):
    return int(''.join(map(str, reverse(arr))))

def carry(x):
    carry = 0
    for i in range(0, len(x)):
        y = x[i] + carry
        carry = y // 10
        x[i] = y % 10
    return x

def compute_working_modulus(m, n):
    M = m * m * n - 1
    k = (M - 1) // n
    while True:
        N = k * n + 1
        if N >= M and sympy.isprime(N):
            return N
        k += 1

def compute_primitive_root(n, N):
    factors = sympy.ntheory.factorint(n)
    candidates = sympy.ntheory.residue_ntheory.nthroot_mod(1, n, N, True)
    for a in candidates:
        if all(pow(a, n // p, N) != 1 for p in factors):
            return a

def is_power_of_2(x):
    return x & (x - 1) == 0

def ntt(a):
    n = len(a)
    N = compute_working_modulus(BASE - 1, n)
    w = compute_primitive_root(n, N)

    def xk(k):
        result = 0
        for j, x in enumerate(a):
            result += x * (w ** (j * k))
        return result % N

    return [xk(k) for k in range(n)]

def intt(a):
    n = len(a)
    N = compute_working_modulus(BASE - 1, n)
    w = compute_primitive_root(n, N)
    invw = pow(w, -1, N)
    invn = pow(n, -1, N)

    def xk(k):
        result = 0
        for j, x in enumerate(a):
            result += x * pow(invw, j * k) * invn
        return result % N
    return [xk(k) for k in range(n)]

def ntt2_r(N, a):
    n = len(a)
    w = compute_primitive_root(n, N)

    if n == 1:
        return [a[0]]

    a_even = a[0::2]
    a_odd = a[1::2]

    x_even = ntt2_r(N, a_even)
    x_odd = ntt2_r(N, a_odd)
    x = x_even + x_odd

    for k in range(n // 2):
        p = x[k]
        q = (w ** k) * x[k + n // 2]
        x[k] = (p + q) % N
        x[k + n // 2] = (p - q) % N

    return x

def ntt2(a):
    n = len(a)
    assert is_power_of_2(n)

    N = compute_working_modulus(BASE - 1, n)
    return ntt2_r(N, a)

def intt2_r(N, a):
    n = len(a)
    w = compute_primitive_root(n, N)
    invw = pow(w, -1, N)
    invn = pow(n, -1, N)

    if n == 1:
        return [a[0]]

    a_even = a[0::2]
    a_odd = a[1::2]

    x_even = intt2_r(N, a_even)
    x_odd = intt2_r(N, a_odd)
    x = x_even + x_odd

    for k in range(n // 2):
        p = x[k]
        q = (invw ** k) * x[k + n // 2]
        x[k] = (p + q) % N
        x[k + n // 2] = (p - q) % N

    return x

def intt2(a):
    n = len(a)
    assert is_power_of_2(n)

    N = compute_working_modulus(BASE - 1, n)
    invn = pow(n, -1, N)

    x = intt2_r(N, a)
    for k in range(n):
        x[k] = x[k] * invn % N
    return x

f = [4, 1, 4, 2, 1, 3, 5, 6]

print(ntt(f))
print(ntt2(f))

print(intt(ntt(f)))
print(intt2(ntt2(f)))
