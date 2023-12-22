// Sources flattened with hardhat v2.14.0 https://hardhat.org

// File @openzeppelin/contracts/utils/Context.sol@v4.8.3


/**
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


// File @openzeppelin/contracts/access/Ownable.sol@v4.8.3


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
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v4.8.3


/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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
}


// File @openzeppelin/contracts/utils/structs/EnumerableSet.sol@v4.8.3


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
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an
 * array of EnumerableSet.
 * ====
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
                bytes32 lastValue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastValue;
                // Update the index for the moved value
                set._indexes[lastValue] = valueIndex; // Replace lastValue's index to valueIndex
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

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
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

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        bytes32[] memory store = _values(set._inner);
        bytes32[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
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

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(AddressSet storage set) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
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
     * @dev Returns the number of values in the set. O(1).
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

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(UintSet storage set) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }
}


// File contracts/MultiWrapper.sol


interface IWrapper {
    function wrap(IERC20 token) external view returns (IERC20 wrappedToken, uint256 rate);
}

/// @notice A smart contract to manage multiple token wrappers and provide wrapped tokens with conversion rates.
contract MultiWrapper is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The event emitted when a new wrapper is added.
    event WrapperAdded(IWrapper connector);
    /// @notice The event emitted when an existing wrapper is removed.
    event WrapperRemoved(IWrapper connector);
    /// @notice Enumerable set of wrapper addresses.
    EnumerableSet.AddressSet private _wrappers;

    /// @notice Initialize the contract with an array of existing wrappers.
    /// @param existingWrappers An array of existing wrappers to be added during contract deployment.
    constructor(IWrapper[] memory existingWrappers) {
        for (uint256 i = 0; i < existingWrappers.length; i++) {
            require(_wrappers.add(address(existingWrappers[i])), "Wrapper already added");
            emit WrapperAdded(existingWrappers[i]);
        }
    }

    /// @notice Return the list of all registered wrappers.
    /// @return allWrappers An array of all registered wrapper instances.
    function wrappers() external view returns (IWrapper[] memory allWrappers) {
        allWrappers = new IWrapper[](_wrappers.length());
        for (uint256 i = 0; i < allWrappers.length; i++) {
            allWrappers[i] = IWrapper(_wrappers.at(i));
        }
    }

    /// @notice Add a new wrapper to the set, only callable by the contract owner.
    /// @param wrapper The instance of the wrapper to be added.
    function addWrapper(IWrapper wrapper) external onlyOwner {
        require(_wrappers.add(address(wrapper)), "Wrapper already added");
        emit WrapperAdded(wrapper);
    }

    /// @notice Remove an existing wrapper from the set, only callable by the contract owner.
    /// @param wrapper The instance of the wrapper to be removed.
    function removeWrapper(IWrapper wrapper) external onlyOwner {
        require(_wrappers.remove(address(wrapper)), "Unknown wrapper");
        emit WrapperRemoved(wrapper);
    }

    /// @notice Get wrapped tokens and their conversion rates for a given ERC20 token.
    /// @param token The instance of the ERC20 token to be wrapped.
    /// @return wrappedTokens An array of wrapped token instances.
    /// @return rates An array of conversion rates for the wrapped tokens.
    function getWrappedTokens(IERC20 token) external view returns (IERC20[] memory wrappedTokens, uint256[] memory rates) {
        IERC20[] memory memWrappedTokens = new IERC20[](20);
        uint256[] memory memRates = new uint256[](20);
        uint256 len = 0;
        for (uint256 i = 0; i < _wrappers._inner._values.length; i++) {
            try IWrapper(_wrappers.at(i)).wrap(token) returns (IERC20 wrappedToken, uint256 rate) {
                memWrappedTokens[len] = wrappedToken;
                memRates[len] = rate;
                len += 1;
                for (uint256 j = 0; j < _wrappers._inner._values.length; j++) {
                    if (i != j) {
                        try IWrapper(_wrappers.at(j)).wrap(wrappedToken) returns (IERC20 wrappedToken2, uint256 rate2) {
                            bool used = false;
                            for (uint256 k = 0; k < len; k++) {
                                if (wrappedToken2 == memWrappedTokens[k]) {
                                    used = true;
                                    break;
                                }
                            }
                            if (!used) {
                                memWrappedTokens[len] = wrappedToken2;
                                memRates[len] = rate * rate2 / 1e18;
                                len += 1;
                            }
                        } catch { continue; }
                    }
                }
            } catch { continue; }
        }
        wrappedTokens = new IERC20[](len + 1);
        rates = new uint256[](len + 1);
        for (uint256 i = 0; i < len; i++) {
            wrappedTokens[i] = memWrappedTokens[i];
            rates[i] = memRates[i];
        }
        wrappedTokens[len] = token;
        rates[len] = 1e18;
    }
}


// File @openzeppelin/contracts/utils/math/SafeMath.sol@v4.8.3

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
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
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
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


// File contracts/StaikOracle.sol

// SPDX-License-Identifier: UNLICENSED

//     ███████╗████████╗ █████╗ ██╗██╗  ██╗    █████╗ ██╗
//     ██╔════╝╚══██╔══╝██╔══██╗██║██║ ██╔╝   ██╔══██╗██║
//     ███████╗   ██║   ███████║██║█████╔╝    ███████║██║
//     ╚════██║   ██║   ██╔══██║██║██╔═██╗    ██╔══██║██║
//     ███████║   ██║   ██║  ██║██║██║  ██╗██╗██║  ██║██║
//     ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝

pragma solidity ^0.8.0;

/// @notice Import statements for necessary contracts and interfaces
/// @notice Interface for Oracle that defines the getRate function
interface IOracle {
    function getRate(IERC20 srcToken, IERC20 dstToken, IERC20 connector) external view returns (uint256 rate, uint256 weight);
}

/// @notice StaikOracle contract that extends OwnableUpgradeable
contract StaikOracle is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // DAO governance multisig
    address public DAO;

    enum OracleType { WETH, ETH, WETH_ETH }

    event OracleAdded(IOracle oracle, OracleType oracleType);
    event OracleRemoved(IOracle oracle, OracleType oracleType);
    event ConnectorAdded(IERC20 connector);
    event ConnectorRemoved(IERC20 connector);
    event MultiWrapperUpdated(MultiWrapper multiWrapper);

    /// @notice EnumerableSet of WETH oracles
    EnumerableSet.AddressSet private _wethOracles;
    /// @notice EnumerableSet of ETH oracles
    EnumerableSet.AddressSet private _ethOracles;
    /// @notice EnumerableSet of connector tokens
    EnumerableSet.AddressSet private _connectors;
    /// @notice MultiWrapper contract instance
    MultiWrapper public multiWrapper;

    /// @notice Constant base token (represents ETH)
    IERC20 private constant _BASE = IERC20(0x0000000000000000000000000000000000000000);
    
    IERC20 private constant _NONE = IERC20(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
    
    /// @notice Immutable wrapped base token (represents WETH)
    IERC20 private _wBase;

    constructor(
        MultiWrapper _multiWrapper,
        IOracle[] memory existingOracles,
        OracleType[] memory oracleTypes,
        IERC20[] memory existingConnectors,
        IERC20 wBase
    ) {

    // temporarily set owner to DAO
    DAO = msg.sender;

    require(existingOracles.length == oracleTypes.length, "Arrays length mismatch");
    multiWrapper = _multiWrapper;
    emit MultiWrapperUpdated(_multiWrapper);
    for (uint256 i = 0; i < existingOracles.length; i++) {
        if (oracleTypes[i] == OracleType.WETH) {
            require(_wethOracles.add(address(existingOracles[i])), "Oracle already added");
        } else if (oracleTypes[i] == OracleType.ETH) {
            require(_ethOracles.add(address(existingOracles[i])), "Oracle already added");
        } else if (oracleTypes[i] == OracleType.WETH_ETH) {
            require(_wethOracles.add(address(existingOracles[i])), "Oracle already added");
            require(_ethOracles.add(address(existingOracles[i])), "Oracle already added");
        } else {
            revert("Invalid OracleTokenKind");
        }
        emit OracleAdded(existingOracles[i], oracleTypes[i]);
    }
    for (uint256 i = 0; i < existingConnectors.length; i++) {
        require(_connectors.add(address(existingConnectors[i])), "Connector already added");
        emit ConnectorAdded(existingConnectors[i]);
    }
    _wBase = wBase;
    }

    // modifier for DAO governance to call functions
    modifier onlyDAO {
        require(msg.sender == DAO, "Only DAO can call this function");
        _;
    }

    // transition to DAO governance
    function setDAO(address _multisig) external onlyDAO {
        require(
            _multisig != address(0) 
        );
        DAO = _multisig;
    } 
   
    /// @notice Function to set the MultiWrapper contract instance
    function setMultiWrapper(MultiWrapper _multiWrapper) external onlyDAO {
        multiWrapper = _multiWrapper;
        emit MultiWrapperUpdated(_multiWrapper);
    }

    /// @notice Function to add an oracle with the specified OracleType
    function addOracle(IOracle oracle, OracleType oracleKind) external onlyDAO {
        if (oracleKind == OracleType.WETH) {
            require(_wethOracles.add(address(oracle)), "Oracle already added");
        } else if (oracleKind == OracleType.ETH) {
            require(_ethOracles.add(address(oracle)), "Oracle already added");
        } else if (oracleKind == OracleType.WETH_ETH) {
            require(_wethOracles.add(address(oracle)), "Oracle already added");
            require(_ethOracles.add(address(oracle)), "Oracle already added");
        } else {
            revert("Invalid OracleTokenKind");
        }
        emit OracleAdded(oracle, oracleKind);
    }

    /// @notice Function to remove an oracle with the specified OracleType
    function removeOracle(IOracle oracle, OracleType oracleKind) external onlyDAO {
        if (oracleKind == OracleType.WETH) {
            require(_wethOracles.remove(address(oracle)), "Unknown oracle");
        } else if (oracleKind == OracleType.ETH) {
            require(_ethOracles.remove(address(oracle)), "Unknown oracle");
        } else if (oracleKind == OracleType.WETH_ETH) {
            require(_wethOracles.remove(address(oracle)), "Unknown oracle");
            require(_ethOracles.remove(address(oracle)), "Unknown oracle");
        } else {
            revert("Invalid OracleTokenKind");
        }
        emit OracleRemoved(oracle, oracleKind);
    }

    /// @notice Function to add a connector token
    function addConnector(IERC20 connector) external onlyDAO{
        require(_connectors.add(address(connector)), "Connector already added");
        emit ConnectorAdded(connector);
    }

    /// @notice Function to remove a connector token
    function removeConnector(IERC20 connector) external onlyDAO {
        require(_connectors.remove(address(connector)), "Unknown connector");
        emit ConnectorRemoved(connector);
    }

    /// @notice Function to retrieve all oracles and their types
    function oracles() public view returns (IOracle[] memory allOracles, OracleType[] memory oracleTypes) {
        IOracle[] memory oraclesBuffer = new IOracle[](_wethOracles._inner._values.length + _ethOracles._inner._values.length);
        OracleType[] memory oracleTypesBuffer = new OracleType[](oraclesBuffer.length);
        for (uint256 i = 0; i < _wethOracles._inner._values.length; i++) {
            oraclesBuffer[i] = IOracle(address(uint160(uint256(_wethOracles._inner._values[i]))));
            oracleTypesBuffer[i] = OracleType.WETH;
        }

        uint256 actualItemsCount = _wethOracles._inner._values.length;

        for (uint256 i = 0; i < _ethOracles._inner._values.length; i++) {
            OracleType kind = OracleType.ETH;
            uint256 oracleIndex = actualItemsCount;
            IOracle oracle = IOracle(address(uint160(uint256(_ethOracles._inner._values[i]))));
            for (uint j = 0; j < oraclesBuffer.length; j++) {
                if (oraclesBuffer[j] == oracle) {
                    oracleIndex = j;
                    kind = OracleType.WETH_ETH;
                    break;
                }
            }
            if (kind == OracleType.ETH) {
                actualItemsCount++;
            }
            oraclesBuffer[oracleIndex] = oracle;
            oracleTypesBuffer[oracleIndex] = kind;
        }

        allOracles = new IOracle[](actualItemsCount);
        oracleTypes = new OracleType[](actualItemsCount);
        for (uint256 i = 0; i < actualItemsCount; i++) {
            allOracles[i] = oraclesBuffer[i];
            oracleTypes[i] = oracleTypesBuffer[i];
        }
    }

    /// @notice Function to retrieve all connectors
    function connectors() external view returns (IERC20[] memory allConnectors) {
        allConnectors = new IERC20[](_connectors.length());
        for (uint256 i = 0; i < allConnectors.length; i++) {
            allConnectors[i] = IERC20(address(uint160(uint256(_connectors._inner._values[i]))));
        }
    }

    function getRate(IERC20 srcToken, IERC20 dstToken, bool useWrappers) external view returns (uint256 weightedRate) {
        require(srcToken != dstToken, "Tokens should not be the same");
        uint256 totalWeight;
        (IOracle[] memory allOracles, ) = oracles();
        (IERC20[] memory wrappedSrcTokens, uint256[] memory srcRates) = _getWrappedTokens(srcToken, useWrappers);
        (IERC20[] memory wrappedDstTokens, uint256[] memory dstRates) = _getWrappedTokens(dstToken, useWrappers);
        bytes32[] memory connectors_ = _connectors._inner._values;

        for (uint256 k1 = 0; k1 < wrappedSrcTokens.length; k1++) {
            for (uint256 k2 = 0; k2 < wrappedDstTokens.length; k2++) {
                if (wrappedSrcTokens[k1] == wrappedDstTokens[k2]) {
                    return srcRates[k1].mul(dstRates[k2]).div(1e18);
                }
                for (uint256 j = 0; j < connectors_.length; j++) {
                    if (IERC20(address(uint160(uint256(connectors_[j])))) == wrappedSrcTokens[k1] || IERC20(address(uint160(uint256(connectors_[j])))) == wrappedDstTokens[k2]) {
                        continue;
                    }
                    for (uint256 i = 0; i < allOracles.length; i++) {
                            try allOracles[i].getRate(wrappedSrcTokens[k1], wrappedDstTokens[k2], IERC20(address(uint160(uint256(connectors_[j]))))) returns (uint256 rate, uint256 weight) {
                            rate = rate.mul(srcRates[k1]).mul(dstRates[k2]).div(1e36);
                            weight = weight.mul(weight);
                            weightedRate = weightedRate.add(rate.mul(weight));
                            totalWeight = totalWeight.add(weight);
                        } catch {}  // solhint-disable-line no-empty-blocks
                    }
                }
            }
        }
        if (totalWeight > 0) {
            weightedRate = weightedRate.div(totalWeight);
        }
    }





    /// @notice Function to get the weighted rate to ETH for the specified token using the available oracles and connectors
    function getRateToEth(IERC20 srcToken, bool useSrcWrappers) external view returns (uint256 weightedRate) {
        uint256 totalWeight;
        (IERC20[] memory wrappedSrcTokens, uint256[] memory srcRates) = _getWrappedTokens(srcToken, useSrcWrappers);
        IERC20[2] memory wrappedDstTokens = [_BASE, _wBase];
        bytes32[][2] memory wrappedOracles = [_ethOracles._inner._values, _wethOracles._inner._values];
        bytes32[] memory connectors_ = _connectors._inner._values;

        for (uint256 k1 = 0; k1 < wrappedSrcTokens.length; k1++) {
            for (uint256 k2 = 0; k2 < wrappedDstTokens.length; k2++) {
                if (wrappedSrcTokens[k1] == wrappedDstTokens[k2]) {
                    return srcRates[k1];
                }
                for (uint256 j = 0; j < connectors_.length; j++) {
                    IERC20 connector = IERC20(address(uint160(uint256(connectors_[j]))));
                    if (connector == wrappedSrcTokens[k1] || connector == wrappedDstTokens[k2]) {
                        continue;
                    }
                    for (uint256 i = 0; i < wrappedOracles[k2].length; i++) {
                        try IOracle(address(uint160(uint256(wrappedOracles[k2][i])))).getRate(
                            wrappedSrcTokens[k1],
                            wrappedDstTokens[k2],
                            connector
                        ) returns (uint256 rate, uint256 weight) {
                            rate = rate * srcRates[k1] / 1e18;
                            weight = weight * weight;
                            weightedRate += rate * weight;
                            totalWeight += weight;
                        } catch {}  // solhint-disable-line no-empty-blocks
                    }
                }
            }
        }
        if (totalWeight > 0) {
            weightedRate /= totalWeight;
        }
    }

    /// @notice Internal function to get wrapped tokens and their rates
    function _getWrappedTokens(IERC20 token, bool useWrappers) internal view returns (IERC20[] memory wrappedTokens, uint256[] memory rates) {
        if (useWrappers) {
            return multiWrapper.getWrappedTokens(token);
        }

        wrappedTokens = new IERC20[](1);
        wrappedTokens[0] = token;
        rates = new uint256[](1);
        rates[0] = uint256(1e18);
    }
}