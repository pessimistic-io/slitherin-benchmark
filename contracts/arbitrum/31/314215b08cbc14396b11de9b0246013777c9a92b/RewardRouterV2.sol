// File: Address.sol

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
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
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

// File: Governable.sol

contract Governable {
    address public gov;

    constructor() {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }
}

// File: IBlpManager.sol

interface IBlpManager {
    function provideForAccount(
        uint256 tokenXAmount,
        uint256 minMint,
        address account
    ) external returns (uint256 mint);

    function withdrawForAccount(uint256 tokenXAmount, address account)
        external
        returns (uint256 burn);

    function toTokenX(uint256 amount) external view returns (uint256);
}

// File: IERC20.sol

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
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
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

// File: IMintable.sol

interface IMintable {
    function isMinter(address _account) external returns (bool);

    function setMinter(address _minter, bool _isActive) external;

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}

// File: IRewardTracker.sol

interface IRewardTracker {
    function depositBalances(address _account, address _depositToken)
        external
        view
        returns (uint256);

    function stakedAmounts(address _account) external view returns (uint256);

    function updateRewards() external;

    function stake(address _depositToken, uint256 _amount) external;

    function stakeForAccount(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) external;

    function unstake(address _depositToken, uint256 _amount) external;

    function unstakeForAccount(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) external;

    function tokensPerInterval() external view returns (uint256);

    function claim(address _receiver) external returns (uint256);

    function claimForAccount(address _account, address _receiver)
        external
        returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function averageStakedAmounts(address _account)
        external
        view
        returns (uint256);

    function cumulativeRewards(address _account)
        external
        view
        returns (uint256);
}

// File: IVester.sol

interface IVester {
    function rewardTracker() external view returns (address);

    function claimForAccount(address _account, address _receiver)
        external
        returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function cumulativeClaimAmounts(address _account)
        external
        view
        returns (uint256);

    function claimedAmounts(address _account) external view returns (uint256);

    function pairAmounts(address _account) external view returns (uint256);

    function getVestedAmount(address _account) external view returns (uint256);

    function transferredAverageStakedAmounts(address _account)
        external
        view
        returns (uint256);

    function transferredCumulativeRewards(address _account)
        external
        view
        returns (uint256);

    function cumulativeRewardDeductions(address _account)
        external
        view
        returns (uint256);

    function bonusRewards(address _account) external view returns (uint256);

    function transferStakeValues(address _sender, address _receiver) external;

    function setTransferredAverageStakedAmounts(
        address _account,
        uint256 _amount
    ) external;

    function setTransferredCumulativeRewards(address _account, uint256 _amount)
        external;

    function setCumulativeRewardDeductions(address _account, uint256 _amount)
        external;

    function setBonusRewards(address _account, uint256 _amount) external;

    function getMaxVestableAmount(address _account)
        external
        view
        returns (uint256);

    function getCombinedAverageStakedAmount(address _account)
        external
        view
        returns (uint256);
}

// File: ReentrancyGuard.sol

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: SafeMath.sol

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// File: SafeERC20.sol

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

// File: RewardRouterV2.sol

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public usdc;

    address public bfr;
    address public esBfr;
    address public bnBfr;

    address public blp; // BFR Liquidity Provider token

    address public stakedBfrTracker;
    address public bonusBfrTracker;
    address public feeBfrTracker;

    address public stakedBlpTracker;
    address public feeBlpTracker;

    address public blpManager;

    address public bfrVester;
    address public blpVester;

    mapping(address => address) public pendingReceivers;

    event StakeBfr(address account, address token, uint256 amount);
    event UnstakeBfr(address account, address token, uint256 amount);

    event StakeBlp(address account, uint256 amount);
    event UnstakeBlp(address account, uint256 amount);

    receive() external payable {
        revert("Router: Can't receive eth");
    }

    function initialize(
        address _usdc,
        address _bfr,
        address _esBfr,
        address _bnBfr,
        address _blp,
        address _stakedBfrTracker,
        address _bonusBfrTracker,
        address _feeBfrTracker,
        address _feeBlpTracker,
        address _stakedBlpTracker,
        address _bfrVester,
        address _blpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        usdc = _usdc;

        bfr = _bfr;
        esBfr = _esBfr;
        bnBfr = _bnBfr;

        blp = _blp;

        stakedBfrTracker = _stakedBfrTracker;
        bonusBfrTracker = _bonusBfrTracker;
        feeBfrTracker = _feeBfrTracker;

        feeBlpTracker = _feeBlpTracker;
        stakedBlpTracker = _stakedBlpTracker;

        blpManager = _blp;

        bfrVester = _bfrVester;
        blpVester = _blpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeBfrForAccount(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyGov {
        address _bfr = bfr;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeBfr(msg.sender, _accounts[i], _bfr, _amounts[i]);
        }
    }

    function stakeBfrForAccount(address _account, uint256 _amount)
        external
        nonReentrant
        onlyGov
    {
        _stakeBfr(msg.sender, _account, bfr, _amount);
    }

    function stakeBfr(uint256 _amount) external nonReentrant {
        _stakeBfr(msg.sender, msg.sender, bfr, _amount);
    }

    function stakeEsBfr(uint256 _amount) external nonReentrant {
        _stakeBfr(msg.sender, msg.sender, esBfr, _amount);
    }

    function unstakeBfr(uint256 _amount) external nonReentrant {
        _unstakeBfr(msg.sender, bfr, _amount, true);
    }

    function unstakeEsBfr(uint256 _amount) external nonReentrant {
        _unstakeBfr(msg.sender, esBfr, _amount, true);
    }

    function mintAndStakeBlp(
        uint256 _amount,
        uint256 _minBlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 blpAmount = IBlpManager(blpManager).provideForAccount(
            _amount,
            _minBlp,
            account
        );
        IRewardTracker(feeBlpTracker).stakeForAccount(
            account,
            account,
            blp,
            blpAmount
        );
        IRewardTracker(stakedBlpTracker).stakeForAccount(
            account,
            account,
            feeBlpTracker,
            blpAmount
        );

        emit StakeBlp(account, blpAmount);

        return blpAmount;
    }

    function unstakeAndRedeemBlp(uint256 _blpAmount)
        external
        nonReentrant
        returns (uint256)
    {
        require(_blpAmount > 0, "RewardRouter: invalid _blpAmount");

        address account = msg.sender;
        IRewardTracker(stakedBlpTracker).unstakeForAccount(
            account,
            feeBlpTracker,
            _blpAmount,
            account
        );
        IRewardTracker(feeBlpTracker).unstakeForAccount(
            account,
            blp,
            _blpAmount,
            account
        );
        uint256 amountOut = IBlpManager(blpManager).withdrawForAccount(
            IBlpManager(blpManager).toTokenX(_blpAmount),
            account
        );

        emit UnstakeBlp(account, _blpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeBfrTracker).claimForAccount(account, account);
        IRewardTracker(feeBlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedBfrTracker).claimForAccount(account, account);
        IRewardTracker(stakedBlpTracker).claimForAccount(account, account);
    }

    function claimEsBfr() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedBfrTracker).claimForAccount(account, account);
        IRewardTracker(stakedBlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeBfrTracker).claimForAccount(account, account);
        IRewardTracker(feeBlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account)
        external
        nonReentrant
        onlyGov
    {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimBfr,
        bool _shouldStakeBfr,
        bool _shouldClaimEsBfr,
        bool _shouldStakeEsBfr,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimUsdc
    ) external nonReentrant {
        address account = msg.sender;

        uint256 bfrAmount = 0;
        if (_shouldClaimBfr) {
            uint256 bfrAmount0 = IVester(bfrVester).claimForAccount(
                account,
                account
            );
            uint256 bfrAmount1 = IVester(blpVester).claimForAccount(
                account,
                account
            );
            bfrAmount = bfrAmount0.add(bfrAmount1);
        }

        if (_shouldStakeBfr && bfrAmount > 0) {
            _stakeBfr(account, account, bfr, bfrAmount);
        }

        uint256 esBfrAmount = 0;
        if (_shouldClaimEsBfr) {
            uint256 esBfrAmount0 = IRewardTracker(stakedBfrTracker)
                .claimForAccount(account, account);
            uint256 esBfrAmount1 = IRewardTracker(stakedBlpTracker)
                .claimForAccount(account, account);
            esBfrAmount = esBfrAmount0.add(esBfrAmount1);
        }

        if (_shouldStakeEsBfr && esBfrAmount > 0) {
            _stakeBfr(account, account, esBfr, esBfrAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker)
                .claimForAccount(account, account);
            if (bnBfrAmount > 0) {
                IRewardTracker(feeBfrTracker).stakeForAccount(
                    account,
                    account,
                    bnBfr,
                    bnBfrAmount
                );
            }
        }

        if (_shouldClaimUsdc) {
            IRewardTracker(feeBfrTracker).claimForAccount(account, account);
            IRewardTracker(feeBlpTracker).claimForAccount(account, account);
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts)
        external
        nonReentrant
        onlyGov
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(
            IERC20(bfrVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(blpVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(
            IERC20(bfrVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(blpVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        address receiver = msg.sender;
        require(
            pendingReceivers[_sender] == receiver,
            "RewardRouter: transfer not signalled"
        );
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedBfr = IRewardTracker(stakedBfrTracker).depositBalances(
            _sender,
            bfr
        );
        if (stakedBfr > 0) {
            _unstakeBfr(_sender, bfr, stakedBfr, false);
            _stakeBfr(_sender, receiver, bfr, stakedBfr);
        }

        uint256 stakedEsBfr = IRewardTracker(stakedBfrTracker).depositBalances(
            _sender,
            esBfr
        );
        if (stakedEsBfr > 0) {
            _unstakeBfr(_sender, esBfr, stakedEsBfr, false);
            _stakeBfr(_sender, receiver, esBfr, stakedEsBfr);
        }

        uint256 stakedBnBfr = IRewardTracker(feeBfrTracker).depositBalances(
            _sender,
            bnBfr
        );
        if (stakedBnBfr > 0) {
            IRewardTracker(feeBfrTracker).unstakeForAccount(
                _sender,
                bnBfr,
                stakedBnBfr,
                _sender
            );
            IRewardTracker(feeBfrTracker).stakeForAccount(
                _sender,
                receiver,
                bnBfr,
                stakedBnBfr
            );
        }

        uint256 esBfrBalance = IERC20(esBfr).balanceOf(_sender);
        if (esBfrBalance > 0) {
            IERC20(esBfr).transferFrom(_sender, receiver, esBfrBalance);
        }

        uint256 blpAmount = IRewardTracker(feeBlpTracker).depositBalances(
            _sender,
            blp
        );
        if (blpAmount > 0) {
            IRewardTracker(stakedBlpTracker).unstakeForAccount(
                _sender,
                feeBlpTracker,
                blpAmount,
                _sender
            );
            IRewardTracker(feeBlpTracker).unstakeForAccount(
                _sender,
                blp,
                blpAmount,
                _sender
            );

            IRewardTracker(feeBlpTracker).stakeForAccount(
                _sender,
                receiver,
                blp,
                blpAmount
            );
            IRewardTracker(stakedBlpTracker).stakeForAccount(
                receiver,
                receiver,
                feeBlpTracker,
                blpAmount
            );
        }

        IVester(bfrVester).transferStakeValues(_sender, receiver);
        IVester(blpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedBfrTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedBfrTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusBfrTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: bonusBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusBfrTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeBfrTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeBfrTracker.cumulativeRewards > 0"
        );

        require(
            IVester(bfrVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: bfrVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(bfrVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: bfrVester.transferredCumulativeRewards > 0"
        );

        require(
            IRewardTracker(stakedBlpTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedBlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedBlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedBlpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeBlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeBlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeBlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeBlpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(blpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: bfrVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(blpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: bfrVester.transferredCumulativeRewards > 0"
        );

        require(
            IERC20(bfrVester).balanceOf(_receiver) == 0,
            "RewardRouter: bfrVester.balance > 0"
        );
        require(
            IERC20(blpVester).balanceOf(_receiver) == 0,
            "RewardRouter: blpVester.balance > 0"
        );
    }

    function _compound(address _account) private {
        _compoundBfr(_account);
        _compoundBlp(_account);
    }

    function _compoundBfr(address _account) private {
        uint256 esBfrAmount = IRewardTracker(stakedBfrTracker).claimForAccount(
            _account,
            _account
        );
        if (esBfrAmount > 0) {
            _stakeBfr(_account, _account, esBfr, esBfrAmount);
        }

        uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker).claimForAccount(
            _account,
            _account
        );
        if (bnBfrAmount > 0) {
            IRewardTracker(feeBfrTracker).stakeForAccount(
                _account,
                _account,
                bnBfr,
                bnBfrAmount
            );
        }
    }

    function _compoundBlp(address _account) private {
        uint256 esBfrAmount = IRewardTracker(stakedBlpTracker).claimForAccount(
            _account,
            _account
        );
        if (esBfrAmount > 0) {
            _stakeBfr(_account, _account, esBfr, esBfrAmount);
        }
    }

    function _stakeBfr(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedBfrTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusBfrTracker).stakeForAccount(
            _account,
            _account,
            stakedBfrTracker,
            _amount
        );
        IRewardTracker(feeBfrTracker).stakeForAccount(
            _account,
            _account,
            bonusBfrTracker,
            _amount
        );

        emit StakeBfr(_account, _token, _amount);
    }

    function _unstakeBfr(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnBfr
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedBfrTracker).stakedAmounts(
            _account
        );

        IRewardTracker(feeBfrTracker).unstakeForAccount(
            _account,
            bonusBfrTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusBfrTracker).unstakeForAccount(
            _account,
            stakedBfrTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedBfrTracker).unstakeForAccount(
            _account,
            _token,
            _amount,
            _account
        );

        if (_shouldReduceBnBfr) {
            uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker)
                .claimForAccount(_account, _account);
            if (bnBfrAmount > 0) {
                IRewardTracker(feeBfrTracker).stakeForAccount(
                    _account,
                    _account,
                    bnBfr,
                    bnBfrAmount
                );
            }

            uint256 stakedBnBfr = IRewardTracker(feeBfrTracker).depositBalances(
                _account,
                bnBfr
            );
            if (stakedBnBfr > 0) {
                uint256 reductionAmount = stakedBnBfr.mul(_amount).div(balance);
                IRewardTracker(feeBfrTracker).unstakeForAccount(
                    _account,
                    bnBfr,
                    reductionAmount,
                    _account
                );
                IMintable(bnBfr).burn(_account, reductionAmount);
            }
        }

        emit UnstakeBfr(_account, _token, _amount);
    }
}