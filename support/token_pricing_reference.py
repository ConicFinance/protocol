from decimal import Decimal

A_PREC = 100

# functions to simplify the iterative process
def calc_a(D: Decimal, A: Decimal, n: int) -> Decimal:
    # NOTE: not using (A * n ** n) since the Curve code differs from the white paper / comment
    return D * A_PREC / (A * n) - D


def calc_b(D: Decimal, A: Decimal, n: int) -> Decimal:
    # NOTE: Using (A * n ** (2 * n - 1) instead of (A * n ** (2 * n) as the Curve implementation seems to differ from the paper
    return D ** (n + 1) * A_PREC / (A * n ** (2 * n - 1))


def calc_r(x: Decimal, b: Decimal, a: Decimal) -> Decimal:
    return (x * (4 * b + x * (a + x) ** 2)).sqrt()


def compute_df_s_for_x_and_s(
    D: Decimal, A: Decimal, x: Decimal, s: Decimal, n: int
) -> Decimal:
    a = calc_a(D, A, n)
    b = calc_b(D, A, n)
    r = calc_r(x, b, a)
    # print("[ref] a, b, r", a, b, r)
    num = -2 * b + x * (a * x + x**2 - r)
    denom = 2 * x * r
    return -s - num / denom


def compute_ddf_for_x(D: Decimal, A: Decimal, x: Decimal, n: int) -> Decimal:
    a = calc_a(D, A, n)
    b = calc_b(D, A, n)

    numerator = 2 * b * (3 * b + x * (a**2 + 3 * a * x + 3 * x**2))
    denominator = x * (x * (4 * b + x * (a + x) ** 2)) ** (Decimal(3) / 2)

    return -numerator / denominator


def next_iter(D: Decimal, A: Decimal, x: Decimal, s: Decimal, n: int) -> Decimal:
    num = compute_df_s_for_x_and_s(D, A, x, s, n)
    denom = compute_ddf_for_x(D, A, x, n)
    adjust = num / denom
    if adjust >= x:
        adjust = x / 2
    return x - adjust


def calc_y_from_x_crv(x: Decimal, A: Decimal, D: Decimal, n: int = 2):
    Ann = A * n
    c = D**3 * A_PREC / (x * Ann * n**2)
    b = x + D * A_PREC / Ann
    y = D
    y_prev = Decimal(0)
    for _ in range(255):
        y_prev = y
        y = (y**2 + c) / (2 * y + b - D)
        if abs(y - y_prev) < 1:
            return y
    return y


def calc_y_from_D(D: Decimal, A: Decimal, price: Decimal, n: int = 2):
    x_cur = D
    x_prev = Decimal(0)
    for _ in range(255):
        x_cur = next_iter(D, A, x_cur, price, n)
        if abs(x_cur - x_prev) < Decimal("0.001"):
            break
        x_prev = x_cur

    return x_cur - Decimal("0.5")


def get_v1_lp_token_price(
    D: Decimal,
    total_supply: Decimal,
    A_precise: Decimal,
    price_a: Decimal,
    price_b: Decimal,
) -> Decimal:
    amount_asset_a = calc_y_from_D(D, A_precise, price_a)
    amount_asset_b = calc_y_from_x_crv(amount_asset_a, A_precise, D)
    token_price = (amount_asset_a * price_a + amount_asset_b * price_b) / total_supply
    return token_price
