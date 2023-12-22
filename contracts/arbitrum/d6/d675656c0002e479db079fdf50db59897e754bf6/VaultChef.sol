// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.9;

//File: [SafeMath.sol]

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

//File: [ReentrancyGuard.sol]

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

//File: [IERC20.sol]

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

//File: [Address.sol]

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

//File: [VaultRoles.sol]

abstract contract VaultRoles
{
    //========================
    // ATTRIBUTES
    //========================

    //roles
    bytes32 public constant ROLE_SUPER_ADMIN = keccak256("ROLE_SUPER_ADMIN"); //role management + admin
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN"); //highest security. required to change important settings (security risk)
    bytes32 public constant ROLE_MANAGER = keccak256("ROLE_MANAGER"); //required to change settings to optimize behaviour (no security risk, but trust is required)
    bytes32 public constant ROLE_SECURITY_ADMIN = keccak256("ROLE_SECURITY_ADMIN"); //can pause and unpause (no security risk, but trust is required)
    bytes32 public constant ROLE_SECURITY_MOD = keccak256("ROLE_SECURITY_MOD"); //can pause but not unpause (no security risk, minimal trust required)
    bytes32 public constant ROLE_DEPLOYER = keccak256("ROLE_DEPLOYER"); //can deploy vaults, should be a trusted developer
    bytes32 public constant ROLE_COMPOUNDER = keccak256("ROLE_COMPOUNDER"); //compounders are always allowed to compound (no security risk)
}

//File: [Context.sol]

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

//File: [Strings.sol]

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
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
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

//File: [EnumerableSet.sol]

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

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

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

//File: [IERC165.sol]

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

//File: [SafeERC20.sol]

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

//File: [IToken.sol]

interface IToken is IERC20
{
	function decimals() external view returns (uint8);	
	function symbol() external view returns (string memory);
	function name() external view returns (string memory);
}

//File: [ERC165.sol]

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

//File: [AccessControl.sol]

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address account) external;
}

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     */
    function _checkRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(uint160(account), 20),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, getRoleAdmin(role), adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

//File: [AccessControlEnumerable.sol]

/**
 * @dev External interface of AccessControlEnumerable declared to support ERC165 detection.
 */
interface IAccessControlEnumerable {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

/**
 * @dev Extension of {AccessControl} that allows enumerating the members of each role.
 */
abstract contract AccessControlEnumerable is IAccessControlEnumerable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => EnumerableSet.AddressSet) private _roleMembers;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlEnumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view override returns (address) {
        return _roleMembers[role].at(index);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view override returns (uint256) {
        return _roleMembers[role].length();
    }

    /**
     * @dev Overload {grantRole} to track enumerable memberships
     */
    function grantRole(bytes32 role, address account) public virtual override {
        super.grantRole(role, account);
        _roleMembers[role].add(account);
    }

    /**
     * @dev Overload {revokeRole} to track enumerable memberships
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        super.revokeRole(role, account);
        _roleMembers[role].remove(account);
    }

    /**
     * @dev Overload {renounceRole} to track enumerable memberships
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        super.renounceRole(role, account);
        _roleMembers[role].remove(account);
    }

    /**
     * @dev Overload {_setupRole} to track enumerable memberships
     */
    function _setupRole(bytes32 role, address account) internal virtual override {
        super._setupRole(role, account);
        _roleMembers[role].add(account);
    }
}

//File: [AccessManagerAllowedContractsList.sol]

contract AccessManagerAllowedContractsList is AccessControlEnumerable
{
    //========================
    // ATTRIBUTES
    //========================   
    
    bytes32 public constant ROLE_ALLOWED_CONTRACT = keccak256("ROLE_ALLOWED_CONTRACT");

    //========================
    // CREATE
    //========================
    
    constructor()
    {

    }

    //========================
    // SECURITY FUNCTIONS
    //========================
    
    function notContractOrAllowed() internal view
	{
	    if (!hasRole(ROLE_ALLOWED_CONTRACT, msg.sender))
        {
            notContract();
        }
	}
    
	function notContract() internal view
	{
		require(!checkIsContract(msg.sender), "contract");
        require(msg.sender == tx.origin, "proxy contract");	
	}	
	
    function checkIsContract(address _address) internal view returns (bool)
    {
        uint256 size;
        assembly
        {
            size := extcodesize(_address)
        }
        return size > 0;
    }
}

//File: [IVaultStrategy.sol]

interface IVaultStrategy
{
    //========================
    // CONSTANTS
    //========================
	
	function VERSION() external view returns (string memory);
    function BASE_VERSION() external view returns (string memory);

    //========================
    // ATTRIBUTES
    //========================

    function vault() external view returns (IVault);    

    //used tokens
    function depositToken() external view returns (IToken);
    function rewardToken() external view returns (IToken);
    function additionalRewardToken() external view returns (IToken);
    function lpToken0() external view returns (IToken);
    function lpToken1() external view returns (IToken); 

    //min swap amounts
    function minAdditionalRewardToReward() external view returns (uint256);
    function minRewardToDeposit() external view returns (uint256);
    function minDustToken0() external view returns (uint256);
    function minDustToken1() external view returns (uint256);

    //auto actions
    function autoConvertDust() external view returns (bool);
    function autoCompoundBeforeDeposit() external view returns (bool);
    function autoCompoundBeforeWithdraw() external view returns (bool);

    //pause
    function pauseDeposit() external view returns (bool);
    function pauseWithdraw() external view returns (bool);
    function pauseCompound() external view returns (bool);

    //========================
    // DEPOSIT / WITHDRAW / COMPOUND FUNCTIONS
    //========================  

    function deposit() external;
    function withdraw(address _user, uint256 _amount) external;
    function compound(address _user, bool _revertOnFail) external returns (bool compounded, uint256 rewardAmount, uint256 dustAmount);

    //========================
    // OVERRIDE FUNCTIONS
    //========================
    
    function beforeDeposit() external;
    function beforeWithdraw() external;

    //========================
    // POOL INFO FUNCTIONS
    //========================

    function balanceOf() external view returns (uint256);
    function balanceOfStrategy() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function balanceOfReward() external view returns (uint256);
    function balanceOfDust() external view returns (uint256, uint256);

    function poolCompoundReward() external view returns (uint256);
    function poolPending() external view returns (uint256);
    function poolDepositFee() external view returns (uint256);
    function poolWithdrawFee() external view returns (uint256);
    function poolAllocPoints() external view returns (uint256);
    function poolStartBlock() external view returns (uint256);
    function poolEndBlock() external view returns (uint256);
    function poolEndTime() external view returns (uint256);
    function poolHarvestLockUntil() external view returns (uint256);
    function poolHarvestLockDelay() external view returns (uint256);
    function isPoolFarmable() external view returns (bool);

    //========================
    // STRATEGY RETIRE FUNCTIONS
    //========================

    function retireStrategy() external;

    //========================
    // EMERGENCY FUNCTIONS
    //========================

    function panic() external;
    function pause(bool _pauseDeposit, bool _pauseWithdraw, bool _pauseCompound) external;
    function unpause(bool _unpauseDeposit, bool _unpauseWithdraw, bool _unpauseCompound) external;
}

//File: [IVaultChef.sol]

interface IVaultChef is IAccessControl
{
    //========================
    // CONSTANTS
    //========================

    function VERSION() external view returns (string memory);
    function PERCENT_FACTOR() external view returns (uint256);

    //========================
    // ATTRIBUTES
    //========================

    function wrappedCoin() external view returns (IToken);

    function compoundRewardFee() external view returns (uint256);
    function nativeLiquidityFee() external view returns (uint256);
    function nativePoolFee() external view returns (uint256);
    function withdrawalFee() external view returns (uint256);

    function nativeLiquidityAddress() external view returns (address);
    function nativePoolAddress() external view returns (address);

    function compoundRewardNative() external view returns (bool);
    function allowUserCompound() external view returns (bool);    

    //========================
    // VAULT INFO FUNCTIONS
    //========================

    function vaultLength() external view returns (uint256);		
	function getVault(uint256 _vid) external view returns (IVault);
    function checkVaultApproved(uint _vid, address _user) external view returns (bool);

    //========================
    // VAULT FUNCTIONS
    //========================

    function addVault(IVault _vault) external;

    //========================
    // DEPOSIT / WITHDRAW / COMPOUND FUNCTIONS
    //========================

    function compound(uint256 _vid) external;
    function deposit(uint256 _vid, uint256 _amount) external;
    function withdraw(uint256 _vid, uint256 _amount) external;	
	function emergencyWithdraw(uint256 _vid) external;
	
	//========================
    // MISC FUNCTIONS
    //========================
	
	function setReferrer(address _referrer) external;
    function getReferralInfo(address _user) external view returns (address, uint256);

    //========================
    // SECURITY FUNCTIONS
    //========================

    function requireAdmin(address _user) external view;
    function requireDeployer(address _user) external view;
    function requireCompounder(address _user) external view;
    function requireManager(address _user) external view;
    function requireSecurityAdmin(address _user) external view;
    function requireSecurityMod(address _user) external view;
    function requireAllowedContract(address _user) external view;    
}

//File: [IVault.sol]

interface IVault
{
    //========================
    // CONSTANTS
    //========================

    function VERSION() external view returns (string memory);

    //========================
    // ATTRIBUTES
    //========================

    function strategy() external view returns (IVaultStrategy);

    function totalShares() external view returns (uint256);
    function lastCompound() external view returns (uint256);

    //========================
    // VAULT INFO FUNCTIONS
    //========================

    function depositToken() external view returns (IToken);
    function rewardToken() external view returns (IToken);
    function balance() external view returns (uint256);

    //========================
    // USER INFO FUNCTIONS
    //========================    

    function checkApproved(address _user) external view returns (bool);
    function balanceOf(address _user) external view returns (uint256);
    function userPending(address _user) external view returns (uint256);

    //========================
    // POOL INFO FUNCTIONS
    //========================

    function poolCompoundReward() external view returns (uint256);
    function poolPending() external view returns (uint256);
    function poolDepositFee() external view returns (uint256);
    function poolWithdrawFee() external view returns (uint256);
    function poolAllocPoints() external view returns (uint256);
    function poolStartBlock() external view returns (uint256);
    function poolEndBlock() external view returns (uint256);
    function poolEndTime() external view returns (uint256);
    function poolHarvestLockUntil() external view returns (uint256);
    function poolHarvestLockDelay() external view returns (uint256);
    function isPoolFarmable() external view returns (bool);

    //========================
    // DEPOSIT / WITHDRAW / COMPOUND FUNCTIONS
    //========================

    function depositAll(address _user) external;
    function deposit(address _user, uint256 _amount) external;
    function withdrawAll(address _user) external;
    function withdraw(address _user, uint256 _amount) external;
    function compound(address _user) external;
}

//File: [VaultChefAccessManager.sol]

abstract contract VaultChefAccessManager is IVaultChef, VaultRoles, AccessManagerAllowedContractsList
{
    //========================
    // ATTRIBUTES
    //========================
    
    //super admin
    address public superAdmin;

    //========================
    // EVENTS
    //========================

    event SuperAdminTransferred(address _old, address _new);

    //========================
    // CREATE
    //========================

    constructor()
    {   
        //init access control        
        _setRoleAdmin(ROLE_ADMIN, ROLE_SUPER_ADMIN);        
        _setRoleAdmin(ROLE_MANAGER, ROLE_SUPER_ADMIN);
        _setRoleAdmin(ROLE_SECURITY_ADMIN, ROLE_SUPER_ADMIN);
        _setRoleAdmin(ROLE_SECURITY_MOD, ROLE_SUPER_ADMIN);
        _setRoleAdmin(ROLE_DEPLOYER, ROLE_SUPER_ADMIN);
        _setRoleAdmin(ROLE_COMPOUNDER, ROLE_SUPER_ADMIN);
        _setRoleAdmin(ROLE_ALLOWED_CONTRACT, ROLE_SUPER_ADMIN);

        //setup roles
        _setupRole(ROLE_SUPER_ADMIN, msg.sender);
        superAdmin = msg.sender;
    }

    //========================
    // CONFIG FUNCTIONS
    //========================

    function transferSuperAdmin(address _newSuperAdmin) external
    {
        require(hasRole(ROLE_SUPER_ADMIN, msg.sender), "User is not SuperAdmin");
        require(_newSuperAdmin != superAdmin, "User already is Superadmin");
        _setupRole(ROLE_SUPER_ADMIN, _newSuperAdmin);
        renounceRole(ROLE_SUPER_ADMIN, superAdmin);
        superAdmin = _newSuperAdmin; 
        emit SuperAdminTransferred(msg.sender, superAdmin);  
    }

    //========================
    // SECURITY FUNCTIONS
    //========================

    function isAdmin(address _user) public view returns (bool)
    {
        return hasRole(ROLE_SUPER_ADMIN, _user)
            || hasRole(ROLE_ADMIN, _user);
    }

    function requireAdmin(address _user) public override view
    {
        require(
            isAdmin(_user),
            "User is not Admin");
    }

    function requireDeployer(address _user) public override view
    {
        require(
            isAdmin(_user)
                || hasRole(ROLE_DEPLOYER, _user),
            "User is not Admin/Deployer");
    }

    function requireCompounder(address _user) public override view
    {
        require(
            isAdmin(_user)
                || hasRole(ROLE_COMPOUNDER, _user),
            "User is not Admin/Compounder");
    }

    function requireManager(address _user) public override view
    {
        require(
            isAdmin(_user)
                || hasRole(ROLE_MANAGER, _user),
            "User is not Admin/Manager");
    }

    function requireSecurityAdmin(address _user) public override view
    {
        require(
            isAdmin(_user)
                || hasRole(ROLE_SECURITY_ADMIN, _user),
            "User is not Admin/SecurityAdmin");
    }

    function requireSecurityMod(address _user) public override view
    {
        require(
            isAdmin(_user)
                || hasRole(ROLE_SECURITY_ADMIN, _user)
                || hasRole(ROLE_SECURITY_MOD, _user),
            "User is not Admin/SecurityAdmin/SecurityMod");
    }

    function requireAllowedContract(address _user) public override view
    {
        require(
            hasRole(ROLE_ALLOWED_CONTRACT, _user),
            "User is not AllowedContract");
    }
}

contract VaultChef is VaultChefAccessManager, ReentrancyGuard
{
    //========================
    // LIBS
    //========================

    using SafeERC20 for IToken;
    using SafeMath for uint256;

    //========================
    // STRUCTS
    //========================

    struct VaultInfo
    {
        IVault vault;
        bool enabled;
    }

    struct UserInfo
    {
        address referrer;
        uint256 referrals;
    }

    //========================
    // CONSTANTS
    //========================
	
	string public constant override VERSION = "1.0.0";	
	uint256 public constant override PERCENT_FACTOR = 1000000; //100%

    uint256 public constant MAX_REWARD_FEE = 50000; //5%
    uint256 public constant MAX_LIQUIDITY_FEE = 50000; //5%
    uint256 public constant MAX_POOL_FEE = 50000; //5%    
    uint256 public constant MAX_TOTAL_FEE = 50000; //5%	
    uint256 public constant MAX_WITHDRAW_FEE = 10000; //1%    

    //========================
    // ATTRIBUTES
    //========================
    
    address public override nativeLiquidityAddress = 0x4348Bbb326C67742D90F87cEd103badAB867ffbE; //this is default wallet used for blockchain without native token
    address public override nativePoolAddress = 0x4348Bbb326C67742D90F87cEd103badAB867ffbE; //this is default wallet used for blockchain without native token
    uint256 public override compoundRewardFee = 5000; //0.5%
    uint256 public override nativeLiquidityFee = 20000; //2%
    uint256 public override nativePoolFee = 20000; //2%
    uint256 public immutable override withdrawalFee = 1000; //0.1%

    IToken public override immutable wrappedCoin;

    VaultInfo[] public vaultInfo;
    mapping(address => uint256) public vaultMap;
    mapping(address => UserInfo) public userInfo;

    bool public override compoundRewardNative = false; //native token of farm instead of wrapped coin
    bool public override allowUserCompound = true; //are users allowed to compound
    
    //pause actions in case of emergency
    bool public pauseCompound;
    bool public pauseDeposit;
    bool public pauseWithdraw;

    //========================
    // EVENTS
    //========================

    event Pause(address indexed _user, bool _deposit, bool _withdraw, bool _compound);
    event Unpause(address indexed _user, bool _deposit, bool _withdraw, bool _compound);
    event Compound(uint256 indexed _vid, address indexed _user);
    event Deposit(uint256 indexed _vid, address indexed _user, uint256 _amount);
    event Withdraw(uint256 indexed _vid, address indexed _user, uint256 _amount);
	event EmergencyWithdraw(uint256 indexed _vid, address indexed _user);
    event ConfigChanged(string indexed _key, address indexed _sender, uint256 _value);
    event SetReferrer(address indexed _user, address indexed _referrer);

    //========================
    // CREATE
    //========================
    
    constructor(IToken _wrappedCoin)
    VaultChefAccessManager()
    {
        wrappedCoin = _wrappedCoin;
    }
    
    //========================
    // CONFIG FUNCTIONS
    //========================

    function setNativeLiquidityAddress(address _address) external
    {
        requireAdmin(msg.sender);
        nativeLiquidityAddress = _address;
        emit ConfigChanged("NativeLiquidityAddress", msg.sender, uint256(uint160(_address)));
    }

    function setNativePoolAddress(address _address) external
    {
        requireAdmin(msg.sender);
        nativePoolAddress = _address;
        emit ConfigChanged("NativePoolAddress", msg.sender, uint256(uint160(_address)));
    }

    function setCompoundRewardFee(uint256 _fee) external
    {
        //check
        requireAdmin(msg.sender);
        require(_fee <= MAX_REWARD_FEE, "value > rewardFee");
        require(_fee.add(nativeLiquidityFee).add(nativePoolFee) <= MAX_TOTAL_FEE, "value > totalFee");        

        compoundRewardFee = _fee;
        emit ConfigChanged("CompoundRewardFee", msg.sender, compoundRewardFee);
    }
    
    function setNativeLiquidityFee(uint256 _fee) external
    {
        //check
        requireAdmin(msg.sender);
        require(_fee <= MAX_LIQUIDITY_FEE, "value > nativeLiquidityFee");
        require(_fee.add(compoundRewardFee).add(nativePoolFee) <= MAX_TOTAL_FEE, "value > totalFee");        

        nativeLiquidityFee = _fee;
        emit ConfigChanged("TeamTreasuryFee", msg.sender, nativeLiquidityFee);
    }

    function setNativePoolFee(uint256 _fee) external
    {
        //check
        requireAdmin(msg.sender);
        require(_fee <= MAX_POOL_FEE, "value > nativePoolFee");
        require(_fee.add(nativeLiquidityFee).add(compoundRewardFee) <= MAX_TOTAL_FEE, "value > totalFee");        
        
        nativePoolFee = _fee;
        emit ConfigChanged("NativePoolFee", msg.sender, nativePoolFee);
    }

    function setCompoundRewardNative(bool _native) external
    {
        //check
        requireAdmin(msg.sender);
        
        compoundRewardNative = _native;
        emit ConfigChanged("CompoundRewardNative", msg.sender, (compoundRewardNative ? 1 : 0));
    }

    function setAllowUserCompound(bool _allow) external
    {
        //check
        requireAdmin(msg.sender);
        
        allowUserCompound = _allow;
        emit ConfigChanged("AllowUserCompound", msg.sender, (allowUserCompound ? 1 : 0));
    }
    
    //========================
    // VAULT FUNCTIONS
    //========================

    function addVault(IVault _vault) external
    {
        //check
        requireDeployer(tx.origin);

        //add
        vaultInfo.push
        (
            VaultInfo(
			{
                vault: _vault,
                enabled: true
            })
        );
    }
    
    function setVault(uint256 _vid, IVault _vault) external
	{
        //check
	    requireDeployer(tx.origin);
		require(_vid < vaultInfo.length, "invalid vault ID");

        //override
		VaultInfo storage vault = vaultInfo[_vid];		
        vault.vault = _vault;
	}
    
    function setVaultStatus(uint256 _vid, bool _enabled) external
    {
        //check
        requireDeployer(msg.sender);        
		require(_vid < vaultInfo.length, "invalid vault ID");

        //disable
        VaultInfo storage vault = vaultInfo[_vid];
        vault.enabled = _enabled;
    }
	
	//========================
    // VAULT INFO FUNCTIONS
    //========================

    function vaultLength() external view override returns (uint256)
    {
        return vaultInfo.length;
    }
	
	function checkVaultApproved(uint _vid, address _user) external view override returns (bool)
	{	
		VaultInfo storage vault = vaultInfo[_vid];	
		return vault.vault.checkApproved(_user);	
    }

	function getVault(uint256 _vid) external view override returns (IVault)
	{
		VaultInfo storage vault = vaultInfo[_vid];
        return vault.vault;
	}

    //========================
    // DEPOSIT / WITHDRAW / COMPOUND FUNCTIONS
    //========================

    function compound(uint256 _vid) external override nonReentrant 
    {
        //check
        notContractOrAllowed();
        require(!pauseCompound, "Compounds paused!");
        if (!allowUserCompound)
        {
            requireCompounder(msg.sender);
        }

        //compounds
        VaultInfo storage vault = vaultInfo[_vid];
        vault.vault.compound(msg.sender);
        emit Compound(_vid, msg.sender);
    }

    function deposit(uint256 _vid, uint256 _amount) external override nonReentrant
    {
        VaultInfo storage vault = vaultInfo[_vid];
		uint256 balance = vault.vault.depositToken().balanceOf(msg.sender);

        //check
        notContractOrAllowed();
        require(!pauseDeposit, "Deposits paused!");
        require(balance >= _amount, "Insufficient balance");
        require(_amount > 0, "0 deposit");
        require(vault.enabled, "Vault disabled!");

        //deposit		
        vault.vault.deposit(msg.sender, _amount);
        emit Deposit(_vid, msg.sender, _amount);
    }

    function withdraw(uint256 _vid, uint256 _amount) external override nonReentrant
    {
        //check
        notContractOrAllowed();
        require(!pauseWithdraw, "Withdraws paused!");
        require(_amount > 0, "0 withdraw");

        //withdraw
        VaultInfo storage vault = vaultInfo[_vid];   
        vault.vault.withdraw(msg.sender, _amount);
        emit Withdraw(_vid, msg.sender, _amount);
    }
	
	function emergencyWithdraw(uint256 _vid) external override nonReentrant
    {
        //check
        notContractOrAllowed();
        require(!pauseWithdraw, "Withdraws paused!");

        //withdraw
        VaultInfo storage vault = vaultInfo[_vid];   
        vault.vault.withdraw(msg.sender, type(uint256).max);
        emit EmergencyWithdraw(_vid, msg.sender);
    }

    //========================
    // REFERRAL FUNCTIONS
    //========================
    
    function setReferrer(address _referrer) external override
    {
        UserInfo storage user = userInfo[msg.sender];

        //check
        require(user.referrer == address(0), "Referrer already set"); 
        require(_referrer != address(0), "Invalid Referrer");
        require(_referrer != msg.sender, "Can't refer yourself");

        //set
        user.referrer = _referrer;
        emit SetReferrer(msg.sender, _referrer);

        //increase referals
        UserInfo storage userReferrer = userInfo[_referrer];
        userReferrer.referrals = userReferrer.referrals.add(1);
    }

    function getReferralInfo(address _user) external view override returns (address, uint256)
    {
        UserInfo storage user = userInfo[_user];
        return (user.referrer, user.referrals);
    }

    //========================
    // EMERGENCY FUNCTIONS
    //========================

    function inCaseTokensGetStuck(IToken _token) external
    {
        //check
        requireSecurityAdmin(msg.sender);

        //send
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }

    function pause(bool _pauseDeposit, bool _pauseWithdraw, bool _pauseCompound) external
    {
        //check
        requireSecurityMod(msg.sender);

        //pause
        if (_pauseDeposit)
        {    
            pauseDeposit = true;
        }
        if (_pauseWithdraw)
        {    
            pauseWithdraw = true;
        }
        if (_pauseCompound)
        {    
            pauseCompound = true;
        }

        //event
        emit Pause(msg.sender, _pauseDeposit, _pauseWithdraw, _pauseCompound);
    }
    
    function unpause(bool _unpauseDeposit, bool _unpauseWithdraw, bool _unpauseCompound) external
    {
        //check
        requireSecurityAdmin(msg.sender);

        //unpause
        if (_unpauseDeposit)
        {    
            pauseDeposit = false;
        }
        if (_unpauseWithdraw)
        {    
            pauseWithdraw = false;
        }
        if (_unpauseCompound)
        {    
            pauseCompound = false;
        }

        //event
        emit Unpause(msg.sender, _unpauseDeposit, _unpauseWithdraw, _unpauseCompound);
    }
}