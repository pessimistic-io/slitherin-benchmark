// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

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
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
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
        require(b <= a, "SafeMath: subtraction overflow");
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
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
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
        require(b > 0, "SafeMath: division by zero");
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
        require(b > 0, "SafeMath: modulo by zero");
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
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

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
        assembly { size := extcodesize(account) }
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
        (bool success, ) = recipient.call{ value: amount }("");
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
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
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
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
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
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
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

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}



/// @title StakeARBPAD
/// @notice The stake ARBPAD contract for staking and unstaking ARBPAD
contract StakeARBPAD is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ARBPAD Contract Address
    // solhint-disable-next-line var-name-mixedcase
    IERC20 public ARBPADContract;

    // List of Stakers, helpful when fetching stakers report
    address[] public stakers;

    // APY
    uint256 public constant APY = 15;

    /**
     * @dev Struct representing Staker details
     * @param isPresent Boolean indicating whether a staker exists or not
     * @param stakedAtTimestamp Timestamp of when the user staked tokens
     * @param unstakedAtTimestamp Timestamp of when the user started unstaking the tokens
     * @param rewardRedeemedAt Timestamp of when the user last claimed the rewards
     * @param reward Total rewards earned by staking
     * @param claimedRewards Total rewards claimed by the user
     * @param unstakeAmount Amount which is under unstaking
     * @param amount Total stake amount of the user
     */
    struct Staker {
        bool isPresent;
        uint256 stakedAtTimestamp;
        uint256 unstakedAtTimestamp;
        uint256 rewardRedeemedAt;
        uint256 reward;
        uint256 claimedRewards;
        uint256 unstakeAmount;
        uint256 amount;
    }

    uint256 public totalARBPADStaked;
    mapping(address => Staker) public stakerInfo;

    event Stake(address indexed staker, uint256 amount, uint256 stakedAtTimestamp);
    event Unstake(address indexed staker, uint256 amount, uint256 unstakedAtTimestamp);
    event Withdraw(address indexed staker, uint256 amount, uint256 withdrawnAt);
    event ClaimRewards(address indexed staker, uint256 amount, uint256 redeemedAt);

    constructor(IERC20 arbpadContractAddress) {
        require(address(arbpadContractAddress) != address(0), "Cannot be address zero");
        ARBPADContract = arbpadContractAddress;
    }

    /**
     * @dev Contract might receive/hold BNB as part of the maintenance process.
     * The receive function is executed on a call to the contract with empty calldata.
     */
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @dev The fallback function is executed on a call to the contract if
     * none of the other functions match the given function signature.
     */
    fallback() external payable {}

    /**
     * @dev To claim the earned rewards
     *
     * Requirements:
     * - amount must be greater than 0
     * - ARBPAD balance of Staker must be greater than or equal to amount
     */
    function claimRewards() external {
        Staker memory _staker = stakerInfo[msg.sender];
        require(_staker.isPresent, "No rewards: not a staker");

        uint256 rewardsEarned = 0;
        if ((_staker.unstakeAmount > 0) && (_staker.rewardRedeemedAt == 0)) {
            rewardsEarned = _staker.reward.add(calculateRewards(_staker.unstakedAtTimestamp, _staker.amount));
        } else if (_staker.rewardRedeemedAt > 0) {
            rewardsEarned = _staker.reward.add(calculateRewards(_staker.rewardRedeemedAt, _staker.amount));
        } else {
            rewardsEarned = _staker.reward.add(calculateRewards(_staker.stakedAtTimestamp, _staker.amount));
        }

        _staker.rewardRedeemedAt = block.timestamp;

        require(
            ARBPADContract.balanceOf(address(this)) >= rewardsEarned,
            "claimRewards: Insufficient contract balance"
        );

        ARBPADContract.safeTransfer(msg.sender, rewardsEarned);

        _staker.reward = 0;
        _staker.claimedRewards = _staker.claimedRewards.add(rewardsEarned);
        stakerInfo[msg.sender] = _staker; // Write Staker info to contract storage

        emit ClaimRewards(msg.sender, rewardsEarned, block.timestamp); //solhint-disable-line not-rely-on-time
    }

    /**
     * @dev To stake ARBPAD in the contract
     *
     * Requirements:
     * - amount must be greater than 0
     * - ARBPAD balance of Staker must be greater than or equal to amount
     */
    function stake(uint256 amount) external {
        require(amount > 0, "Stake amount must be > 0");

        uint256 stakerARBPADBalance = ARBPADContract.balanceOf(msg.sender);
        require(stakerARBPADBalance >= amount, "stake: Insufficient user balance");

        Staker memory _staker = stakerInfo[msg.sender];
        if (!_staker.isPresent) {
            _staker.isPresent = true;
            stakers.push(msg.sender);
            //solhint-disable-next-line not-rely-on-time
            _staker.stakedAtTimestamp = block.timestamp;
        }
        /*
         * It implies a staker is again staking
         * Update total principal & keep aside the reward for the user for the first staked amount
         */
        uint256 previousStake = _staker.amount;
        if (previousStake > 0) {
            // Reward for previousStake amount
            _staker.reward = calculateRewards(_staker.stakedAtTimestamp, previousStake);
            //solhint-disable-next-line not-rely-on-time
            _staker.stakedAtTimestamp = block.timestamp;
        }

        ARBPADContract.safeTransferFrom(msg.sender, address(this), amount);

        totalARBPADStaked = totalARBPADStaked.add(amount);

        // Updates Total Stake amount
        _staker.amount = _staker.amount.add(amount);
        stakerInfo[msg.sender] = _staker; // Write Staker info to contract storage

        emit Stake(msg.sender, amount, _staker.stakedAtTimestamp);
    }

    /**
     * @dev To Unstake ARBPAD from the contract
     *
     * Requirements:
     * - Caller's staked ARBPAD must be greater than 0
     * - Unstake amount must be less than or equal to the staked ARBPAD
     * - Contract's ARBPAD balance must be greater than staked ARBPAD
     */
    function unstake(uint256 amount) external {
        require(amount > 0, "Unstake amount must be > 0");

        Staker memory _staker = stakerInfo[msg.sender];
        require(_staker.amount > 0, "No Stakes");
        require(amount <= _staker.amount, "Unstake amt > staked amt");

        _staker.unstakedAtTimestamp = block.timestamp; //solhint-disable-line not-rely-on-time

        _staker.reward = calculateRewards(_staker.unstakedAtTimestamp, (_staker.amount.sub(amount)));
        _staker.unstakeAmount = _staker.unstakeAmount.add(amount);
        _staker.amount = _staker.amount.sub(amount);

        totalARBPADStaked = totalARBPADStaked.sub(amount);

        stakerInfo[msg.sender] = _staker; // Write Staker info to contract storage

        emit Unstake(msg.sender, amount, block.timestamp); //solhint-disable-line not-rely-on-time
    }

    /**
     * @dev To claim/withdraw the unstake amount
     *
     * Requirements:
     * - amount must be greater than 0
     * - ARBPAD balance of Staker must be greater than or equal to amount
     */
    function withdraw() external {
        Staker memory _staker = stakerInfo[msg.sender];
        uint256 unstakeAmount = _staker.unstakeAmount;
        require(unstakeAmount > 0, "Unstake amount is 0");

        uint256 hoursUnstakedFor = getHoursFromTimestamp(_staker.unstakedAtTimestamp);
        // Since 24 Hours = 1 Day, therefore 5 Days = 120 Hours
        require(hoursUnstakedFor >= 168, "Cannot unstake in cooldown period");

        require(
            ARBPADContract.balanceOf(address(this)) >= unstakeAmount,
            "withdraw: Insufficient contract balance"
        );

        ARBPADContract.safeTransfer(msg.sender, unstakeAmount);

        _staker.unstakeAmount = 0;
        stakerInfo[msg.sender] = _staker; // Write Staker info to contract storage

        emit Withdraw(msg.sender, unstakeAmount, block.timestamp); //solhint-disable-line not-rely-on-time
    }

    /**
     * @dev Returns the caller's staking details
     */
    function myStakes(address _staker)
        external
        view
        returns (
            uint256 stakedARBPAD,
            uint256 hoursStakedFor,
            uint256 unstakedAtTimestamp,
            uint256 reward,
            uint256 unstakeAmount,
            uint256 claimedRewards
        )
    {
        Staker memory _staker = stakerInfo[_staker];
        stakedARBPAD = _staker.amount;
        hoursStakedFor = getHoursFromTimestamp(_staker.stakedAtTimestamp);
        unstakedAtTimestamp = _staker.unstakedAtTimestamp;
        if ((_staker.unstakeAmount > 0) && (_staker.rewardRedeemedAt == 0)) {
            reward = _staker.reward.add(calculateRewards(_staker.unstakedAtTimestamp, _staker.amount));
        } else if (_staker.rewardRedeemedAt > 0) {
            reward = _staker.reward.add(calculateRewards(_staker.rewardRedeemedAt, _staker.amount));
        } else {
            reward = _staker.reward.add(calculateRewards(_staker.stakedAtTimestamp, _staker.amount));
        }
        unstakeAmount = _staker.unstakeAmount;
        claimedRewards = _staker.claimedRewards;
    }

    /**
     * @dev Returns the total number of stakers
     */
    function totalStakers() external view returns (uint256) {
        return stakers.length;
    }

    /**
     * @dev Returns rewards earned
     */
    function earnedRewards(address staker) public view returns (uint256) {
        Staker memory _staker = stakerInfo[staker];

        if ((_staker.unstakeAmount > 0) && (_staker.rewardRedeemedAt == 0)) {
            return _staker.reward.add(calculateRewards(_staker.unstakedAtTimestamp, _staker.amount));
        } else if (_staker.rewardRedeemedAt > 0) {
            return _staker.reward.add(calculateRewards(_staker.rewardRedeemedAt, _staker.amount));
        } else {
            return _staker.reward.add(calculateRewards(_staker.stakedAtTimestamp, _staker.amount));
        }
    }

    /**
     * @dev Returns the calculated rewards
     */
    function calculateRewards(uint256 timestamp, uint256 amount) internal view returns (uint256 reward) {
        uint256 hoursStakedFor = getHoursFromTimestamp(timestamp);

        uint256 tokenPerYear = (amount.mul(APY)).div(100);
        uint256 tokenPerDay = tokenPerYear.div(365);
        uint256 tokenPerHour = tokenPerDay.div(24);

        return tokenPerHour.mul(hoursStakedFor);
    }

    /**
     * @dev Returns the number of hours for which ARBPAD was staked
     */
    function getHoursFromTimestamp(uint256 timestamp) internal view returns (uint256) {
        //solhint-disable-next-line not-rely-on-time
        return (block.timestamp - timestamp) / 1 hours;
    }
}