// Sources flattened with hardhat v2.9.3 https://hardhat.org

// File contracts/libraries/math/SafeMath.sol

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
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
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
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
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
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
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
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
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
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
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
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
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
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
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
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
        require(b != 0, errorMessage);
        return a % b;
    }
}


// File contracts/libraries/token/IERC20.sol


pragma solidity 0.6.12;

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


// File contracts/libraries/utils/Address.sol


pragma solidity ^0.6.2;

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
        // solhint-disable-next-line no-inline-assembly
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
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

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.3._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.3._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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


// File contracts/libraries/token/SafeERC20.sol


pragma solidity 0.6.12;



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
    using SafeMath for uint256;
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
        // solhint-disable-next-line max-line-length
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
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeERC20: decreased allowance below zero"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


// File contracts/libraries/utils/ReentrancyGuard.sol


pragma solidity 0.6.12;

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
contract ReentrancyGuard {
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

    constructor() internal {
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


// File contracts/staking/interfaces/IRewardTracker.sol


pragma solidity 0.6.12;

interface IRewardTracker {
    function depositBalances(address _account, address _depositToken) external view returns (uint256);

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

    function claimForAccount(address _account, address _receiver) external returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function averageStakedAmounts(address _account) external view returns (uint256);

    function cumulativeRewards(address _account) external view returns (uint256);
}


// File contracts/staking/interfaces/IVester.sol


pragma solidity 0.6.12;

interface IVester {
    function rewardTracker() external view returns (address);

    function claimForAccount(address _account, address _receiver) external returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function cumulativeClaimAmounts(address _account) external view returns (uint256);

    function claimedAmounts(address _account) external view returns (uint256);

    function pairAmounts(address _account) external view returns (uint256);

    function getVestedAmount(address _account) external view returns (uint256);

    function transferredAverageStakedAmounts(address _account) external view returns (uint256);

    function transferredCumulativeRewards(address _account) external view returns (uint256);

    function cumulativeRewardDeductions(address _account) external view returns (uint256);

    function bonusRewards(address _account) external view returns (uint256);

    function transferStakeValues(address _sender, address _receiver) external;

    function setTransferredAverageStakedAmounts(address _account, uint256 _amount) external;

    function setTransferredCumulativeRewards(address _account, uint256 _amount) external;

    function setCumulativeRewardDeductions(address _account, uint256 _amount) external;

    function setBonusRewards(address _account, uint256 _amount) external;

    function getMaxVestableAmount(address _account) external view returns (uint256);

    function getCombinedAverageStakedAmount(address _account) external view returns (uint256);
}


// File contracts/tokens/interfaces/IMintable.sol


pragma solidity 0.6.12;

interface IMintable {
    function isMinter(address _account) external returns (bool);

    function setMinter(address _minter, bool _isActive) external;

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}


// File contracts/tokens/interfaces/IWETH.sol


pragma solidity 0.6.12;

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}


// File contracts/core/interfaces/IMlpManager.sol


pragma solidity 0.6.12;

interface IMlpManager {
    function cooldownDuration() external returns (uint256);

    function lastAddedAt(address _account) external returns (uint256);

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minMlp
    ) external returns (uint256);

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minMlp
    ) external returns (uint256);

    function removeLiquidity(
        address _tokenOut,
        uint256 _mlpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _MlpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
}


// File contracts/access/Governable.sol


pragma solidity 0.6.12;

contract Governable {
    address public gov;

    constructor() public {
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


// File contracts/staking/RewardRouterV2.sol


pragma solidity 0.6.12;




contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public myc;
    address public esMyc;
    address public bnMyc;

    address public mlp; // MYC Liquidity Provider token

    address public stakedMycTracker;
    address public bonusMycTracker;
    address public feeMycTracker;

    address public stakedMlpTracker;
    address public feeMlpTracker;

    address public mlpManager;

    address public mlpVester;
    address public mycVester;

    mapping(address => address) public pendingReceivers;

    event StakeMyc(address account, address token, uint256 amount);
    event UnstakeMyc(address account, address token, uint256 amount);

    event StakeMlp(address account, uint256 amount);
    event UnstakeMlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _myc,
        address _esMyc,
        address _bnMyc,
        address _mlp,
        address _stakedMycTracker,
        address _bonusMycTracker,
        address _feeMycTracker,
        address _feeMlpTracker,
        address _stakedMlpTracker,
        address _mlpManager,
        address _mycVester,
        address _mlpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        myc = _myc;
        esMyc = _esMyc;
        bnMyc = _bnMyc;

        mlp = _mlp;

        stakedMycTracker = _stakedMycTracker;
        bonusMycTracker = _bonusMycTracker;
        feeMycTracker = _feeMycTracker;

        feeMlpTracker = _feeMlpTracker;
        stakedMlpTracker = _stakedMlpTracker;

        mlpManager = _mlpManager;

        mycVester = _mycVester;
        mlpVester = _mlpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeMycForAccount(address[] memory _accounts, uint256[] memory _amounts)
        external
        nonReentrant
        onlyGov
    {
        address _myc = myc;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeMyc(msg.sender, _accounts[i], _myc, _amounts[i]);
        }
    }

    function stakeMycForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeMyc(msg.sender, _account, myc, _amount);
    }

    function stakeMyc(uint256 _amount) external nonReentrant {
        _stakeMyc(msg.sender, msg.sender, myc, _amount);
    }

    function stakeEsMyc(uint256 _amount) external nonReentrant {
        _stakeMyc(msg.sender, msg.sender, esMyc, _amount);
    }

    function unstakeMyc(uint256 _amount) external nonReentrant {
        _unstakeMyc(msg.sender, myc, _amount, true);
    }

    function unstakeEsMyc(uint256 _amount) external nonReentrant {
        _unstakeMyc(msg.sender, esMyc, _amount, true);
    }

    function mintAndStakeMlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minMlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 mlpAmount = IMlpManager(mlpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdg,
            _minMlp
        );
        IRewardTracker(feeMlpTracker).stakeForAccount(account, account, mlp, mlpAmount);
        IRewardTracker(stakedMlpTracker).stakeForAccount(account, account, feeMlpTracker, mlpAmount);

        emit StakeMlp(account, mlpAmount);

        return mlpAmount;
    }

    function mintAndStakeMlpETH(uint256 _minUsdg, uint256 _minMlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(mlpManager, msg.value);

        address account = msg.sender;
        uint256 mlpAmount = IMlpManager(mlpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdg,
            _minMlp
        );

        IRewardTracker(feeMlpTracker).stakeForAccount(account, account, mlp, mlpAmount);
        IRewardTracker(stakedMlpTracker).stakeForAccount(account, account, feeMlpTracker, mlpAmount);

        emit StakeMlp(account, mlpAmount);

        return mlpAmount;
    }

    function unstakeAndRedeemMlp(
        address _tokenOut,
        uint256 _mlpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_mlpAmount > 0, "RewardRouter: invalid _mlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMlpTracker).unstakeForAccount(account, feeMlpTracker, _mlpAmount, account);
        IRewardTracker(feeMlpTracker).unstakeForAccount(account, mlp, _mlpAmount, account);
        uint256 amountOut = IMlpManager(mlpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _mlpAmount,
            _minOut,
            _receiver
        );

        emit UnstakeMlp(account, _mlpAmount);

        return amountOut;
    }

    function unstakeAndRedeemMlpETH(
        uint256 _mlpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_mlpAmount > 0, "RewardRouter: invalid _mlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMlpTracker).unstakeForAccount(account, feeMlpTracker, _mlpAmount, account);
        IRewardTracker(feeMlpTracker).unstakeForAccount(account, mlp, _mlpAmount, account);
        uint256 amountOut = IMlpManager(mlpManager).removeLiquidityForAccount(
            account,
            weth,
            _mlpAmount,
            _minOut,
            address(this)
        );

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeMlp(account, _mlpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMycTracker).claimForAccount(account, account);
        IRewardTracker(feeMlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedMycTracker).claimForAccount(account, account);
        IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
    }

    function claimEsMyc() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedMycTracker).claimForAccount(account, account);
        IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMycTracker).claimForAccount(account, account);
        IRewardTracker(feeMlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimMyc,
        bool _shouldStakeMyc,
        bool _shouldClaimEsMyc,
        bool _shouldStakeEsMyc,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth,
        bool _shouldBuyMlpWithWeth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 mycAmount = 0;
        if (_shouldClaimMyc) {
            uint256 mycAmount0 = IVester(mycVester).claimForAccount(account, account);
            uint256 mycAmount1 = IVester(mlpVester).claimForAccount(account, account);
            mycAmount = mycAmount0.add(mycAmount1);
        }

        if (_shouldStakeMyc && mycAmount > 0) {
            _stakeMyc(account, account, myc, mycAmount);
        }

        uint256 esMycAmount = 0;
        if (_shouldClaimEsMyc) {
            uint256 esMycAmount0 = IRewardTracker(stakedMycTracker).claimForAccount(account, account);
            uint256 esMycAmount1 = IRewardTracker(stakedMlpTracker).claimForAccount(account, account);
            esMycAmount = esMycAmount0.add(esMycAmount1);
        }

        if (_shouldStakeEsMyc && esMycAmount > 0) {
            _stakeMyc(account, account, esMyc, esMycAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnMycAmount = IRewardTracker(bonusMycTracker).claimForAccount(account, account);
            if (bnMycAmount > 0) {
                IRewardTracker(feeMycTracker).stakeForAccount(account, account, bnMyc, bnMycAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldBuyMlpWithWeth) {
                uint256 weth0 = IRewardTracker(feeMycTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeMlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);

                // claimed amount can be 0
                if (wethAmount > 0) {
                    IERC20(weth).approve(mlpManager, wethAmount);
                    uint256 mlpAmount = IMlpManager(mlpManager).addLiquidityForAccount(
                        address(this),
                        account,
                        weth,
                        wethAmount,
                        0,
                        0
                    );

                    IRewardTracker(feeMlpTracker).stakeForAccount(account, account, mlp, mlpAmount);
                    IRewardTracker(stakedMlpTracker).stakeForAccount(account, account, feeMlpTracker, mlpAmount);

                    emit StakeMlp(account, mlpAmount);
                }
            } else if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeMycTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeMlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);

                IWETH(weth).withdraw(wethAmount);
                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeMycTracker).claimForAccount(account, account);
                IRewardTracker(feeMlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(mycVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mlpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(mycVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mlpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedMyc = IRewardTracker(stakedMycTracker).depositBalances(_sender, myc);
        if (stakedMyc > 0) {
            _unstakeMyc(_sender, myc, stakedMyc, false);
            _stakeMyc(_sender, receiver, myc, stakedMyc);
        }

        uint256 stakedEsMyc = IRewardTracker(stakedMycTracker).depositBalances(_sender, esMyc);
        if (stakedEsMyc > 0) {
            _unstakeMyc(_sender, esMyc, stakedEsMyc, false);
            _stakeMyc(_sender, receiver, esMyc, stakedEsMyc);
        }

        uint256 stakedBnMyc = IRewardTracker(feeMycTracker).depositBalances(_sender, bnMyc);
        if (stakedBnMyc > 0) {
            IRewardTracker(feeMycTracker).unstakeForAccount(_sender, bnMyc, stakedBnMyc, _sender);
            IRewardTracker(feeMycTracker).stakeForAccount(_sender, receiver, bnMyc, stakedBnMyc);
        }

        uint256 esMycBalance = IERC20(esMyc).balanceOf(_sender);
        if (esMycBalance > 0) {
            IERC20(esMyc).transferFrom(_sender, receiver, esMycBalance);
        }

        uint256 mlpAmount = IRewardTracker(feeMlpTracker).depositBalances(_sender, mlp);
        if (mlpAmount > 0) {
            IRewardTracker(stakedMlpTracker).unstakeForAccount(_sender, feeMlpTracker, mlpAmount, _sender);
            IRewardTracker(feeMlpTracker).unstakeForAccount(_sender, mlp, mlpAmount, _sender);

            IRewardTracker(feeMlpTracker).stakeForAccount(_sender, receiver, mlp, mlpAmount);
            IRewardTracker(stakedMlpTracker).stakeForAccount(receiver, receiver, feeMlpTracker, mlpAmount);
        }

        IVester(mycVester).transferStakeValues(_sender, receiver);
        IVester(mlpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedMycTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: stakedMycTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedMycTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedMycTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusMycTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: bonusMycTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusMycTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusMycTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeMycTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeMycTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeMycTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeMycTracker.cumulativeRewards > 0"
        );

        require(
            IVester(mycVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: mycVester.transferredAverageStakedAmounts > 0"
        );

        require(
            IVester(mycVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: mycVester.transferredCumulativeRewards > 0"
        );
        require(
            IRewardTracker(stakedMlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: stakedMlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedMlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedMlpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeMlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeMlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeMlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeMlpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(mlpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: mlpVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(mlpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: mlpVester.transferredCumulativeRewards > 0"
        );

        require(IERC20(mycVester).balanceOf(_receiver) == 0, "RewardRouter: mycVester.balance > 0");
        require(IERC20(mlpVester).balanceOf(_receiver) == 0, "RewardRouter: mlpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundMyc(_account);
        _compoundMlp(_account);
    }

    function _compoundMyc(address _account) private {
        uint256 esMycAmount = IRewardTracker(stakedMycTracker).claimForAccount(_account, _account);
        if (esMycAmount > 0) {
            _stakeMyc(_account, _account, esMyc, esMycAmount);
        }

        uint256 bnMycAmount = IRewardTracker(bonusMycTracker).claimForAccount(_account, _account);
        if (bnMycAmount > 0) {
            IRewardTracker(feeMycTracker).stakeForAccount(_account, _account, bnMyc, bnMycAmount);
        }
    }

    function _compoundMlp(address _account) private {
        uint256 esMycAmount = IRewardTracker(stakedMlpTracker).claimForAccount(_account, _account);
        if (esMycAmount > 0) {
            _stakeMyc(_account, _account, esMyc, esMycAmount);
        }
    }

    function _stakeMyc(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedMycTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusMycTracker).stakeForAccount(_account, _account, stakedMycTracker, _amount);
        IRewardTracker(feeMycTracker).stakeForAccount(_account, _account, bonusMycTracker, _amount);

        emit StakeMyc(_account, _token, _amount);
    }

    function _unstakeMyc(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnMyc
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedMycTracker).stakedAmounts(_account);

        IRewardTracker(feeMycTracker).unstakeForAccount(_account, bonusMycTracker, _amount, _account);
        IRewardTracker(bonusMycTracker).unstakeForAccount(_account, stakedMycTracker, _amount, _account);
        IRewardTracker(stakedMycTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnMyc) {
            uint256 bnMycAmount = IRewardTracker(bonusMycTracker).claimForAccount(_account, _account);
            if (bnMycAmount > 0) {
                IRewardTracker(feeMycTracker).stakeForAccount(_account, _account, bnMyc, bnMycAmount);
            }

            uint256 stakedBnMyc = IRewardTracker(feeMycTracker).depositBalances(_account, bnMyc);
            if (stakedBnMyc > 0) {
                uint256 reductionAmount = stakedBnMyc.mul(_amount).div(balance);
                IRewardTracker(feeMycTracker).unstakeForAccount(_account, bnMyc, reductionAmount, _account);
                IMintable(bnMyc).burn(_account, reductionAmount);
            }
        }

        emit UnstakeMyc(_account, _token, _amount);
    }
}