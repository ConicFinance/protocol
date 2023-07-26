from typing import List

A_PREC = 100
FEE_DENOMINATOR = 10**10
RATES = [1000000000000000000, 1000000000000000000]
PRECISION = 10**18  # The precision to convert to
N_COINS = 2


class CurvePool:
    def __init__(self, _A: int) -> None:
        self.A = _A * A_PREC
        self.balances = [0, 0]
        self.token_supply = 0
        self.fee = 0
        self.admin_fee = 0

    def _xp(self) -> List[int]:
        result = RATES.copy()
        for i in range(N_COINS):
            result[i] = result[i] * self.balances[i] // PRECISION
        return result

    def _xp_mem(self, _balances: List[int]):
        result = RATES.copy()
        for i in range(N_COINS):
            result[i] = result[i] * _balances[i] // PRECISION
        return result

    def get_D(self, _xp: List[int], _amp: int) -> int:
        S = 0
        D_prev = 0

        for _x in _xp:
            S += _x
        if S == 0:
            return 0

        D = S
        Ann = _amp * N_COINS
        for _ in range(255):
            D_P = D
            for _x in _xp:
                D_P = D_P * D // (_x * N_COINS)
            D_prev = D
            D = (
                (Ann * S // A_PREC + D_P * N_COINS)
                * D
                // ((Ann - A_PREC) * D // A_PREC + (N_COINS + 1) * D_P)
            )

            if D > D_prev:
                if D - D_prev <= 1:
                    return D
            else:
                if D_prev - D <= 1:
                    return D
        raise

    def _get_D_mem(self, _balances, _amp):
        return self.get_D(self._xp_mem(_balances), _amp)

    def get_virtual_price(self) -> int:
        D = self.get_D(self._xp(), self.A)
        token_supply = self.token_supply
        return D * 10**18 // token_supply

    def calc_token_amount(self, _amounts: List[int], _is_deposit: bool) -> int:
        amp = self.A
        balances = self.balances
        D0 = self.get_D(balances, amp)
        for i in range(N_COINS):
            if _is_deposit:
                balances[i] += _amounts[i]
            else:
                balances[i] -= _amounts[i]
        D1 = self.get_D(balances, amp)
        token_amount = self.token_supply
        diff = 0
        if _is_deposit:
            diff = D1 - D0
        else:
            diff = D0 - D1
        return diff * token_amount // D0

    def add_liquidity(self, _amounts: List[int], _min_mint_amount: int) -> int:
        amp = self.A
        old_balances = self.balances.copy()
        # Initial invariant
        D0 = self._get_D_mem(old_balances, amp)

        token_supply = self.token_supply
        new_balances = old_balances.copy()
        for i in range(N_COINS):
            if token_supply == 0:
                assert _amounts[i] > 0  # dev: initial deposit requires all coins
            # balances store amounts of c-tokens
            new_balances[i] += _amounts[i]

        # Invariant after change
        D1 = self._get_D_mem(new_balances, amp)
        assert D1 > D0

        # We need to recalculate the invariant accounting for fees
        # to calculate fair user's share
        D2 = D1
        fees = []
        mint_amount = 0
        if token_supply > 0:
            # Only account for fees if we are not the first to deposit
            fee = self.fee * N_COINS // (4 * (N_COINS - 1))
            admin_fee = self.admin_fee
            for i in range(N_COINS):
                ideal_balance = D1 * old_balances[i] // D0
                difference = 0
                new_balance = new_balances[i]
                if ideal_balance > new_balance:
                    difference = ideal_balance - new_balance
                else:
                    difference = new_balance - ideal_balance
                fees[i] = fee * difference // FEE_DENOMINATOR
                self.balances[i] = new_balance - (
                    fees[i] * admin_fee // FEE_DENOMINATOR
                )
                new_balances[i] -= fees[i]
            D2 = self._get_D_mem(new_balances, amp)
            mint_amount = token_supply * (D2 - D0) // D0
        else:
            self.balances = new_balances
            mint_amount = D1  # Take the dust if there was any
        assert mint_amount >= _min_mint_amount, "Slippage screwed you"

        self.token_supply += mint_amount
        return mint_amount

    def _get_y(self, i: int, j: int, x: int, _xp: List[int]) -> int:
        assert i != j  # dev: same coin
        assert j >= 0  # dev: j below zero
        assert j < N_COINS  # dev: j above N_COINS

        # should be unreachable, but good for safety
        assert i >= 0
        assert i < N_COINS

        A = self.A
        D = self.get_D(_xp, A)
        Ann = A * N_COINS
        c = D
        S = 0
        _x = 0
        y_prev = 0

        for _i in range(N_COINS):
            if _i == i:
                _x = x
            elif _i != j:
                _x = _xp[_i]
            else:
                continue
            S += _x
            c = c * D // (_x * N_COINS)
        c = c * D * A_PREC // (Ann * N_COINS)
        b = S + D * A_PREC // Ann  # - D
        y = D
        for _i in range(255):
            y_prev = y
            y = (y * y + c) // (2 * y + b - D)
            # Equality with the precision of 1
            if y > y_prev:
                if y - y_prev <= 1:
                    return y
            else:
                if y_prev - y <= 1:
                    return y
        raise

    def get_dy(self, i: int, j: int, _dx: int) -> int:
        xp = self._xp()
        rates = RATES

        x = xp[i] + (_dx * rates[i] // PRECISION)
        y = self._get_y(i, j, x, xp)
        dy = xp[j] - y - 1
        fee = self.fee * dy // FEE_DENOMINATOR
        return (dy - fee) * PRECISION // rates[j]
