// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


pragma solidity ^0.8.10;

interface IPancakeStableSwap {
    function token() external view returns (address);

    function balances(uint256 i) external view returns (uint256);

    function RATES(uint256 i) external view returns (uint256);

    function PRECISION_MUL(uint256 i) external view returns (uint256);

    function fee() external view returns (uint256);

    function admin_fee() external view returns (uint256);

    function A() external view returns (uint256);

    function get_D_mem(uint256[2] memory _balances, uint256 amp) external view returns (uint256);

    function get_y(
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[2] memory xp_
    ) external view returns (uint256);

    function calc_withdraw_one_coin(uint256 _token_amount, uint256 i) external view returns (uint256);
}

contract PancakeStableSwapInfo {
    uint256 public constant N_COINS = 2;
    uint256 public constant FEE_DENOMINATOR = 1e10;
    uint256 public constant PRECISION = 1e18;

    function token(address _swap) public view returns (IERC20) {
        return IERC20(IPancakeStableSwap(_swap).token());
    }

    function balances(address _swap) public view returns (uint256[N_COINS] memory swapBalances) {
        for (uint256 i = 0; i < N_COINS; i++) {
            swapBalances[i] = IPancakeStableSwap(_swap).balances(i);
        }
    }

    function RATES(address _swap) public view returns (uint256[N_COINS] memory swapRATES) {
        for (uint256 i = 0; i < N_COINS; i++) {
            swapRATES[i] = IPancakeStableSwap(_swap).RATES(i);
        }
    }

    function PRECISION_MUL(address _swap) public view returns (uint256[N_COINS] memory swapPRECISION_MUL) {
        for (uint256 i = 0; i < N_COINS; i++) {
            swapPRECISION_MUL[i] = IPancakeStableSwap(_swap).PRECISION_MUL(i);
        }
    }

    function calc_coins_amount(address _swap, uint256 _amount) external view returns (uint256[N_COINS] memory) {
        uint256 total_supply = token(_swap).totalSupply();
        uint256[N_COINS] memory amounts;

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 value = (IPancakeStableSwap(_swap).balances(i) * _amount) / total_supply;
            amounts[i] = value;
        }
        return amounts;
    }

    function get_D_mem(
        address _swap,
        uint256[N_COINS] memory _balances,
        uint256 amp
    ) public view returns (uint256) {
        return get_D(_xp_mem(_swap, _balances), amp);
    }

    function get_add_liquidity_mint_amount(address _swap, uint256[N_COINS] memory amounts)
        external
        view
        returns (uint256)
    {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        uint256[N_COINS] memory fees;
        uint256 _fee = (swap.fee() * N_COINS) / (4 * (N_COINS - 1));
        uint256 amp = swap.A();

        uint256 token_supply = token(_swap).totalSupply();
        //Initial invariant
        uint256 D0;
        uint256[N_COINS] memory old_balances = balances(_swap);
        if (token_supply > 0) {
            D0 = get_D_mem(_swap, old_balances, amp);
        }
        uint256[N_COINS] memory new_balances = old_balances;

        for (uint256 i = 0; i < N_COINS; i++) {
            if (token_supply == 0) {
                require(amounts[i] > 0, "Initial deposit requires all coins");
            }
            // balances store amounts of c-tokens
            new_balances[i] = old_balances[i] + amounts[i];
        }

        // Invariant after change
        uint256 D1 = get_D_mem(_swap, new_balances, amp);
        require(D1 > D0, "D1 must be greater than D0");

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256 D2 = D1;
        if (token_supply > 0) {
            // Only account for fees if we are not the first to deposit
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 ideal_balance = (D1 * old_balances[i]) / D0;
                uint256 difference;
                if (ideal_balance > new_balances[i]) {
                    difference = ideal_balance - new_balances[i];
                } else {
                    difference = new_balances[i] - ideal_balance;
                }

                fees[i] = (_fee * difference) / FEE_DENOMINATOR;
                new_balances[i] -= fees[i];
            }
            D2 = get_D_mem(_swap, new_balances, amp);
        }

        // Calculate, how much pool tokens to mint
        uint256 mint_amount;
        if (token_supply == 0) {
            mint_amount = D1; // Take the dust if there was any
        } else {
            mint_amount = (token_supply * (D2 - D0)) / D0;
        }
        return mint_amount;
    }

    function get_add_liquidity_fee(address _swap, uint256[N_COINS] memory amounts)
        external
        view
        returns (uint256[N_COINS] memory liquidityFee)
    {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        uint256 _fee = (swap.fee() * N_COINS) / (4 * (N_COINS - 1));
        uint256 _admin_fee = swap.admin_fee();
        uint256 amp = swap.A();

        uint256 token_supply = token(_swap).totalSupply();
        //Initial invariant
        uint256 D0;
        uint256[N_COINS] memory old_balances = balances(_swap);
        if (token_supply > 0) {
            D0 = get_D_mem(_swap, old_balances, amp);
        }
        uint256[N_COINS] memory new_balances = old_balances;

        for (uint256 i = 0; i < N_COINS; i++) {
            if (token_supply == 0) {
                require(amounts[i] > 0, "Initial deposit requires all coins");
            }
            new_balances[i] = old_balances[i] + amounts[i];
        }

        // Invariant after change
        uint256 D1 = get_D_mem(_swap, new_balances, amp);
        require(D1 > D0, "D1 must be greater than D0");
        if (token_supply > 0) {
            // Only account for fees if we are not the first to deposit
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 ideal_balance = (D1 * old_balances[i]) / D0;
                uint256 difference;
                if (ideal_balance > new_balances[i]) {
                    difference = ideal_balance - new_balances[i];
                } else {
                    difference = new_balances[i] - ideal_balance;
                }
                uint256 coinFee;
                coinFee = (_fee * difference) / FEE_DENOMINATOR;
                liquidityFee[i] = ((coinFee * _admin_fee) / FEE_DENOMINATOR);
            }
        }
    }

    function get_remove_liquidity_imbalance_fee(address _swap, uint256[N_COINS] memory amounts)
        external
        view
        returns (uint256[N_COINS] memory liquidityFee)
    {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        uint256 _fee = (swap.fee() * N_COINS) / (4 * (N_COINS - 1));
        uint256 _admin_fee = swap.admin_fee();
        uint256 amp = swap.A();

        uint256[N_COINS] memory old_balances = balances(_swap);
        uint256[N_COINS] memory new_balances = old_balances;
        uint256 D0 = get_D_mem(_swap, old_balances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            new_balances[i] -= amounts[i];
        }
        uint256 D1 = get_D_mem(_swap, new_balances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 ideal_balance = (D1 * old_balances[i]) / D0;
            uint256 difference;
            if (ideal_balance > new_balances[i]) {
                difference = ideal_balance - new_balances[i];
            } else {
                difference = new_balances[i] - ideal_balance;
            }
            uint256 coinFee;
            coinFee = (_fee * difference) / FEE_DENOMINATOR;
            liquidityFee[i] = ((coinFee * _admin_fee) / FEE_DENOMINATOR);
        }
    }

    function _xp_mem(address _swap, uint256[N_COINS] memory _balances)
        public
        view
        returns (uint256[N_COINS] memory result)
    {
        result = RATES(_swap);
        for (uint256 i = 0; i < N_COINS; i++) {
            result[i] = (result[i] * _balances[i]) / PRECISION;
        }
    }

    function get_D(uint256[N_COINS] memory xp, uint256 amp) internal pure returns (uint256) {
        uint256 S;
        for (uint256 i = 0; i < N_COINS; i++) {
            S += xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 Dprev;
        uint256 D = S;
        uint256 Ann = amp * N_COINS;
        for (uint256 j = 0; j < 255; j++) {
            uint256 D_P = D;
            for (uint256 k = 0; k < N_COINS; k++) {
                D_P = (D_P * D) / (xp[k] * N_COINS); // If division by 0, this will be borked: only withdrawal will work. And that is good
            }
            Dprev = D;
            D = ((Ann * S + D_P * N_COINS) * D) / ((Ann - 1) * D + (N_COINS + 1) * D_P);
            // Equality with the precision of 1
            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    break;
                }
            } else {
                if (Dprev - D <= 1) {
                    break;
                }
            }
        }
        return D;
    }

    function get_y(
        address _swap,
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[N_COINS] memory xp_
    ) internal view returns (uint256) {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        uint256 amp = swap.A();
        uint256 D = get_D(xp_, amp);
        uint256 c = D;
        uint256 S_;
        uint256 Ann = amp * N_COINS;

        uint256 _x;
        for (uint256 k = 0; k < N_COINS; k++) {
            if (k == i) {
                _x = x;
            } else if (k != j) {
                _x = xp_[k];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D) / (Ann * N_COINS);
        uint256 b = S_ + D / Ann; // - D
        uint256 y_prev;
        uint256 y = D;

        for (uint256 m = 0; m < 255; m++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    break;
                }
            } else {
                if (y_prev - y <= 1) {
                    break;
                }
            }
        }
        return y;
    }

    function get_exchange_fee(
        address _swap,
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256 exFee, uint256 exAdminFee) {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);

        uint256[N_COINS] memory old_balances = balances(_swap);
        uint256[N_COINS] memory xp = _xp_mem(_swap, old_balances);
        uint256[N_COINS] memory rates = RATES(_swap);
        uint256 x = xp[i] + (dx * rates[i]) / PRECISION;
        uint256 y = get_y(_swap, i, j, x, xp);

        uint256 dy = xp[j] - y - 1; //  -1 just in case there were some rounding errors
        uint256 dy_fee = (dy * swap.fee()) / FEE_DENOMINATOR;

        uint256 dy_admin_fee = (dy_fee * swap.admin_fee()) / FEE_DENOMINATOR;
        dy_admin_fee = (dy_admin_fee * PRECISION) / rates[j];
        exFee = dy_fee;
        exAdminFee = dy_admin_fee;
    }

    function _xp(address _swap) internal view returns (uint256[N_COINS] memory result) {
        result = RATES(_swap);
        for (uint256 i = 0; i < N_COINS; i++) {
            result[i] = (result[i] * IPancakeStableSwap(_swap).balances(i)) / PRECISION;
        }
    }

    function get_y_D(
        uint256 A_,
        uint256 i,
        uint256[N_COINS] memory xp,
        uint256 D
    ) internal pure returns (uint256) {
        /**
        Calculate x[i] if one reduces D from being calculated for xp to D

        Done by solving quadratic equation iteratively.
        x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
        x_1**2 + b*x_1 = c

        x_1 = (x_1**2 + c) / (2*x_1 + b)
        */
        // x in the input is converted to the same price/precision
        require(i < N_COINS, "dev: i above N_COINS");
        uint256 c = D;
        uint256 S_;
        uint256 Ann = A_ * N_COINS;

        uint256 _x;
        for (uint256 k = 0; k < N_COINS; k++) {
            if (k != i) {
                _x = xp[k];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D) / (Ann * N_COINS);
        uint256 b = S_ + D / Ann;
        uint256 y_prev;
        uint256 y = D;

        for (uint256 k = 0; k < 255; k++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    break;
                }
            } else {
                if (y_prev - y <= 1) {
                    break;
                }
            }
        }
        return y;
    }

    function _calc_withdraw_one_coin(
        address _swap,
        uint256 _token_amount,
        uint256 i
    ) internal view returns (uint256, uint256) {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        uint256 amp = swap.A();
        uint256 _fee = (swap.fee() * N_COINS) / (4 * (N_COINS - 1));
        uint256[N_COINS] memory precisions = PRECISION_MUL(_swap);

        uint256[N_COINS] memory xp = _xp(_swap);

        uint256 D0 = get_D(xp, amp);
        uint256 D1 = D0 - (_token_amount * D0) / (token(_swap).totalSupply());
        uint256[N_COINS] memory xp_reduced = xp;

        uint256 new_y = get_y_D(amp, i, xp, D1);
        uint256 dy_0 = (xp[i] - new_y) / precisions[i]; // w/o fees

        for (uint256 k = 0; k < N_COINS; k++) {
            uint256 dx_expected;
            if (k == i) {
                dx_expected = (xp[k] * D1) / D0 - new_y;
            } else {
                dx_expected = xp[k] - (xp[k] * D1) / D0;
            }
            xp_reduced[k] -= (_fee * dx_expected) / FEE_DENOMINATOR;
        }
        uint256 dy = xp_reduced[i] - get_y_D(amp, i, xp_reduced, D1);
        dy = (dy - 1) / precisions[i]; // Withdraw less to account for rounding errors

        return (dy, dy_0 - dy);
    }

    function get_remove_liquidity_one_coin_fee(
        address _swap,
        uint256 _token_amount,
        uint256 i
    ) external view returns (uint256 adminFee) {
        IPancakeStableSwap swap = IPancakeStableSwap(_swap);
        (uint256 dy, uint256 dy_fee) = _calc_withdraw_one_coin(_swap, _token_amount, i);
        adminFee = (dy_fee * swap.admin_fee()) / FEE_DENOMINATOR;
    }
}
