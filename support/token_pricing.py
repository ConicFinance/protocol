from decimal import Decimal
from support.scaled_int import ScaledInt

A_PREC = 100

# functions to simplify the iterative process
def calc_a(D: ScaledInt, A: int, n=2) -> ScaledInt:
    # NOTE: not using (A * n ** n) since the Curve code differs from the white paper / comment
    return D * A_PREC / (A * n) - D


def calc_b(D: ScaledInt, A: int, n=2) -> ScaledInt:
    # NOTE: Using (A * n ** (2 * n - 1) instead of (A * n ** (2 * n) as the Curve implementation seems to differ from the paper
    return D ** (n + 1) * A_PREC / (A * n ** (2 * n - 1))


def calc_r(x: ScaledInt, b: ScaledInt, a: ScaledInt) -> ScaledInt:
    x = x.downscale(6)
    b = b.downscale(6)
    a = a.downscale(6)
    result = x.sqrt() * (4 * b + x * (a + x) ** 2).sqrt()
    return result.upscale(18)


def compute_df_s_for_x_and_s(
    D: ScaledInt, A: int, x: ScaledInt, s: ScaledInt, n=2
) -> ScaledInt:
    a = calc_a(D, A, n)
    b = calc_b(D, A, n)
    r = calc_r(x, b, a)
    num = -2 * b + (x * (a * x + x**2 - r))
    denom = 2 * x * r
    # NOTE: Use - dy/dx for now - double check this
    return -s - (num / denom)


def compute_ddf_for_x(D: ScaledInt, A: int, x: ScaledInt, n=2) -> ScaledInt:
    a = calc_a(D, A, n)
    b = calc_b(D, A, n)

    base = 4 * b.downscale(6) + x.downscale(6) * (a.downscale(6) + x.downscale(6)) ** 2

    t1 = 6 * b
    t1 /= x
    t1 /= x
    t1 = t1.downscale(6)
    t1 *= b.downscale(6)
    t1 /= base
    t1 = t1.upscale(18)

    t2 = 2 * b
    t2 /= x
    t2 = t2
    t2 *= a
    t2 /= base.upscale(18)
    t2 *= a

    t3 = 6 * b.downscale(6)
    t3 /= base
    t3 = t3.upscale(18)
    t3 *= a

    t4 = 6 * b.downscale(6)
    t4 /= base
    t4 = t4.upscale(18)
    t4 *= x

    numerator = t1 + t2 + t3 + t4
    denominator = -(x.downscale(6).sqrt() * base.sqrt()).upscale(18)
    result = numerator / denominator

    return result


def next_iter(D: ScaledInt, A: int, x: ScaledInt, s: ScaledInt, n=2) -> ScaledInt:
    num = compute_df_s_for_x_and_s(D, A, x, s, n)
    denom = compute_ddf_for_x(D, A, x, n)
    adjust = num / denom
    if adjust >= x:
        adjust = x / 2
    return x - adjust


def calc_y_from_x_crv(x: ScaledInt, A: int, D: ScaledInt, n: int = 2):
    Ann = A * n
    c = D * A_PREC
    c = c * D / (x * n)
    c = c * D / (Ann * n)
    b = x + D * A_PREC / Ann
    y = D
    y_prev = ScaledInt(0, 1)
    for _ in range(255):
        y_prev = y
        y = (y**2 + c) / (2 * y + b - D)
        if abs(y - y_prev) < 1:
            return y
    return y


def calc_y_from_D(D: ScaledInt, A: int, price: ScaledInt):
    x_cur = D
    x_prev = ScaledInt.from_int(0, x_cur.decimals)
    for _ in range(255):
        x_cur = next_iter(D, A, x_cur, price)
        if abs(x_cur - x_prev) < 1:
            break
        x_prev = x_cur

    return x_cur - ScaledInt.from_int(1) / 2
