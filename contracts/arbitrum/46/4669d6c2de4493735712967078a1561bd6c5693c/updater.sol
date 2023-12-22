// SPDX-License-Identifier: MIT

// File: @openzeppelin/contracts/utils/Address.sol

pragma solidity >=0.6.2 <0.8.0;
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
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () { }

    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
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
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
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
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
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
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
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
contract Ownable is Context {
    address payable private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address payable msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address payable) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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
    function transferOwnership(address payable newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol
pragma solidity >=0.6.0 <0.8.0;

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
abstract contract ReentrancyGuard is Ownable {
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

    constructor () {
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

// File: contracts/libs/IERC20.sol
pragma solidity >=0.4.0;

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

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
    function allowance(address _owner, address spender) external view returns (uint256);

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

contract TOKENPresale is ReentrancyGuard {
    using SafeMath for uint256;
	using SafeERC20 for IERC20;

    // Claim active
    bool public isClaimActive = false;

    uint256 public startTime;
    uint256 public endTime;

    uint256 public hardCapAmount = 40000_000_000;
    uint256 public totalDepositedBalance;
    // tokenPerUSDC 30000 => 3 token = 1 usdc
    uint256 public tokenPerUSDC = 3125;
	uint256 public totalTokensSold = 0;

    uint256 public minBuyETHAmount = 1_000_000;
    uint256 public maxBuyETHAmount = 1000_000_000;

    mapping(address => uint256) public deposits;
    mapping(address => uint256) public claimed;

    mapping(address => bool) public whiteList;
    address[] public whiteLists;
    bool public isWhiteListEnabled;

    // these variables are for vesting contributor
    uint256 public vestingFirst = 5000;
    uint256 public vestingPeriod = 1 weeks;
    uint256 public vestingEach = 1250;

	// TOKEN token
	IERC20 public TOKEN;
    IERC20 public buyToken;

    constructor(
        address _buyToken,
        address _TOKEN,
        uint256 _startTime,
        uint256 _endTime
    ) {
        buyToken = IERC20(_buyToken);
        TOKEN = IERC20(_TOKEN);
        startTime = _startTime;
        endTime = _endTime;
    }
    
    receive() payable external {
    }

    function buy(uint256 amount) public payable nonReentrant{
        require(isSaleActive(), "TOKEN: sale is not active");
        require(totalDepositedBalance.add(amount) <= hardCapAmount, "TOKEN: deposit limits reached");
        require(amount >= minBuyETHAmount, "low amount than min");
        require(deposits[msg.sender].add(amount) <= maxBuyETHAmount, "high amount than max");
        if(isWhiteListEnabled)
            require(whiteList[msg.sender], "not in whitelist");
        buyToken.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] = deposits[msg.sender].add(amount);

        uint256 tokenAmount = amount.mul(tokenPerUSDC).div(10);

        totalDepositedBalance = totalDepositedBalance.add(amount);
        totalTokensSold = totalTokensSold.add(tokenAmount);
        emit TokenBuy(msg.sender, amount);
    }

    function claimTokens() external nonReentrant {
		require(isClaimActive, "TOKEN: Claim is not active");
		require(deposits[msg.sender] > 0, "TOKEN: User should have unclaimed TOKEN tokens");

        uint256 claimableAmount = getVestedAmount(msg.sender).sub(claimed[msg.sender]);
        if(claimableAmount > 0) {
            if(claimableAmount <= TOKEN.balanceOf(address(this))) {
                TOKEN.safeTransfer(msg.sender, claimableAmount);
                claimed[msg.sender] = claimed[msg.sender] + claimableAmount;
		        emit TokenClaim(msg.sender, claimableAmount);
            }
            else {
                TOKEN.safeTransfer(msg.sender, TOKEN.balanceOf(address(this)));
                claimed[msg.sender] = claimed[msg.sender] + TOKEN.balanceOf(address(this));
                emit TokenClaim(msg.sender, TOKEN.balanceOf(address(this)));
            }
        }
	}

    function getUnclaimedAmount(address _addr) public view returns (uint256) {
        return deposits[_addr].mul(tokenPerUSDC).div(10).sub(claimed[_addr]);
    }
    
    function isSaleActive() public view returns (bool) {
        return startTime < block.timestamp && endTime > block.timestamp;
    }

    function getWhiteListLength() public view returns (uint256) {
        return whiteLists.length;
    }

    function getWhiteLists(uint256 size, uint256 cursor) public view returns (address[] memory) {
        uint256 length = size;

        if (length > whiteLists.length - cursor) {
            length = whiteLists.length - cursor;
        }

        address[] memory returnArray = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            returnArray[i] = whiteLists[cursor + i];
        }

        return returnArray;
    }

    function setSaleActive() external onlyOwner {
		startTime = block.timestamp;
	}

    function endPresale() public onlyOwner {
        endTime = block.timestamp;
    }

    function setClaimActive(bool _isClaimActive) external onlyOwner {
		isClaimActive = _isClaimActive;
	}

    function setTokenPerUSDC(uint256 _tokenPerUSDC) public onlyOwner returns (bool) {
        tokenPerUSDC = _tokenPerUSDC;
        return true;
    }

    function updateHardCapAmount(uint256 _hardCapAmount) external onlyOwner {
        hardCapAmount = _hardCapAmount;
    }

    function updateBuyAmount(uint256 _minAmount, uint256 _maxAmount) external onlyOwner {
        minBuyETHAmount = _minAmount;
        maxBuyETHAmount = _maxAmount;
    }

    function withdrawFunds() public onlyOwner {
        Address.sendValue(owner(), address(this).balance);
        buyToken.safeTransfer(owner(), buyToken.balanceOf(address(this)));
    }

    function withdrawUnsoldTOKEN() external onlyOwner {
		uint256 amount = TOKEN.balanceOf(address(this));
		TOKEN.safeTransfer(msg.sender, amount);
	}

    function recoverToken(address token) public onlyOwner {
        require(token != address(0), "Can't be zero address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    function setIsWhiteListEnabled(bool _en) public onlyOwner {
        isWhiteListEnabled = _en;
    }

    function addWhiteList(address[] calldata accounts) public onlyOwner {
        for (uint256 index = 0; index < accounts.length; index++) {
            if(whiteList[accounts[index]] == false)
                whiteLists.push(accounts[index]);
            whiteList[accounts[index]] = true;
        }
    }

    function removeWhiteList(address[] calldata accounts) public onlyOwner {
        for (uint256 index = 0; index < accounts.length; index++) {
            if(whiteList[accounts[index]]) {
                for (uint256 j = 0; j < whiteLists.length; j++) {
                    if(accounts[index] == whiteLists[j]) {
                        whiteLists[j] = whiteLists[whiteLists.length - 1];
                        break;
                    }
                }
                whiteLists.pop();
            }
            whiteList[accounts[index]] = false;
        }
    }

    function getVestedAmount(address _user) public view returns (uint256) {
        uint256 user = deposits[_user];
        if(block.timestamp < endTime) return 0;
        if(vestingPeriod == 0)
            return user.mul(tokenPerUSDC).div(10);
        uint256 vestedAmount = vestingFirst;
        vestedAmount = vestedAmount + (block.timestamp - endTime).div(vestingPeriod).mul(vestingEach);
        if(vestedAmount > 10000)
            vestedAmount = 10000;
        return vestedAmount.mul(user.mul(tokenPerUSDC).div(10)).div(10000);
    }

    function getNextClaimTime() public view returns (uint256) {
        if(vestingPeriod == 0)
            return block.timestamp;
        if(block.timestamp < endTime) return endTime;
        uint256 vestedAmount = vestingFirst;
        vestedAmount = vestedAmount + (block.timestamp - endTime).div(vestingPeriod).mul(vestingEach);
        if(vestedAmount < 10000)
            return endTime + vestingPeriod.mul(vestedAmount - vestingFirst).div(vestingEach) + vestingPeriod;
    }
    
    event TokenBuy(address user, uint256 value);
    event TokenClaim(address user, uint256 tokens);
}

contract updater is ReentrancyGuard {
    using SafeMath for uint256;
	using SafeERC20 for IERC20;
    
    mapping(address => uint256) public claimed;
    IERC20 public TOKEN;
    uint256 public tokenPerUSDC = 3125;

    TOKENPresale public presale;
    event TokenClaim(address user, uint256 tokens);

    constructor(
        address _TOKEN,
        uint256 _presale
    ) {
        TOKEN = IERC20(_TOKEN);
        presale = TOKENPresale(_presale);
    }

    function claimTokens() external nonReentrant {
		require(presale.isClaimActive(), "TOKEN: Claim is not active");
		require(presale.deposits(msg.sender) > 0, "TOKEN: User should have unclaimed TOKEN tokens");

        uint256 claimableAmount = presale.getVestedAmount(msg.sender).sub(presale.claimed(msg.sender)).sub(claimed[msg.sender]);
        if(claimableAmount > 0) {
            if(claimableAmount <= TOKEN.balanceOf(address(this))) {
                TOKEN.safeTransfer(msg.sender, claimableAmount);
                claimed[msg.sender] = claimed[msg.sender] + claimableAmount;
		        emit TokenClaim(msg.sender, claimableAmount);
            }
            else {
                TOKEN.safeTransfer(msg.sender, TOKEN.balanceOf(address(this)));
                claimed[msg.sender] = claimed[msg.sender] + TOKEN.balanceOf(address(this));
                emit TokenClaim(msg.sender, TOKEN.balanceOf(address(this)));
            }
        }
	}

    function getUnclaimedAmount(address _addr) public view returns (uint256) {
        return presale.deposits(_addr).mul(tokenPerUSDC).div(10).sub(presale.claimed(_addr)).sub(claimed[_addr]);
    }

    function deposits(address _addr) public view returns (uint256) {
        return presale.deposits(_addr);
    }

    function whiteList(address _addr) public view returns (bool) {
        return presale.whiteList(_addr);
    }

    function getNextClaimTime() public view returns (uint256) {
        if(presale.vestingPeriod() == 0)
            return block.timestamp;
        if(block.timestamp < presale.endTime()) return presale.endTime();
        uint256 vestedAmount = presale.vestingFirst();
        vestedAmount = vestedAmount + (block.timestamp - presale.endTime()).div(presale.vestingPeriod()).mul(presale.vestingEach());
        if(vestedAmount < 10000)
            return presale.endTime() + presale.vestingPeriod().mul(vestedAmount - presale.vestingFirst()).div(presale.vestingEach()) + presale.vestingPeriod();
    }

    function isSaleActive() public view returns (bool) {
        return presale.startTime() < block.timestamp && presale.endTime() > block.timestamp;
    }

    function isClaimActive() public view returns (bool) {
        return presale.isClaimActive();
    }
}