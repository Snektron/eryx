#!/usr/bin/env python
import sympy
import sys

BASE = 2**8
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
    print(len(candidates))
    for a in candidates:
        if all(pow(a, n // p, N) != 1 for p in factors):
            return a

def is_power_of_2(x):
    return x & (x - 1) == 0

def bit_reverse(x, bits):
    assert 0 <= x < 2 ** bits
    return int(f'{x:0{bits}b}'[::-1], 2)

def ntt(a):
    n = len(a)
    N = compute_working_modulus(BASE - 1, n)
    w = compute_primitive_root(n, N)

    def xk(k):
        result = 0
        for j, x in enumerate(a):
            result = (result + x * (w ** (j * k))) % N
        return result

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

def ntt3(a):
    a = [x for x in a]
    n = len(a)

    N = compute_working_modulus(BASE - 1, n)
    w = compute_primitive_root(n, N)
    # invw = pow(w, -1, N)

    # for i in range(n // 2):
    #     print(pow(invw, i, N))
    # return

    def iteration(j, ns, a, b):
        k = (j % ns) * n // (ns * 2)
        assert (j % ns) * n % (ns * 2) == 0

        v0 = a[j]
        v1 = pow(w, k, N) * a[j + n // 2]
        v0, v1 = (v0 + v1) % N, (v0 - v1) % N
        d = (j // ns) * ns * 2 + j % ns
        b[d] = v0
        b[d + ns] = v1

    assert is_power_of_2(n)
    b = [0] * n
    ns = 1
    while ns < n:
        for j in range(n // 2):
            iteration(j, ns, a, b)
        a, b = b, a
        ns *= 2
    return a

def intt3(a):
    a = [x for x in a]
    n = len(a)

    N = compute_working_modulus(BASE - 1, n)
    w = compute_primitive_root(n, N)
    invw = pow(w, -1, N)
    invn = pow(n, -1, N)

    def iteration(j, ns, a, b):
        k = (j % ns) * n // (ns * 2)
        assert (j % ns) * n % (ns * 2) == 0

        v0 = a[j]
        v1 = pow(invw, k, N) * a[j + n // 2]
        v0, v1 = (v0 + v1) % N, (v0 - v1) % N
        d = (j // ns) * ns * 2 + j % ns
        b[d] = v0
        b[d + ns] = v1

    assert is_power_of_2(n)
    b = [0] * n
    ns = 1
    while ns < n:
        for j in range(n // 2):
            iteration(j, ns, a, b)
        a, b = b, a
        ns *= 2

    for i in range(n):
        a[i] = a[i] * invn % N

    return a

class Montgomery:
    def __init__(self, mod):
        self.r = 2**64
        self.mod = mod
        self.inv = 1
        for i in range(6):
            self.inv *= 2 - n * self.inv
        self.inv %= self.r



    def mulhl(self, a, b):
        c = a * b
        return c // self.r, c % self.r

    def init(self, x):
        assert x < self.r
        x %= self.mod

        for i in range(64):
            x <<= 1
            x %= self.r
            if x >= self.mod:
                x -= self.mod
        return x

    def reduce(self, h, l):
        assert h < self.r and l < self.r
        q = (l * self.inv) % self.r
        a = h - (q * self.mod) // self.r
        if a < 0:
            a += self.mod
        return a

    def mult(self, a, b):
        h, l = self.mulhl(a, b)
        return self.reduce(h, l)

# f = [0] * MAX_N
# f[1] = 1
# print(ntt3(f))

# print(ntt3(f))

# a = 5315
# b = 249366121
# n = 4261675009

# print((a * b) % n)

# m = Montgomery(n)

# print(m.reduce(0, m.mult(m.init(a), m.init(b))))

# f = [4, 1, 4, 2, 1, 3, 5, 6]

# print(ntt([3, 2, 1, 0, 0, 0, 0, 0]))
# print(ntt([6, 5, 4, 0, 0, 0, 0, 0]))
# print(ntt2(f))
# print(ntt3(f))

# print(intt(ntt(f)))
# print(intt2(ntt2(f)))
# print(intt3(ntt3(f)))

# n = 16
# N = compute_working_modulus(BASE - 1, n)
# w = compute_primitive_root(n, N)
# invw = pow(w, -1, N)

# print([pow(w, i, N) for i in range(n // 2)])
# print([pow(invw, i, N) for i in range(n // 2)])

MAX_N_LOG2 = 26
BASE = 2 ** 8

Ns = [compute_working_modulus(BASE - 1, 2**i) for i in range(MAX_N_LOG2)]
print("primes =", Ns)

ws = [compute_primitive_root(2**i, Ns[i]) for i in range(MAX_N_LOG2)]
print("primitive roots =", ws)
