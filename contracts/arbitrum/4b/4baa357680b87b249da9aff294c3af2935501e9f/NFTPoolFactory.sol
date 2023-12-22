// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts may inherit from this and call {_registerInterface} to declare
 * their support of an interface.
 */
abstract contract ERC165 is IERC165 {
    /*
     * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    /**
     * @dev Mapping of interface ids to whether or not it's supported.
     */
    mapping(bytes4 => bool) private _supportedInterfaces;

    constructor() internal {
        // Derived contracts need only register support for their own interfaces,
        // we register support for ERC165 itself here
        _registerInterface(_INTERFACE_ID_ERC165);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     *
     * Time complexity O(1), guaranteed to always use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    /**
     * @dev Registers the contract as an implementer of the interface defined by
     * `interfaceId`. Support of the actual ERC165 interface is automatic and
     * registering its interface id is not required.
     *
     * See {IERC165-supportsInterface}.
     *
     * Requirements:
     *
     * - `interfaceId` cannot be the ERC165 invalid interface (`0xffffffff`).
     */
    function _registerInterface(bytes4 interfaceId) internal virtual {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
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
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
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

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
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
 * @dev Library for managing an enumerable variant of Solidity's
 * https://solidity.readthedocs.io/en/latest/types.html#mapping-types[`mapping`]
 * type.
 *
 * Maps have the following properties:
 *
 * - Entries are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableMap for EnumerableMap.UintToAddressMap;
 *
 *     // Declare a set state variable
 *     EnumerableMap.UintToAddressMap private myMap;
 * }
 * ```
 *
 * As of v3.0.0, only maps of type `uint256 -> address` (`UintToAddressMap`) are
 * supported.
 */
library EnumerableMap {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Map type with
    // bytes32 keys and values.
    // The Map implementation uses private functions, and user-facing
    // implementations (such as Uint256ToAddressMap) are just wrappers around
    // the underlying Map.
    // This means that we can only create new EnumerableMaps for types that fit
    // in bytes32.

    struct MapEntry {
        bytes32 _key;
        bytes32 _value;
    }

    struct Map {
        // Storage of map keys and values
        MapEntry[] _entries;
        // Position of the entry defined by a key in the `entries` array, plus 1
        // because index 0 means a key is not in the map.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function _set(Map storage map, bytes32 key, bytes32 value) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex == 0) {
            // Equivalent to !contains(map, key)
            map._entries.push(MapEntry({ _key: key, _value: value }));
            // The entry is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            map._indexes[key] = map._entries.length;
            return true;
        } else {
            map._entries[keyIndex - 1]._value = value;
            return false;
        }
    }

    /**
     * @dev Removes a key-value pair from a map. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function _remove(Map storage map, bytes32 key) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex != 0) {
            // Equivalent to contains(map, key)
            // To delete a key-value pair from the _entries array in O(1), we swap the entry to delete with the last one
            // in the array, and then remove the last entry (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = keyIndex - 1;
            uint256 lastIndex = map._entries.length - 1;

            // When the entry to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            MapEntry storage lastEntry = map._entries[lastIndex];

            // Move the last entry to the index where the entry to delete is
            map._entries[toDeleteIndex] = lastEntry;
            // Update the index for the moved entry
            map._indexes[lastEntry._key] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved entry was stored
            map._entries.pop();

            // Delete the index for the deleted slot
            delete map._indexes[key];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function _contains(Map storage map, bytes32 key) private view returns (bool) {
        return map._indexes[key] != 0;
    }

    /**
     * @dev Returns the number of key-value pairs in the map. O(1).
     */
    function _length(Map storage map) private view returns (uint256) {
        return map._entries.length;
    }

    /**
     * @dev Returns the key-value pair stored at position `index` in the map. O(1).
     *
     * Note that there are no guarantees on the ordering of entries inside the
     * array, and it may change when more entries are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Map storage map, uint256 index) private view returns (bytes32, bytes32) {
        require(map._entries.length > index, "EnumerableMap: index out of bounds");

        MapEntry storage entry = map._entries[index];
        return (entry._key, entry._value);
    }

    /**
     * @dev Tries to returns the value associated with `key`.  O(1).
     * Does not revert if `key` is not in the map.
     */
    function _tryGet(Map storage map, bytes32 key) private view returns (bool, bytes32) {
        uint256 keyIndex = map._indexes[key];
        if (keyIndex == 0) return (false, 0); // Equivalent to contains(map, key)
        return (true, map._entries[keyIndex - 1]._value); // All indexes are 1-based
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function _get(Map storage map, bytes32 key) private view returns (bytes32) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, "EnumerableMap: nonexistent key"); // Equivalent to contains(map, key)
        return map._entries[keyIndex - 1]._value; // All indexes are 1-based
    }

    /**
     * @dev Same as {_get}, with a custom error message when `key` is not in the map.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {_tryGet}.
     */
    function _get(Map storage map, bytes32 key, string memory errorMessage) private view returns (bytes32) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, errorMessage); // Equivalent to contains(map, key)
        return map._entries[keyIndex - 1]._value; // All indexes are 1-based
    }

    // UintToAddressMap

    struct UintToAddressMap {
        Map _inner;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function set(UintToAddressMap storage map, uint256 key, address value) internal returns (bool) {
        return _set(map._inner, bytes32(key), bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function remove(UintToAddressMap storage map, uint256 key) internal returns (bool) {
        return _remove(map._inner, bytes32(key));
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function contains(UintToAddressMap storage map, uint256 key) internal view returns (bool) {
        return _contains(map._inner, bytes32(key));
    }

    /**
     * @dev Returns the number of elements in the map. O(1).
     */
    function length(UintToAddressMap storage map) internal view returns (uint256) {
        return _length(map._inner);
    }

    /**
     * @dev Returns the element stored at position `index` in the set. O(1).
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintToAddressMap storage map, uint256 index) internal view returns (uint256, address) {
        (bytes32 key, bytes32 value) = _at(map._inner, index);
        return (uint256(key), address(uint160(uint256(value))));
    }

    /**
     * @dev Tries to returns the value associated with `key`.  O(1).
     * Does not revert if `key` is not in the map.
     *
     * _Available since v3.4._
     */
    function tryGet(UintToAddressMap storage map, uint256 key) internal view returns (bool, address) {
        (bool success, bytes32 value) = _tryGet(map._inner, bytes32(key));
        return (success, address(uint160(uint256(value))));
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function get(UintToAddressMap storage map, uint256 key) internal view returns (address) {
        return address(uint160(uint256(_get(map._inner, bytes32(key)))));
    }

    /**
     * @dev Same as {get}, with a custom error message when `key` is not in the map.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryGet}.
     */
    function get(
        UintToAddressMap storage map,
        uint256 key,
        string memory errorMessage
    ) internal view returns (address) {
        return address(uint160(uint256(_get(map._inner, bytes32(key), errorMessage))));
    }
}

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

/**
 * @dev String operations.
 */
library Strings {
    /**
     * @dev Converts a `uint256` to its ASCII `string` representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + (temp % 10)));
            temp /= 10;
        }
        return string(buffer);
    }
}

/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 * @dev see https://eips.ethereum.org/EIPS/eip-721
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata, IERC721Enumerable {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using Strings for uint256;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping(address => EnumerableSet.UintSet) private _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMap.UintToAddressMap private _tokenOwners;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // Base URI
    string private _baseURI;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c5 ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

    /*
     *     bytes4(keccak256('totalSupply()')) == 0x18160ddd
     *     bytes4(keccak256('tokenOfOwnerByIndex(address,uint256)')) == 0x2f745c59
     *     bytes4(keccak256('tokenByIndex(uint256)')) == 0x4f6ccce7
     *
     *     => 0x18160ddd ^ 0x2f745c59 ^ 0x4f6ccce7 == 0x780e9d63
     */
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _holderTokens[owner].length();
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        return _tokenOwners.get(tokenId, "ERC721: owner query for nonexistent token");
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, tokenId.toString()));
    }

    /**
     * @dev Returns the base URI set via {_setBaseURI}. This will be
     * automatically added as a prefix in {tokenURI} to each token's URI, or
     * to the token ID if no specific URI is set for that token ID.
     */
    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        return _holderTokens[owner].at(index);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || ERC721.isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _tokenOwners.contains(tokenId);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || ERC721.isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     d*
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId); // internal owner

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        _holderTokens[owner].remove(tokenId);

        _tokenOwners.remove(tokenId);

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own"); // internal owner
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Internal function to set the base URI for all token IDs. It is
     * automatically added as a prefix to the value returned in {tokenURI},
     * or to the token ID if {tokenURI} is empty.
     */
    function _setBaseURI(string memory baseURI_) internal virtual {
        _baseURI = baseURI_;
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(
            abi.encodeWithSelector(IERC721Receiver(to).onERC721Received.selector, _msgSender(), from, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId); // internal owner
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}
}

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 * Since it is not possible to overflow a 256 bit integer with increments of one, `increment` can skip the {SafeMath}
 * overflow check, thereby saving gas. This does assume however correct usage, in that the underlying `_value` is never
 * directly accessed.
 */
library Counters {
    using SafeMath for uint256;

    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        // The {SafeMath} overflow check can be skipped here, see the comment at the top
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

interface INFTHandler is IERC721Receiver {
    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xTokenAmount
    ) external returns (bool);

    function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);

    function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
}

interface INFTPool is IERC721 {
    function exists(uint256 tokenId) external view returns (bool);

    function hasDeposits() external view returns (bool);

    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address protocolToken,
            address sbtToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );

    function getStakingPosition(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    function boost(uint256 userAddress, uint256 amount) external;

    function unboost(uint256 userAddress, uint256 amount) external;
}

interface IXToken is IERC20 {
    function usageAllocations(address userAddress, address usageAddress) external view returns (uint256 allocation);

    function allocateFromUsage(address userAddress, uint256 amount) external;

    function convertTo(uint256 amount, address to) external;

    function deallocateFromUsage(address userAddress, uint256 amount) external;

    function isTransferWhitelisted(address account) external view returns (bool);
}

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

interface IMasterChef {
    function protocolToken() external view returns (address);

    function yieldBooster() external view returns (address);

    function emergencyUnlock() external view returns (bool);

    function getPoolInfo(
        address _poolAddress
    )
        external
        view
        returns (
            address poolAddress,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 poolEmissionRate
        );

    function claimRewards() external returns (uint256 rewardAmount);

    function isAdmin(address) external view returns (bool);

    function isOperator(address) external view returns (bool);

    function owner() external view returns (address);
}

interface ISinglePoolRewardManager {
    function pendingAdditionalRewards(
        uint256 tokenId,
        uint256 positionAmountMultiplied,
        uint256 lpSupplyWithMultiplier,
        uint256 lastRewardTime
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts);

    function updateRewardsPerShare(uint256 lpSupplyMultiplied, uint256 lastRewardTime) external;

    function updatePositionRewardDebts(uint256 positionAmountMultiplied, uint256 tokenId) external;

    function harvestAdditionalRewards(uint256 positionAmountMultiplied, address to, uint256 tokenId) external;

    function addRewardToken(address token, uint256 sharesPerSecond) external;
}

interface IYieldBooster {
    function deallocateAllFromPool(address userAddress, uint256 tokenId) external;

    function getMultiplier(
        address poolAddress,
        uint256 maxBoostMultiplier,
        uint256 amount,
        uint256 totalPoolSupply,
        uint256 allocatedAmount
    ) external view returns (uint256);
}

/*
 * This contract wraps ERC20 assets into non-fungible staking positions called spNFTs
 * spNFTs add the possibility to create an additional layer on liquidity providing lock features
 * spNFTs are yield-generating positions when the NFTPool contract has allocations from the MasterChef
 */
contract NFTPool is ReentrancyGuard, INFTPool, ERC721("Staking position NFT", "spNFT") {
    using Address for address;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each NFT (staked position).
    struct StakingPosition {
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 startLockTime; // The time at which the user made his deposit
        uint256 lockDuration; // The lock duration in seconds
        uint256 lockMultiplier; // Active lock multiplier (times 1e2)
        uint256 rewardDebt; // Reward debt
        uint256 boostPoints; // Allocated xToken from yieldboost contract (optional)
        uint256 totalMultiplier; // lockMultiplier + allocated xToken boostPoints multiplier
        uint256 pendingXTokenRewards; // Not harvested xToken rewards
        uint256 pendingProtocolTokenRewards; // Not harvested ProtocolToken rewards
    }

    Counters.Counter private _tokenIds;

    EnumerableSet.AddressSet private _unlockOperators; // Addresses allowed to forcibly unlock locked spNFTs
    address public operator; // Used to delegate multiplier settings to project's owners
    IMasterChef public master; // Address of the master
    address public immutable factory; // NFTPoolFactory contract's address
    bool public initialized;

    IERC20 private _lpToken; // Deposit token contract's address
    IERC20 private _protocolToken; // ProtocolToken contract's address
    IXToken private _xToken; // XToken contract's address
    ISinglePoolRewardManager public rewardManager;

    uint256 private _lpSupply; // Sum of deposit tokens on this pool
    uint256 private _lpSupplyWithMultiplier; // Sum of deposit token on this pool including the user's total multiplier (lockMultiplier + boostPoints)
    uint256 private _accRewardsPerShare; // Accumulated Rewards (staked token) per share, times 1e18. See below

    // readable via getMultiplierSettings
    uint256 public constant MAX_GLOBAL_MULTIPLIER_LIMIT = 25000; // 250%, high limit for maxGlobalMultiplier (100 = 1%)
    uint256 public constant MAX_LOCK_MULTIPLIER_LIMIT = 15000; // 150%, high limit for maxLockMultiplier (100 = 1%)
    uint256 public constant MAX_BOOST_MULTIPLIER_LIMIT = 15000; // 150%, high limit for maxBoostMultiplier (100 = 1%)
    uint256 private _maxGlobalMultiplier = 20000; // 200%
    uint256 private _maxLockDuration = 183 days; // 6 months, Capped lock duration to have the maximum bonus lockMultiplier
    uint256 private _maxLockMultiplier = 10000; // 100%, Max available lockMultiplier (100 = 1%)
    uint256 private _maxBoostMultiplier = 10000; // 100%, Max boost that can be earned from xToken yieldBooster

    uint256 private constant _TOTAL_REWARDS_SHARES = 10000; // 100%, high limit for xTokenRewardsShare
    uint256 public xTokenRewardsShare = 8000; // 80%, directly defines protocolTokenShare with the remaining value to 100%

    bool public emergencyUnlock; // Release all locks in case of emergency
    bool public additionalRewardsEnabled; // When the reward manager is set this allows additional reward checks to happen

    // readable via getStakingPosition
    mapping(uint256 => StakingPosition) internal _stakingPositions; // Info of each NFT position that stakes LP tokens

    constructor() {
        factory = msg.sender;
    }

    function initialize(IMasterChef master_, IERC20 protocolToken, IXToken xToken, IERC20 lpToken) external {
        require(msg.sender == factory && !initialized, "FORBIDDEN");
        _lpToken = lpToken;
        master = master_;
        _protocolToken = protocolToken;
        _xToken = xToken;
        initialized = true;

        // to convert ProtocolToken to xToken variant
        _protocolToken.approve(address(_xToken), type(uint256).max);
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event AddToPosition(uint256 indexed tokenId, address user, uint256 amount);
    event CreatePosition(uint256 indexed tokenId, uint256 amount, uint256 lockDuration);
    event WithdrawFromPosition(uint256 indexed tokenId, uint256 amount);
    event EmergencyWithdraw(uint256 indexed tokenId, uint256 amount);
    event LockPosition(uint256 indexed tokenId, uint256 lockDuration);
    event SplitPosition(uint256 indexed tokenId, uint256 splitAmount, uint256 newTokenId);
    event MergePositions(address indexed user, uint256[] tokenIds);
    event HarvestPosition(uint256 indexed tokenId, address to, uint256 pending);
    event SetBoost(uint256 indexed tokenId, uint256 boostPoints);

    event PoolUpdated(uint256 lastRewardTime, uint256 accRewardsPerShare);

    event SetLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier);
    event SetBoostMultiplierSettings(uint256 maxGlobalMultiplier, uint256 maxBoostMultiplier);
    event SetXTokenRewardsShare(uint256 xTokenRewardsShare);
    event SetUnlockOperator(address operator, bool isAdded);
    event SetEmergencyUnlock(bool emergencyUnlock);
    event SetOperator(address operator);
    event SetRewardManager(address manager);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check if caller has operator rights
     * To protect users certain settings can only be updated by the protocol
     */
    function _requireOnlyOwner() internal view {
        require(msg.sender == master.owner(), "FORBIDDEN");
    }

    function _requireOnlyOperator() internal view {
        require(master.isOperator(msg.sender), "FORBIDDEN");
    }

    /**
     * @dev Check if caller is a validated YieldBooster contract
     */
    function _requireOnlyYieldBooster() internal view {
        require(msg.sender == yieldBooster(), "FORBIDDEN");
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyOperatorOrOwnerOf(uint256 tokenId) internal view {
        require(ERC721._isApprovedOrOwner(msg.sender, tokenId), "FORBIDDEN");
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyApprovedOrOwnerOf(uint256 tokenId) internal view {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        require(_isOwnerOf(msg.sender, tokenId) || getApproved(tokenId) == msg.sender, "FORBIDDEN");
    }

    /**
     * @dev Check if a msg.sender is owner of a spNFT
     */
    function _requireOnlyOwnerOf(uint256 tokenId) internal view {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        // onlyOwnerOf: caller has no rights on token
        require(_isOwnerOf(msg.sender, tokenId), "not owner");
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Returns this contract's owner (= master contract's owner)
     */
    function owner() public view returns (address) {
        return master.owner();
    }

    /**
     * @dev Get master-defined yield booster contract address
     */
    function yieldBooster() public view returns (address) {
        return master.yieldBooster();
    }

    /**
     * @dev Returns true if "tokenId" is an existing spNFT id
     */
    function exists(uint256 tokenId) external view override returns (bool) {
        return ERC721._exists(tokenId);
    }

    /**
     * @dev Returns last minted NFT id
     */
    function lastTokenId() external view returns (uint256) {
        return _tokenIds.current();
    }

    /**
     * @dev Returns true if emergency unlocks are activated on this pool or on the master
     */
    function isUnlocked() public view returns (bool) {
        return emergencyUnlock || master.emergencyUnlock();
    }

    /**
     * @dev Returns true if this pool currently has deposits
     */
    function hasDeposits() external view override returns (bool) {
        return _lpSupplyWithMultiplier > 0;
    }

    /**
     * @dev Returns general "pool" info for this contract
     */
    function getPoolInfo()
        external
        view
        override
        returns (
            address lpToken,
            address protocolToken,
            address xTokenToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        )
    {
        (, allocPoint, lastRewardTime, , ) = master.getPoolInfo(address(this));
        return (
            address(_lpToken),
            address(_protocolToken),
            address(_xToken),
            lastRewardTime,
            _accRewardsPerShare,
            _lpSupply,
            _lpSupplyWithMultiplier,
            allocPoint
        );
    }

    /**
     * @dev Returns all multiplier settings for this contract
     */
    function getMultiplierSettings()
        external
        view
        returns (
            uint256 maxGlobalMultiplier,
            uint256 maxLockDuration,
            uint256 maxLockMultiplier,
            uint256 maxBoostMultiplier
        )
    {
        return (_maxGlobalMultiplier, _maxLockDuration, _maxLockMultiplier, _maxBoostMultiplier);
    }

    /**
     * @dev Returns bonus multiplier from YieldBooster contract for given "amount" (LP token staked) and "boostPoints" (result is *1e4)
     */
    function getMultiplierByBoostPoints(uint256 amount, uint256 boostPoints) public view returns (uint256) {
        if (boostPoints == 0 || amount == 0) return 0;

        address yieldBoosterAddress = yieldBooster();
        // only call yieldBooster contract if defined on master
        return
            yieldBoosterAddress != address(0)
                ? IYieldBooster(yieldBoosterAddress).getMultiplier(
                    address(this),
                    _maxBoostMultiplier,
                    amount,
                    _lpSupply,
                    boostPoints
                )
                : 0;
    }

    /**
     * @dev Returns expected multiplier for a "lockDuration" duration lock (result is *1e4)
     */
    function getMultiplierByLockDuration(uint256 lockDuration) public view returns (uint256) {
        // in case of emergency unlock
        if (isUnlocked()) return 0;

        if (_maxLockDuration == 0 || lockDuration == 0) return 0;

        // capped to maxLockDuration
        if (lockDuration >= _maxLockDuration) return _maxLockMultiplier;

        return _maxLockMultiplier.mul(lockDuration).div(_maxLockDuration);
    }

    /**
     * @dev Returns a position info
     */
    function getStakingPosition(
        uint256 tokenId
    )
        external
        view
        override
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        )
    {
        StakingPosition storage position = _stakingPositions[tokenId];
        return (
            position.amount,
            position.amountWithMultiplier,
            position.startLockTime,
            position.lockDuration,
            position.lockMultiplier,
            position.rewardDebt,
            position.boostPoints,
            position.totalMultiplier
        );
    }

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId) external view returns (uint256) {
        StakingPosition storage position = _stakingPositions[tokenId];

        uint256 accRewardsPerShare = _accRewardsPerShare;
        (, , uint256 lastRewardTime, uint256 reserve, uint256 poolEmissionRate) = master.getPoolInfo(address(this));

        // recompute accRewardsPerShare if not up to date
        if ((reserve > 0 || _currentBlockTimestamp() > lastRewardTime) && _lpSupplyWithMultiplier > 0) {
            uint256 duration = _currentBlockTimestamp().sub(lastRewardTime);
            // adding reserve here in case master has been synced but not the pool
            uint256 tokenRewards = duration.mul(poolEmissionRate).add(reserve);
            accRewardsPerShare = accRewardsPerShare.add(tokenRewards.mul(1e18).div(_lpSupplyWithMultiplier));
        }

        return
            position
                .amountWithMultiplier
                .mul(accRewardsPerShare)
                .div(1e18)
                .sub(position.rewardDebt)
                .add(position.pendingXTokenRewards)
                .add(position.pendingProtocolTokenRewards);
    }

    function pendingAdditionalRewards(
        uint256 tokenId
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        if (!additionalRewardsEnabled) return (tokens, rewardAmounts);

        StakingPosition storage position = _stakingPositions[tokenId];
        (, , uint256 lastRewardTime, , ) = master.getPoolInfo(address(this));
        (tokens, rewardAmounts) = rewardManager.pendingAdditionalRewards(
            tokenId,
            position.amountWithMultiplier,
            _lpSupplyWithMultiplier,
            lastRewardTime
        );
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /**
     * @dev Set lock multiplier settings
     *
     * maxLockMultiplier must be <= MAX_LOCK_MULTIPLIER_LIMIT
     * maxLockMultiplier must be <= _maxGlobalMultiplier - _maxBoostMultiplier
     *
     * Must only be called by the owner
     */
    function setLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier) external {
        require(msg.sender == owner() || msg.sender == operator, "FORBIDDEN");
        // onlyOperatorOrOwner: caller has no operator rights
        require(
            maxLockMultiplier <= MAX_LOCK_MULTIPLIER_LIMIT &&
                maxLockMultiplier.add(_maxBoostMultiplier) <= _maxGlobalMultiplier,
            "too high"
        );
        // setLockSettings: maxGlobalMultiplier is too high
        _maxLockDuration = maxLockDuration;
        _maxLockMultiplier = maxLockMultiplier;

        emit SetLockMultiplierSettings(maxLockDuration, maxLockMultiplier);
    }

    /**
     * @dev Set global and boost multiplier settings
     *
     * maxGlobalMultiplier must be <= MAX_GLOBAL_MULTIPLIER_LIMIT
     * maxBoostMultiplier must be <= MAX_BOOST_MULTIPLIER_LIMIT
     * (maxBoostMultiplier + _maxLockMultiplier) must be <= _maxGlobalMultiplier
     *
     * Must only be called by the owner
     */
    function setBoostMultiplierSettings(uint256 maxGlobalMultiplier, uint256 maxBoostMultiplier) external {
        _requireOnlyOwner();
        require(maxGlobalMultiplier <= MAX_GLOBAL_MULTIPLIER_LIMIT, "too high");

        // setMultiplierSettings: maxGlobalMultiplier is too high
        require(
            maxBoostMultiplier <= MAX_BOOST_MULTIPLIER_LIMIT &&
                maxBoostMultiplier.add(_maxLockMultiplier) <= maxGlobalMultiplier,
            "too high"
        );
        // setLockSettings: maxGlobalMultiplier is too high
        _maxGlobalMultiplier = maxGlobalMultiplier;
        _maxBoostMultiplier = maxBoostMultiplier;

        emit SetBoostMultiplierSettings(maxGlobalMultiplier, maxBoostMultiplier);
    }

    /**
     * @dev Set the share of xToken for the distributed rewards
     * The share of ProtocolToken will incidently be 100% - xTokenRewardsShare
     *
     * Must only be called by the owner
     */
    function setXTokenRewardsShare(uint256 xTokenRewardsShare_) external {
        _requireOnlyOwner();
        require(xTokenRewardsShare_ <= _TOTAL_REWARDS_SHARES, "too high");

        xTokenRewardsShare = xTokenRewardsShare_;
        emit SetXTokenRewardsShare(xTokenRewardsShare_);
    }

    /**
     * @dev Add or remove unlock operators
     *
     * Must only be called by the owner
     */
    function setUnlockOperator(address _operator, bool add) external {
        _requireOnlyOwner();

        if (add) {
            _unlockOperators.add(_operator);
        } else {
            _unlockOperators.remove(_operator);
        }
        emit SetUnlockOperator(_operator, add);
    }

    /**
     * @dev Set operator (usually deposit token's project's owner) to adjust contract's settings
     *
     * Must only be called by the owner
     */
    function setOperator(address operator_) external {
        _requireOnlyOwner();

        operator = operator_;
        emit SetOperator(operator_);
    }

    /**
     * @dev Set emergency unlock status
     *
     * Must only be called by the owner
     */
    function setEmergencyUnlock(bool emergencyUnlock_) external {
        _requireOnlyOwner();

        emergencyUnlock = emergencyUnlock_;
        emit SetEmergencyUnlock(emergencyUnlock);
    }

    /**
     * @dev Set the reward manager contract used to manage additional rewards.
     * Setting to zero address will disable addtional rewards.
     * Ability to disable rewards prevents the pool from being in a broken state
     * due to some outside factor with the reward manager.
     * Must only be called by the owner
     */
    function setRewardManager(address manager) external {
        _requireOnlyOperator();

        additionalRewardsEnabled = manager == address(0) ? false : true;
        rewardManager = ISinglePoolRewardManager(manager);

        emit SetRewardManager(manager);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Add nonReentrant to ERC721.transferFrom
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) nonReentrant {
        ERC721.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Add nonReentrant to ERC721.safeTransferFrom
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override(ERC721, IERC721) nonReentrant {
        ERC721.safeTransferFrom(from, to, tokenId, _data);
    }

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    /**
     * @dev Create a staking position (spNFT) with an optional lockDuration
     */
    function createPosition(uint256 amount, uint256 lockDuration) external nonReentrant {
        // no new lock can be set if the pool has been unlocked
        if (isUnlocked()) {
            require(lockDuration == 0, "locks disabled");
        }

        _updatePool();

        // handle tokens with transfer tax
        amount = _transferSupportingFeeOnTransfer(_lpToken, msg.sender, amount);
        require(amount != 0, "zero amount"); // createPosition: amount cannot be null

        // mint NFT position token
        uint256 currentTokenId = _mintNextTokenId(msg.sender);

        // calculate bonuses
        uint256 lockMultiplier = getMultiplierByLockDuration(lockDuration);
        uint256 amountWithMultiplier = amount.mul(lockMultiplier.add(1e4)).div(1e4);

        // create position
        _stakingPositions[currentTokenId] = StakingPosition({
            amount: amount,
            rewardDebt: amountWithMultiplier.mul(_accRewardsPerShare).div(1e18),
            lockDuration: lockDuration,
            startLockTime: _currentBlockTimestamp(),
            lockMultiplier: lockMultiplier,
            amountWithMultiplier: amountWithMultiplier,
            boostPoints: 0,
            totalMultiplier: lockMultiplier,
            pendingProtocolTokenRewards: 0,
            pendingXTokenRewards: 0
        });

        // update total lp supply
        _lpSupply = _lpSupply.add(amount);
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.add(amountWithMultiplier);

        emit CreatePosition(currentTokenId, amount, lockDuration);
    }

    /**
     * @dev Add to an existing staking position
     *
     * Can only be called by spNFT's owner or operators
     */
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external nonReentrant {
        _requireOnlyOperatorOrOwnerOf(tokenId);
        require(amountToAdd > 0, "0 amount"); // addToPosition: amount cannot be null

        _updatePool();
        address nftOwner = ERC721.ownerOf(tokenId);
        _harvestPosition(tokenId, nftOwner);

        StakingPosition storage position = _stakingPositions[tokenId];

        // if position is locked, renew the lock
        if (position.lockDuration > 0) {
            position.startLockTime = _currentBlockTimestamp();
            position.lockMultiplier = getMultiplierByLockDuration(position.lockDuration);
        }

        // handle tokens with transfer tax
        amountToAdd = _transferSupportingFeeOnTransfer(_lpToken, msg.sender, amountToAdd);

        // update position
        position.amount = position.amount.add(amountToAdd);
        _lpSupply = _lpSupply.add(amountToAdd);
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);

        _checkOnAddToPosition(nftOwner, tokenId, amountToAdd);
        emit AddToPosition(tokenId, msg.sender, amountToAdd);
    }

    /**
     * @dev Assign "amount" of boost points to a position
     *
     * Can only be called by the master-defined YieldBooster contract
     */
    function boost(uint256 tokenId, uint256 amount) external override nonReentrant {
        _requireOnlyYieldBooster();
        require(ERC721._exists(tokenId), "invalid tokenId");

        _updatePool();
        _harvestPosition(tokenId, address(0));

        StakingPosition storage position = _stakingPositions[tokenId];

        // update position
        uint256 boostPoints = position.boostPoints.add(amount);
        position.boostPoints = boostPoints;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        emit SetBoost(tokenId, boostPoints);
    }

    /**
     * @dev Remove "amount" of boost points from a position
     *
     * Can only be called by the master-defined YieldBooster contract
     */
    function unboost(uint256 tokenId, uint256 amount) external override nonReentrant {
        _requireOnlyYieldBooster();

        _updatePool();
        _harvestPosition(tokenId, address(0));

        StakingPosition storage position = _stakingPositions[tokenId];

        // update position
        uint256 boostPoints = position.boostPoints.sub(amount);
        position.boostPoints = boostPoints;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        emit SetBoost(tokenId, boostPoints);
    }

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPosition(uint256 tokenId) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _harvestPosition(tokenId, ERC721.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
    }

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);
        require(ERC721.ownerOf(tokenId).isContract(), "FORBIDDEN");

        _updatePool();
        _harvestPosition(tokenId, to);
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
    }

    /**
     * @dev Harvest from multiple staking positions to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPositionsTo(uint256[] calldata tokenIds, address to) external nonReentrant {
        _updatePool();

        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireOnlyApprovedOrOwnerOf(tokenId);
            address tokenOwner = ERC721.ownerOf(tokenId);
            // if sender is the current owner, must also be the harvest dst address
            // if sender is approved, current owner must be a contract
            require((msg.sender == tokenOwner && msg.sender == to) || tokenOwner.isContract(), "FORBIDDEN");

            _harvestPosition(tokenId, to);
            _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
        }
    }

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        address nftOwner = ERC721.ownerOf(tokenId);
        _withdrawFromPosition(nftOwner, tokenId, amountToWithdraw);
        _checkOnWithdraw(nftOwner, tokenId, amountToWithdraw);
    }

    /**
     * @dev Renew lock from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function renewLockPosition(uint256 tokenId) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, _stakingPositions[tokenId].lockDuration);
    }

    /**
     * @dev Lock a staking position (can be used to extend a lock)
     *
     * Can only be called by spNFT's owner or approved address
     */
    function lockPosition(uint256 tokenId, uint256 lockDuration) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, lockDuration);
    }

    /**
     * @dev Merge an array of staking positions into a single one with "lockDuration"
     * Can't be used on positions with a higher lock duration than "lockDuration" param
     *
     * Can only be called by spNFT's owner
     */
    function mergePositions(uint256[] calldata tokenIds, uint256 lockDuration) external nonReentrant {
        _updatePool();

        uint256 length = tokenIds.length;
        require(length > 1, "invalid");
        // mergePositions: array must have at least two items

        // set the destination position into which the others will be merged (using first item of the list)
        uint256 dstTokenId = tokenIds[0];
        _requireOnlyOwnerOf(dstTokenId);

        StakingPosition storage dstPosition = _stakingPositions[dstTokenId];
        require(dstPosition.lockDuration <= lockDuration, "can't merge");
        _harvestPosition(dstTokenId, msg.sender);

        dstPosition.lockDuration = lockDuration;
        dstPosition.lockMultiplier = getMultiplierByLockDuration(lockDuration);

        // loop starts at 2nd element
        for (uint256 i = 1; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireOnlyOwnerOf(tokenId);
            require(tokenId != dstTokenId, "invalid token id");

            _harvestPosition(tokenId, msg.sender);
            StakingPosition storage position = _stakingPositions[tokenId];

            // positions must have a lower lock duration than param
            require(position.lockDuration <= lockDuration, "can't merge");
            // mergePositions: positions cannot be merged

            // we want to use the latest startLockTime
            if (dstPosition.startLockTime < position.startLockTime) {
                dstPosition.startLockTime = position.startLockTime;
            }

            // aggregate amounts to the destination position
            dstPosition.amount = dstPosition.amount.add(position.amount);

            // destroy position
            _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);
            _destroyPosition(tokenId, position.boostPoints);
        }

        _updateBoostMultiplierInfoAndRewardDebt(dstPosition, dstTokenId);
        emit MergePositions(msg.sender, tokenIds);
    }

    /**
     * Withdraw without caring about rewards, EMERGENCY ONLY
     *
     * Can only be called by spNFT's owner
     */
    function emergencyWithdraw(uint256 tokenId) external nonReentrant {
        _requireOnlyOwnerOf(tokenId);

        StakingPosition storage position = _stakingPositions[tokenId];

        // position should be unlocked
        require(
            _unlockOperators.contains(msg.sender) ||
                position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp() ||
                isUnlocked(),
            "locked"
        );
        // emergencyWithdraw: locked

        uint256 amount = position.amount;

        // update total lp supply
        _lpSupply = _lpSupply.sub(amount);
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);

        // destroy position (ignore boost points)
        _destroyPosition(tokenId, 0);

        emit EmergencyWithdraw(tokenId, amount);
        _lpToken.safeTransfer(msg.sender, amount);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Returns whether "userAddress" is the owner of "tokenId" spNFT
     */
    function _isOwnerOf(address userAddress, uint256 tokenId) internal view returns (bool) {
        return userAddress == ERC721.ownerOf(tokenId);
    }

    /**
     * @dev Updates rewards states of this pool to be up-to-date
     */
    function _updatePool() internal {
        uint256 lpSupplyMultiplied = _lpSupplyWithMultiplier;

        if (additionalRewardsEnabled) {
            // User current reward time before pool claims and updates it
            (, , uint256 lastRewardTime, , ) = master.getPoolInfo(address(this));
            rewardManager.updateRewardsPerShare(lpSupplyMultiplied, lastRewardTime);
        }

        // gets allocated rewards from Master and updates
        uint256 rewardAmount = master.claimRewards();

        if (rewardAmount > 0) {
            _accRewardsPerShare = _accRewardsPerShare.add(rewardAmount.mul(1e18).div(lpSupplyMultiplied));
        }

        emit PoolUpdated(_currentBlockTimestamp(), _accRewardsPerShare);
    }

    /**
     * @dev Destroys spNFT
     *
     * "boostPointsToDeallocate" is set to 0 to ignore boost points handling if called during an emergencyWithdraw
     * Users should still be able to deallocate xToken from the YieldBooster contract
     */
    function _destroyPosition(uint256 tokenId, uint256 boostPoints) internal {
        // calls yieldBooster contract to deallocate the spNFT's owner boost points if any
        if (boostPoints > 0) {
            IYieldBooster(yieldBooster()).deallocateAllFromPool(msg.sender, tokenId);
        }

        // burn spNFT
        delete _stakingPositions[tokenId];
        ERC721._burn(tokenId);
    }

    /**
     * @dev Computes new tokenId and mint associated spNFT to "to" address
     */
    function _mintNextTokenId(address to) internal returns (uint256 tokenId) {
        _tokenIds.increment();
        tokenId = _tokenIds.current();
        _safeMint(to, tokenId);
    }

    /**
     * @dev Withdraw from a staking position and destroy it
     *
     * _updatePool() should be executed before calling this
     */
    function _withdrawFromPosition(address nftOwner, uint256 tokenId, uint256 amountToWithdraw) internal {
        require(amountToWithdraw > 0, "null");
        // withdrawFromPosition: amount cannot be null

        StakingPosition storage position = _stakingPositions[tokenId];
        require(
            _unlockOperators.contains(nftOwner) ||
                position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp() ||
                isUnlocked(),
            "locked"
        );
        // withdrawFromPosition: invalid amount
        require(position.amount >= amountToWithdraw, "invalid");

        _harvestPosition(tokenId, nftOwner);

        // update position
        position.amount = position.amount.sub(amountToWithdraw);

        // update total lp supply
        _lpSupply = _lpSupply.sub(amountToWithdraw);

        if (position.amount == 0) {
            // destroy if now empty
            _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);
            _destroyPosition(tokenId, position.boostPoints);
        } else {
            _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        }

        emit WithdrawFromPosition(tokenId, amountToWithdraw);
        _lpToken.safeTransfer(nftOwner, amountToWithdraw);
    }

    /**
     * @dev updates position's boost multiplier, totalMultiplier, amountWithMultiplier (_lpSupplyWithMultiplier)
     * and rewardDebt without updating lockMultiplier
     */
    function _updateBoostMultiplierInfoAndRewardDebt(StakingPosition storage position, uint256 tokenId) internal {
        // keep the original lock multiplier and recompute current boostPoints multiplier
        uint256 newTotalMultiplier = getMultiplierByBoostPoints(position.amount, position.boostPoints).add(
            position.lockMultiplier
        );
        if (newTotalMultiplier > _maxGlobalMultiplier) newTotalMultiplier = _maxGlobalMultiplier;

        position.totalMultiplier = newTotalMultiplier;
        uint256 amountWithMultiplier = position.amount.mul(newTotalMultiplier.add(1e4)).div(1e4);
        // update global supply
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier).add(amountWithMultiplier);
        position.amountWithMultiplier = amountWithMultiplier;

        position.rewardDebt = amountWithMultiplier.mul(_accRewardsPerShare).div(1e18);

        if (additionalRewardsEnabled) {
            rewardManager.updatePositionRewardDebts(amountWithMultiplier, tokenId);
        }
    }

    /**
     * @dev Harvest rewards from a position
     * Will also update the position's totalMultiplier
     */
    function _harvestPosition(uint256 tokenId, address to) internal {
        StakingPosition storage position = _stakingPositions[tokenId];

        // compute position's pending rewards
        uint256 positionAmountMultiplied = position.amountWithMultiplier;
        uint256 pending = positionAmountMultiplied.mul(_accRewardsPerShare).div(1e18).sub(position.rewardDebt);

        // unlock the position if pool has been unlocked or position is unlocked
        if (isUnlocked() || position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp()) {
            position.lockDuration = 0;
            position.lockMultiplier = 0;
        }

        // transfer rewards
        if (pending > 0 || position.pendingXTokenRewards > 0 || position.pendingProtocolTokenRewards > 0) {
            uint256 xTokenRewards = pending.mul(xTokenRewardsShare).div(_TOTAL_REWARDS_SHARES);
            uint256 protocolTokenAmount = pending.add(position.pendingProtocolTokenRewards).sub(xTokenRewards);

            xTokenRewards = xTokenRewards.add(position.pendingXTokenRewards);

            // Stack rewards in a buffer if to is equal to address(0)
            if (address(0) == to) {
                position.pendingXTokenRewards = xTokenRewards;
                position.pendingProtocolTokenRewards = protocolTokenAmount;
            } else {
                // convert and send xToken + ProtocolToken rewards
                position.pendingXTokenRewards = 0;
                position.pendingProtocolTokenRewards = 0;

                if (xTokenRewards > 0) xTokenRewards = _safeConvertTo(to, xTokenRewards);
                // send share of ProtocolToken rewards
                protocolTokenAmount = _safeRewardsTransfer(to, protocolTokenAmount);

                // forbidden to harvest if contract has not explicitly confirmed it handle it
                _checkOnNFTHarvest(to, tokenId, protocolTokenAmount, xTokenRewards);

                if (additionalRewardsEnabled) {
                    rewardManager.harvestAdditionalRewards(positionAmountMultiplied, to, tokenId);
                }
            }
        }
        emit HarvestPosition(tokenId, to, pending);
    }

    /**
     * @dev Renew lock from a staking position with "lockDuration"
     */
    function _lockPosition(uint256 tokenId, uint256 lockDuration) internal {
        require(!isUnlocked(), "locks disabled");

        StakingPosition storage position = _stakingPositions[tokenId];

        // for renew only, check if new lockDuration is at least = to the remaining active duration
        uint256 endTime = position.startLockTime.add(position.lockDuration);
        uint256 currentBlockTimestamp = _currentBlockTimestamp();
        if (endTime > currentBlockTimestamp) {
            require(lockDuration >= endTime.sub(currentBlockTimestamp) && lockDuration > 0, "invalid");
        }

        _harvestPosition(tokenId, msg.sender);

        // update position and total lp supply
        position.lockDuration = lockDuration;
        position.lockMultiplier = getMultiplierByLockDuration(lockDuration);
        position.startLockTime = currentBlockTimestamp;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);

        emit LockPosition(tokenId, lockDuration);
    }

    /**
     * @dev Handle deposits of tokens with transfer tax
     */
    function _transferSupportingFeeOnTransfer(
        IERC20 token,
        address user,
        uint256 amount
    ) internal returns (uint256 receivedAmount) {
        uint256 previousBalance = token.balanceOf(address(this));
        token.safeTransferFrom(user, address(this), amount);
        return token.balanceOf(address(this)).sub(previousBalance);
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(address to, uint256 amount) internal returns (uint256) {
        uint256 balance = _protocolToken.balanceOf(address(this));
        // cap to available balance
        if (amount > balance) {
            amount = balance;
        }
        _protocolToken.safeTransfer(to, amount);
        return amount;
    }

    /**
     * @dev Safe convert ProtocolToken to xToken function, in case rounding error causes pool to not have enough tokens
     */
    function _safeConvertTo(address to, uint256 amount) internal returns (uint256) {
        uint256 balance = _protocolToken.balanceOf(address(this));
        // cap to available balance
        if (amount > balance) {
            amount = balance;
        }
        if (amount > 0) _xToken.convertTo(amount, to);
        return amount;
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle rewards harvesting
     */
    function _checkOnNFTHarvest(
        address to,
        uint256 tokenId,
        uint256 protocolTokenAmount,
        uint256 xTokenAmount
    ) internal {
        address nftOwner = ERC721.ownerOf(tokenId);
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(
                    INFTHandler(nftOwner).onNFTHarvest.selector,
                    msg.sender,
                    to,
                    tokenId,
                    protocolTokenAmount,
                    xTokenAmount
                ),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle addToPosition
     */
    function _checkOnAddToPosition(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(
                    INFTHandler(nftOwner).onNFTAddToPosition.selector,
                    msg.sender,
                    tokenId,
                    lpAmount
                ),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle withdrawals
     */
    function _checkOnWithdraw(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(INFTHandler(nftOwner).onNFTWithdraw.selector, msg.sender, tokenId, lpAmount),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev Forbid transfer when spNFT's owner is a contract and an operator is trying to transfer it
     * This is made to avoid unintended side effects
     *
     * Contract owner can still implement it by itself if needed
     */
    function _beforeTokenTransfer(address from, address /*to*/, uint256 /*tokenId*/) internal view override {
        require(!from.isContract() || msg.sender == from, "FORBIDDEN");
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}

contract NFTPoolFactory {
    IMasterChef public immutable master; // Address of the master
    IERC20 public immutable protocolToken;
    IXToken public immutable xToken;

    // lp token => pool
    mapping(address => address) public getPool;
    address[] public pools;

    constructor(IMasterChef _master, IERC20 _protocolToken, IXToken _xToken) {
        master = _master;
        protocolToken = _protocolToken;
        xToken = _xToken;
    }

    event PoolCreated(address indexed lpToken, address pool);

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function createPool(address lpToken) external returns (address pool) {
        require(getPool[lpToken] == address(0), "pool exists");

        bytes memory bytecode_ = type(NFTPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(lpToken));
        /* solhint-disable no-inline-assembly */
        assembly {
            pool := create2(0, add(bytecode_, 32), mload(bytecode_), salt)
        }
        require(pool != address(0), "failed");

        NFTPool(pool).initialize(master, protocolToken, xToken, IERC20(lpToken));
        getPool[lpToken] = pool;
        pools.push(pool);

        emit PoolCreated(lpToken, pool);
    }
}