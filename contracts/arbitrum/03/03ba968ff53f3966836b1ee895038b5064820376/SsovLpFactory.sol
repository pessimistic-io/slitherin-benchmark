// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

// OpenZeppelin Contracts (last updated v4.8.0) (proxy/Clones.sol)

/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 *
 * _Available since v3.4._
 */
library Clones {
    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function clone(address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create(0, 0x09, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone. Using the same `implementation` and `salt` multiple time will revert, since
     * the clones cannot be deployed twice at the same address.
     */
    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create2(0, 0x09, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x38), deployer)
            mstore(add(ptr, 0x24), 0x5af43d82803e903d91602b57fd5bf3ff)
            mstore(add(ptr, 0x14), implementation)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73)
            mstore(add(ptr, 0x58), salt)
            mstore(add(ptr, 0x78), keccak256(add(ptr, 0x0c), 0x37))
            predicted := keccak256(add(ptr, 0x43), 0x55)
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt)
        internal
        view
        returns (address predicted)
    {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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

/**
                    ███████╗███████╗ ██████╗ ██╗   ██╗
                    ██╔════╝██╔════╝██╔═══██╗██║   ██║
                    ███████╗███████╗██║   ██║██║   ██║
                    ╚════██║╚════██║██║   ██║╚██╗ ██╔╝
                    ███████║███████║╚██████╔╝ ╚████╔╝ 
                    ╚══════╝╚══════╝ ╚═════╝   ╚═══╝  
                                                      
                    ██████╗ ██╗     ██████╗          
                    ██╔═══██╗██║     ██╔══██╗         
                    ██║   ██║██║     ██████╔╝         
                    ██║   ██║██║     ██╔═══╝          
                    ╚██████╔╝███████╗██║              
                    ╚═════╝ ╚══════╝╚═╝  

                      SSOV Option Liquidity Pools
                
      Allows Lps to add liquidity for select option tokens along with a discount
      to market price. Option token holders can sell their tokens to Lps at
      anytime during the option token's epoch.
*/

// Interfaces

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 * NOTE: Modified to include symbols and decimals.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

// Libraries

// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1);

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator,
        Rounding rounding
    ) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10**64) {
                value /= 10**64;
                result += 64;
            }
            if (value >= 10**32) {
                value /= 10**32;
                result += 32;
            }
            if (value >= 10**16) {
                value /= 10**16;
                result += 16;
            }
            if (value >= 10**8) {
                value /= 10**8;
                result += 8;
            }
            if (value >= 10**4) {
                value /= 10**4;
                result += 4;
            }
            if (value >= 10**2) {
                value /= 10**2;
                result += 2;
            }
            if (value >= 10**1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10**result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result * 8) < value ? 1 : 0);
        }
    }
}

// OpenZeppelin Contracts (last updated v4.6.0) (utils/math/SafeMath.sol)

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

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

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
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
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
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
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

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
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
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
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
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
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

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

// Contracts

// Interfaces

interface IAssetSwapper {
    function swapAsset(
        address from,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) external returns (uint256);
}

interface IOptionPricing {
    function getOptionPrice(
        bool isPut,
        uint256 expiry,
        uint256 strike,
        uint256 lastPrice,
        uint256 baseIv
    ) external view returns (uint256);
}

struct EpochStrikeData {
    address strikeToken;
    uint256 totalCollateral;
    uint256 activeCollateral;
    uint256 totalPremiums;
    uint256 checkpointPointer;
    uint256[] rewardStoredForPremiums;
    uint256[] rewardDistributionRatiosForPremiums;
}

struct EpochData {
    bool expired;
    uint256 startTime;
    uint256 expiry;
    uint256 settlementPrice;
    uint256 totalCollateralBalance; // Premium + Deposits from all strikes
    uint256 collateralExchangeRate; // Exchange rate for collateral to underlying (Only applicable to CALL options)
    uint256 settlementCollateralExchangeRate; // Exchange rate for collateral to underlying on settlement (Only applicable to CALL options)
    uint256[] strikes;
    uint256[] totalRewardsCollected;
    uint256[] rewardDistributionRatios;
    address[] rewardTokensToDistribute;
}

interface ISSOV {
    function getEpochStrikeData(uint256 epoch, uint256 strike)
        external
        view
        returns (EpochStrikeData memory);

    function getEpochData(uint256 epoch)
        external
        view
        returns (EpochData memory);

    function currentEpoch() external view returns (uint256);

    function collateralPrecision() external view returns (uint256);

    function getVolatility(uint256) external view returns (uint256);

    function getUnderlyingPrice() external view returns (uint256);

    function getEpochTimes(uint256 _epoch)
        external
        view
        returns (uint256, uint256);

    function isPut() external view returns (bool);

    function underlyingSymbol() external view returns (string memory);

    function collateralToken() external view returns (address);
}

// Contracts

// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

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
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

/// @title Lighter version of the Openzeppelin Pausable contract
/// @author witherblock
/// @notice Helps pause a contract to block the execution of selected functions
/// @dev Difference from the Openzeppelin version is changing the modifiers to internal fns and requires to reverts
abstract contract Pausable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Internal function to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _whenNotPaused() internal view {
        if (paused()) revert ContractPaused();
    }

    /**
     * @dev Internal function to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _whenPaused() internal view {
        if (!paused()) revert ContractNotPaused();
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual {
        _whenNotPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual {
        _whenPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }

    error ContractPaused();
    error ContractNotPaused();
}

/// @title ContractWhitelist
/// @author witherblock
/// @notice A helper contract that lets you add a list of whitelisted contracts that should be able to interact with restricited functions
abstract contract ContractWhitelist {
    /// @dev contract => whitelisted or not
    mapping(address => bool) public whitelistedContracts;

    /*==== SETTERS ====*/

    /// @dev add to the contract whitelist
    /// @param _contract the address of the contract to add to the contract whitelist
    function _addToContractWhitelist(address _contract) internal {
        require(isContract(_contract), "Address must be a contract");
        require(
            !whitelistedContracts[_contract],
            "Contract already whitelisted"
        );

        whitelistedContracts[_contract] = true;

        emit AddToContractWhitelist(_contract);
    }

    /// @dev remove from  the contract whitelist
    /// @param _contract the address of the contract to remove from the contract whitelist
    function _removeFromContractWhitelist(address _contract) internal {
        require(whitelistedContracts[_contract], "Contract not whitelisted");

        whitelistedContracts[_contract] = false;

        emit RemoveFromContractWhitelist(_contract);
    }

    // modifier is eligible sender modifier
    function _isEligibleSender() internal view {
        // the below condition checks whether the caller is a contract or not
        if (msg.sender != tx.origin)
            require(
                whitelistedContracts[msg.sender],
                "Contract must be whitelisted"
            );
    }

    /*==== VIEWS ====*/

    /// @dev checks for contract or eoa addresses
    /// @param addr the address to check
    /// @return bool whether the passed address is a contract address
    function isContract(address addr) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /*==== EVENTS ====*/

    event AddToContractWhitelist(address indexed _contract);

    event RemoveFromContractWhitelist(address indexed _contract);
}

// Libraries

contract BaseSsovLp is Ownable, ReentrancyGuard, Pausable, ContractWhitelist {
    using SafeERC20 for IERC20;

    uint256 internal constant MULTI_ADD_LIMIT = 5;
    uint256 internal constant PERCENT = 1e2;
    uint256 internal constant USDC_DECIMALS = 1e6;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    uint256 internal constant DUST_THRESHOLD = 1e7; // $10
    uint256 internal constant TOKEN_DUST_THRESHOLD = 1e15; // 0.001 $token
    uint256 internal constant AMOUNT_PRICE_TO_USDC_DECIMALS =
        (1e18 * 1e8) / 1e6;

    struct OptionTokenInfo {
        // SSOV for option token
        address ssov;
        // Strike price
        uint256 strike;
        // USD liquidity
        uint256 usdLiquidity;
        // Underlying token liquidity
        uint256 underlyingLiquidity;
    }

    struct Addresses {
        // USD token address (1e6 precision)
        address usd;
        // Underlying token address (1e18 precision)
        address underlying;
        // OptionPricing address
        address optionPricing;
        // AssetSwapper address
        address assetSwapper;
    }

    Addresses public addresses;

    /// @dev mapping (option token => OptionTokenInfo)
    mapping(address => OptionTokenInfo) public getOptionTokenInfo;
    /// @dev mapping (ssov address =>  epochs)
    mapping(address => uint256[]) internal ssovEpochs;
    /// @dev mapping (ssov address =>  expires)
    mapping(address => uint256[]) internal ssovExpiries;
    /// @dev mapping (token address => (isPut => SSOV address))
    mapping(address => mapping(bool => address)) internal tokenVaultRegistry;

    /*==== EVENTS ====*/

    event UsdLiquidityForStrikeAdded(
        address indexed epochStrikeToken,
        address indexed buyer,
        uint256 lpId,
        uint256 usdLiquidity
    );
    event UnderlyingLiquidityForStrikeAdded(
        address indexed epochStrikeToken,
        address indexed buyer,
        uint256 lpId,
        uint256 baseLiquidity
    );
    event LpPositionFilled(
        address indexed epochStrikeToken,
        uint256 lpId,
        uint256 amount,
        uint256 usdPremium,
        uint256 underlyingPremium,
        address indexed seller
    );
    event LpPositionKilled(address indexed epochStrikeToken, uint256 index);
    event LpDustCleared(address indexed epochStrikeToken, uint256 index);
    event SsovForTokenRegistered(address token, bool isPut, address ssov);
    event SsovForTokenRemoved(address token, bool isPut, address ssov);
    event AddressesSet(Addresses _addresses);
    event SsovExpiryUpdated(address ssov, uint256 expiry);
    event EmergencyWithdrawn(address caller);

    /*==== ADMIN METHODS ====*/

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the admin
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(address _contract) external onlyOwner {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the admin
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(address _contract) external onlyOwner {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Sets (adds) a list of addresses to the address list
    /// @dev Can only be called by the owner
    /// @param _addresses addresses of contracts in the Addresses struct
    function setAddresses(Addresses calldata _addresses) external onlyOwner {
        addresses = _addresses;
        emit AddressesSet(_addresses);
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by the owner
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdrawn(address[] calldata tokens, bool transferNative)
        external
        onlyOwner
    {
        _whenPaused();
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i = 0; i < tokens.length; i++) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        emit EmergencyWithdrawn(msg.sender);
    }

    /// @notice Register the vault for token
    /// @param token Token address
    /// @param vault SSOV address
    /// @param isPut isPut
    function registerSsovForToken(
        address token,
        address vault,
        bool isPut
    ) external onlyOwner {
        require(isPut == getSsov(vault).isPut(), "invalid isPut");
        require(
            token != address(0) && vault != address(0),
            "addresses cannot be null"
        );
        tokenVaultRegistry[token][isPut] = vault;
        emit SsovForTokenRegistered(token, isPut, vault);
    }

    /// @notice Unregister the vault for token
    /// @param token Token address
    /// @param isPut Is puts
    function unregisterSsovForToken(address token, bool isPut)
        external
        onlyOwner
    {
        address toRemoveVault = tokenVaultRegistry[token][isPut];
        tokenVaultRegistry[token][isPut] = address(0);
        emit SsovForTokenRemoved(token, isPut, toRemoveVault);
    }

    /*==== BOT METHODS ====*/

    /// @notice Updates the list of epoch expiries
    /// @dev Can be run by a bot
    /// @param ssov addresses of ssov
    /// @param epoch epoch to update
    function updateSsovEpoch(address ssov, uint256 epoch)
        external
        returns (bool)
    {
        uint256 expiry = getSsovExpiry(ssov, epoch);
        require(expiry > block.timestamp, "Expiry must be in the future");
        if (
            ssovExpiries[ssov].length == 0 ||
            ssovExpiries[ssov][ssovExpiries[ssov].length - 1] != expiry
        ) {
            ssovExpiries[ssov].push(expiry);
            ssovEpochs[ssov].push(epoch);
            emit SsovExpiryUpdated(ssov, expiry);
            return true;
        }
        return false;
    }

    /*==== INTERNAL METHODS ====*/

    /// @dev Internal function to swap underlying to USD
    /// @param amount Amount of underlying to swap
    /// @param minAmountOut Amount of minimum usd to receive (slippage control parameter)
    /// @param swapperId The swapperId which dictates the amm path to use while swapping
    /// @return usdReceived The amount of USD received after the swap
    function _swapUnderlyingToUsd(
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) internal returns (uint256 usdReceived) {
        usdReceived = IAssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.underlying,
            addresses.usd,
            amount,
            minAmountOut,
            swapperId
        );
    }

    /// @notice Returns SSOV contract
    /// @param vault SSOV address
    function getSsov(address vault) internal pure returns (ISSOV) {
        return ISSOV(vault);
    }

    /*==== SSOV VIEW METHODS ====*/

    /// @notice Returns the SSOV expiry
    /// @param vault SSOV address
    /// @param epoch SSOV epoch
    function getSsovExpiry(address vault, uint256 epoch)
        public
        view
        returns (uint256)
    {
        (, uint256 expiry) = getSsov(vault).getEpochTimes(epoch);
        return expiry;
    }

    /// @notice Returns the SSOV option token address
    /// @param vault SSOV address
    /// @param epoch SSOV epoch
    /// @param strike SSOV strike
    function getSsovOptionToken(
        address vault,
        uint256 epoch,
        uint256 strike
    ) public view returns (address) {
        return getSsov(vault).getEpochStrikeData(epoch, strike).strikeToken;
    }

    /// @notice Returns the SSOV epoch strikes
    /// @param vault SSOV address
    /// @param epoch SSOV epoch
    function getSsovEpochStrikes(address vault, uint256 epoch)
        public
        view
        returns (uint256[] memory strikes)
    {
        return getSsov(vault).getEpochData(epoch).strikes;
    }

    /// @notice Returns the current SSOV epoch
    /// @param vault SSOV address
    function getSsovEpoch(address vault) public view returns (uint256) {
        return getSsov(vault).currentEpoch();
    }

    /// @notice Returns the current underlying price of an SSOV
    /// @param vault SSOV address
    function getSsovUnderlyingPrice(address vault)
        public
        view
        returns (uint256)
    {
        return getSsov(vault).getUnderlyingPrice();
    }

    /// @notice Returns true if the epoch has expired for an SSOV
    /// @param vault SSOV address
    /// @param epoch SSOV epoch
    function hasEpochExpired(address vault, uint256 epoch)
        public
        view
        returns (bool)
    {
        return getSsovExpiry(vault, epoch) <= block.timestamp;
    }

    /// @notice Returns the current volatility of SSOV strike
    /// @param vault SSOV address
    /// @param strike SSOV strike
    function getSsovVolatility(address vault, uint256 strike)
        public
        view
        returns (uint256)
    {
        return getSsov(vault).getVolatility(strike);
    }

    /// @notice Calculate premium for an option
    /// @param isPut call or put options
    /// @param expiry expiry
    /// @param strike Strike price of the option
    /// @param amount Amount of options (1e18 precision)
    /// @param volatility Volatility of the option
    /// @param vault Address of ssov
    /// @return premium in USD
    function calculatePremium(
        bool isPut,
        uint256 strike,
        uint256 expiry,
        uint256 amount,
        uint256 volatility,
        address vault
    ) public view returns (uint256) {
        return
            (IOptionPricing(addresses.optionPricing).getOptionPrice(
                isPut,
                expiry,
                strike,
                getSsovUnderlyingPrice(vault),
                volatility
            ) * amount) / AMOUNT_PRICE_TO_USDC_DECIMALS;
    }

    /// @notice Calculate premium for an option
    /// @param ssov address of ssov
    /// @param usdPremium premium in USD
    /// @return premium in underlying
    function getPremiumInUnderlying(address ssov, uint256 usdPremium)
        public
        view
        returns (uint256)
    {
        return
            Math.mulDiv(
                usdPremium,
                PRICE_DECIMALS * (10**IERC20(addresses.underlying).decimals()),
                getSsovUnderlyingPrice(ssov) * USDC_DECIMALS
            );
    }

    /// @notice Returns the epochs of an ssov
    /// @param vault SSOV address
    function getSsovEpochs(address vault)
        public
        view
        returns (uint256[] memory)
    {
        return ssovEpochs[vault];
    }

    /// @notice Returns the expiries of an ssov
    /// @param vault SSOV address
    function getSsovEpochExpiries(address vault)
        external
        view
        returns (uint256[] memory)
    {
        return ssovExpiries[vault];
    }

    /// @notice Returns the token vault registry
    /// @param token Token address
    /// @param isPut isPut
    function getTokenVaultRegistry(address token, bool isPut)
        external
        view
        returns (address)
    {
        return tokenVaultRegistry[token][isPut];
    }

    /// @notice Returns the SSOV option token addresses for an epoch
    /// @param vault SSOV address
    /// @param epoch SSOV epoch
    function getSsovOptionTokens(address vault, uint256 epoch)
        external
        view
        returns (address[] memory tokens)
    {
        uint256[] memory strikes = getSsovEpochStrikes(vault, epoch);
        tokens = new address[](strikes.length);
        for (uint256 i; i < strikes.length; ++i) {
            tokens[i] = getSsovOptionToken(vault, epoch, strikes[i]);
        }
    }

    /// @notice Returns the collateral precision of an SSOV
    /// @param vault SSOV address
    function getSsovCollateralPrecision(address vault)
        external
        view
        returns (uint256)
    {
        return getSsov(vault).collateralPrecision();
    }

    /*==== ERRORS ====*/

    error AmountTooSmall();
    error InsuffientLiquidity();
    error InvalidDiscount();
    error InvalidEpochToFill();
    error InvalidLiquidity();
    error InvalidLpIndex();
    error InvalidParams();
    error InvalidStrike();
    error LpPositionDead();
    error OnlyBuyerCanKill();
    error SsovDoesNotExist();
    error SsovEpochExpired();
}

// OpenZeppelin Contracts (last updated v4.8.1) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!Address.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

contract SsovLp is BaseSsovLp, Initializable {
    using SafeERC20 for IERC20;

    struct LpPosition {
        // Id for LP position
        uint256 lpId;
        // Epoch for Lp position
        uint256 epoch;
        // Strike price
        uint256 strike;
        // Available usd liquidity in Lp position
        uint256 usdLiquidity;
        // Available underlying liquidity in Lp position
        uint256 underlyingLiquidity;
        // Amount of usd liquidity used to purchase options
        uint256 usdLiquidityUsed;
        // Amount of underlying liquidity used to purchase options
        uint256 underlyingLiquidityUsed;
        // Discount in % to market price
        uint256 discount;
        // Amount of options purchased
        uint256 purchased;
        // maxTokensToFill Max tokens to buy
        uint256 maxTokensToFill;
        // Buyer address
        address buyer;
        // Is position killed
        bool killed;
    }

    string public name;
    string public underlyingSymbol;

    /// @dev mapping (epoch strike token address) => LpPosition[])
    mapping(address => LpPosition[]) internal allLpPositions;
    /// @dev mapping (user => striken token => lpId[])
    mapping(address => mapping(address => uint256[])) internal userLpPositions;

    /*==== INITIALIZE ====*/

    /// @dev An SsovLp contract maps to the same underlying and duration.
    /// @param _name Name of contract, i.e., ETH-MONTHLY, RDPX-WEEKLY
    /// @param _underlyingSymbol The symbol of the contract
    /// @param _addresses Addresses of the contract
    /// @param _sender Deployer address
    function initialize(
        string memory _name,
        string memory _underlyingSymbol,
        Addresses memory _addresses,
        address _sender
    ) external initializer {
        name = _name;
        underlyingSymbol = _underlyingSymbol;
        addresses = _addresses;

        IERC20(addresses.underlying).safeIncreaseAllowance(
            addresses.assetSwapper,
            type(uint256).max
        );

        _transferOwnership(_sender);
    }

    /*==== USER METHODS ====*/

    /**
     * Adds multiple new Lp positions for a token
     * @param token underlying token address
     * @param isUsd Is the liquidity USD or underlying
     * @param isPut Is the Lp for puts
     * @param strike Strike to purchase at
     * @param liquidity Liquidity per strike.
     *  Must be in 6 decimals if isUsd = true else 18 decimals
     * @param discount Discount on volatility
     * @param maxTokensToFill Max tokens to buy
     * @param to Address to send option tokens to if purchase succeeds
     * @return Whether new Lp position was created
     */
    function addToLp(
        address token,
        bool isUsd,
        bool isPut,
        uint256 strike,
        uint256 liquidity,
        uint256 discount,
        uint256 maxTokensToFill,
        address to
    ) external nonReentrant returns (bool) {
        _isEligibleSender();
        _whenNotPaused();

        address ssov = tokenVaultRegistry[token][isPut];
        if (ssov == address(0)) {
            revert SsovDoesNotExist();
        }

        if (isUsd) {
            return
                _addUsd(ssov, strike, liquidity, discount, maxTokensToFill, to);
        }
        return
            _addUnderlying(
                ssov,
                strike,
                liquidity,
                discount,
                maxTokensToFill,
                to
            );
    }

    /**
     * Adds multiple new Lp positions for a token
     * @param token underlying token address
     * @param isUsd Is the liquidity USD or underlying
     * @param isPut Is the Lp for puts
     * @param strikes Strikes to purchase at
     * @param liquidity Liquidity per strike.
     *  Must be in 6 decimals if isUsd = true else 18 decimals
     * @param discount Discount on volatility
     * @param maxTokensToFill Max tokens to buy
     * @param to Address to send option tokens to if purchase succeeds
     * @return Whether new Lp position was created
     */
    function multiAddToLp(
        address token,
        bool isUsd,
        bool isPut,
        uint256[] memory strikes,
        uint256[] memory liquidity,
        uint256[] memory discount,
        uint256[] memory maxTokensToFill,
        address to
    ) external nonReentrant returns (bool) {
        _isEligibleSender();
        _whenNotPaused();

        address ssov = tokenVaultRegistry[token][isPut];
        if (ssov == address(0)) {
            revert SsovDoesNotExist();
        }
        if (
            strikes.length == 0 ||
            strikes.length > MULTI_ADD_LIMIT ||
            strikes.length != liquidity.length ||
            liquidity.length != discount.length
        ) {
            revert InvalidParams();
        }

        for (uint256 i; i < strikes.length; ++i) {
            if (isUsd) {
                _addUsd(
                    ssov,
                    strikes[i],
                    liquidity[i],
                    discount[i],
                    maxTokensToFill[i],
                    to
                );
            } else {
                _addUnderlying(
                    ssov,
                    strikes[i],
                    liquidity[i],
                    discount[i],
                    maxTokensToFill[i],
                    to
                );
            }
        }
        return true;
    }

    /// @dev helper function to check if params are valid before adding
    function _canAddToLp(
        bool isUsd,
        address ssov,
        address strikeToken,
        uint256 liquidity,
        uint256 discount,
        uint256 currentEpoch
    ) internal view returns (bool) {
        if (isUsd && liquidity < DUST_THRESHOLD) {
            revert InvalidLiquidity();
        }
        if (!isUsd && liquidity < TOKEN_DUST_THRESHOLD) {
            revert InvalidLiquidity();
        }
        if (discount == 0 || discount > 100) {
            revert InvalidDiscount();
        }
        if (hasEpochExpired(ssov, currentEpoch)) {
            revert SsovEpochExpired();
        }
        if (strikeToken == address(0)) {
            revert InvalidStrike();
        }
        return true;
    }

    /// @dev helper function to cache unseen tokens
    function _cacheStrikeToken(
        address ssov,
        address strikeToken,
        uint256 strike
    ) internal returns (bool) {
        if (getOptionTokenInfo[strikeToken].ssov == address(0)) {
            getOptionTokenInfo[strikeToken].ssov = address(ssov);
            getOptionTokenInfo[strikeToken].strike = strike;
        }
        return true;
    }

    /// @dev helper function to create an Lp
    function _createLp(
        address strikeToken,
        uint256 strike,
        uint256 usdLiquidity,
        uint256 underlyingLiquidity,
        uint256 discount,
        uint256 currentEpoch,
        uint256 maxTokensToFill,
        address buyer
    ) internal returns (uint256 lpId, LpPosition memory lp) {
        lpId = allLpPositions[strikeToken].length;

        lp.lpId = lpId;
        lp.epoch = currentEpoch;
        lp.strike = strike;
        lp.usdLiquidity = usdLiquidity;
        lp.underlyingLiquidity = underlyingLiquidity;
        lp.discount = discount;
        lp.maxTokensToFill = maxTokensToFill;
        lp.buyer = buyer;

        allLpPositions[strikeToken].push(lp);
        userLpPositions[buyer][strikeToken].push(lpId);
    }

    /// @dev helper function to add usd liquidity
    function _addUsd(
        address ssov,
        uint256 strike,
        uint256 liquidity,
        uint256 discount,
        uint256 maxTokensToFill,
        address buyer
    ) internal returns (bool) {
        uint256 currentEpoch = getSsovEpoch(ssov);
        address strikeToken = getSsovOptionToken(ssov, currentEpoch, strike);

        _canAddToLp({
            isUsd: true,
            ssov: ssov,
            strikeToken: strikeToken,
            liquidity: liquidity,
            discount: discount,
            currentEpoch: currentEpoch
        });
        _cacheStrikeToken({
            ssov: ssov,
            strikeToken: strikeToken,
            strike: strike
        });
        (uint256 lpId, ) = _createLp({
            strikeToken: strikeToken,
            strike: strike,
            usdLiquidity: liquidity,
            underlyingLiquidity: 0,
            discount: discount,
            currentEpoch: currentEpoch,
            maxTokensToFill: maxTokensToFill,
            buyer: buyer
        });

        getOptionTokenInfo[strikeToken].usdLiquidity += liquidity;

        IERC20(addresses.usd).safeTransferFrom(
            msg.sender,
            address(this),
            liquidity
        );

        emit UsdLiquidityForStrikeAdded(strikeToken, buyer, lpId, liquidity);
        return true;
    }

    /// @dev helper function to add underlying liquidity
    function _addUnderlying(
        address ssov,
        uint256 strike,
        uint256 liquidity,
        uint256 discount,
        uint256 maxTokensToFill,
        address buyer
    ) internal returns (bool) {
        uint256 currentEpoch = getSsovEpoch(ssov);
        address strikeToken = getSsovOptionToken(ssov, currentEpoch, strike);

        _canAddToLp({
            isUsd: false,
            ssov: ssov,
            strikeToken: strikeToken,
            liquidity: liquidity,
            discount: discount,
            currentEpoch: currentEpoch
        });
        _cacheStrikeToken({
            ssov: ssov,
            strikeToken: strikeToken,
            strike: strike
        });
        (uint256 lpId, ) = _createLp({
            strikeToken: strikeToken,
            strike: strike,
            usdLiquidity: 0,
            underlyingLiquidity: liquidity,
            discount: discount,
            currentEpoch: currentEpoch,
            maxTokensToFill: maxTokensToFill,
            buyer: buyer
        });

        getOptionTokenInfo[strikeToken].underlyingLiquidity += liquidity;

        IERC20(addresses.underlying).safeTransferFrom(
            msg.sender,
            address(this),
            liquidity
        );

        emit UnderlyingLiquidityForStrikeAdded(
            strikeToken,
            buyer,
            lpId,
            liquidity
        );
        return true;
    }

    /**
     * Fills an Lp position with available liquidity
     * @param isPut is put option
     * @param outUsd give user the option to receive USDC for liquidity in ETH,
     * @param strikeToken epoch strike token address
     * @param lpIndex Index of Lp position
     * @param amount Amount of options to buy from each Lp position
     * @param minAmountOut The minimum amount of usd to receive if outUsd is true
     * @param swapperId The swapperId which dictates which amm path will be used
     * @return Whether Lp positions were filled
     */
    function fillLpPosition(
        bool isPut,
        bool outUsd,
        address strikeToken,
        uint256 lpIndex,
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) external nonReentrant returns (bool) {
        _isEligibleSender();
        _whenNotPaused();

        address ssov = getOptionTokenInfo[strikeToken].ssov;
        if (ssov == address(0)) {
            revert SsovDoesNotExist();
        }
        _fillLpPosition(
            isPut,
            outUsd,
            ssov,
            strikeToken,
            lpIndex,
            amount,
            minAmountOut,
            swapperId
        );
        return true;
    }

    /**
     * Fills multiple Lp positions with available liquidity
     * @param isPut is put option
     * @param outUsd give user the option to receive USDC for liquidity in ETH,
     * @param strikeToken epoch strike token address
     * @param lpIndices Index of Lp position
     * @param amount Amount of options to buy from each Lp position
     * @param minAmountOuts The minimum amount out of usd to receive for each LP position
     * @param swapperId The swapperId
     * @return Whether Lp positions were filled
     */
    function multiFillLpPosition(
        bool isPut,
        bool outUsd,
        address strikeToken,
        uint256[] memory lpIndices,
        uint256[] memory amount,
        uint256[] memory minAmountOuts,
        uint256 swapperId
    ) external nonReentrant returns (bool) {
        _isEligibleSender();
        _whenNotPaused();

        address ssov = getOptionTokenInfo[strikeToken].ssov;
        if (ssov == address(0)) {
            revert SsovDoesNotExist();
        }
        if (lpIndices.length == 0 || lpIndices.length != amount.length) {
            revert InvalidParams();
        }

        for (uint256 i; i < lpIndices.length; ++i) {
            _fillLpPosition(
                isPut,
                outUsd,
                ssov,
                strikeToken,
                lpIndices[i],
                amount[i],
                minAmountOuts[i],
                swapperId
            );
        }
        return true;
    }

    /// @dev helper function to fill an Lp position at index
    function _fillLpPosition(
        bool isPut,
        bool outUsd,
        address ssov,
        address strikeToken,
        uint256 lpIndex,
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) internal returns (bool) {
        if (amount <= TOKEN_DUST_THRESHOLD) {
            revert AmountTooSmall();
        }
        if (lpIndex >= allLpPositions[strikeToken].length) {
            revert InvalidLpIndex();
        }

        LpPosition memory lpPosition = allLpPositions[strikeToken][lpIndex];
        if (lpPosition.killed) {
            revert LpPositionDead();
        }
        if (hasEpochExpired(ssov, getSsovEpoch(ssov))) {
            revert InvalidEpochToFill();
        }

        amount = Math.min(amount, lpPosition.maxTokensToFill);

        uint256 volatility = getSsovVolatility(ssov, lpPosition.strike);

        // volatility -= discount
        volatility -= Math.mulDiv(volatility, lpPosition.discount, PERCENT);

        uint256 usdPremium = calculatePremium({
            isPut: isPut,
            strike: lpPosition.strike,
            expiry: getSsovExpiry(ssov, getSsovEpoch(ssov)),
            amount: amount,
            volatility: volatility,
            vault: ssov
        });
        uint256 underlyingPremium;

        if (lpPosition.usdLiquidity != 0) {
            _fillUsd({
                usdPremium: usdPremium,
                usdLiquidity: lpPosition.usdLiquidity,
                strikeToken: strikeToken,
                lpIndex: lpIndex
            });
        } else {
            underlyingPremium = getPremiumInUnderlying(ssov, usdPremium);
            _fillUnderlying({
                outUsd: outUsd,
                strikeToken: strikeToken,
                premium: underlyingPremium,
                underlyingLiquidity: lpPosition.underlyingLiquidity,
                lpIndex: lpIndex,
                minAmountOut: minAmountOut,
                swapperId: swapperId
            });
        }

        allLpPositions[strikeToken][lpIndex].purchased += amount;
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            lpPosition.buyer,
            amount
        );

        emit LpPositionFilled(
            strikeToken,
            lpIndex,
            amount,
            usdPremium,
            underlyingPremium,
            msg.sender
        );
        return true;
    }

    /// @dev helper function to fill an Lp position's usd liquidity
    /// @notice premium is in usd
    function _fillUsd(
        uint256 usdPremium,
        uint256 usdLiquidity,
        address strikeToken,
        uint256 lpIndex
    ) internal returns (bool) {
        if (usdPremium > usdLiquidity) {
            revert InsuffientLiquidity();
        }
        allLpPositions[strikeToken][lpIndex].usdLiquidity -= usdPremium;
        allLpPositions[strikeToken][lpIndex].usdLiquidityUsed += usdPremium;
        getOptionTokenInfo[strikeToken].usdLiquidity -= usdPremium;

        if (
            allLpPositions[strikeToken][lpIndex].usdLiquidity < DUST_THRESHOLD
        ) {
            _clearLpDust(strikeToken, lpIndex);
        }
        IERC20(addresses.usd).safeTransfer(msg.sender, usdPremium);
        return true;
    }

    /// @dev helper function to fill an Lp position's underlying liquidity
    /// @notice premium is in underlying
    function _fillUnderlying(
        bool outUsd,
        address strikeToken,
        uint256 premium,
        uint256 underlyingLiquidity,
        uint256 lpIndex,
        uint256 minAmountOut,
        uint256 swapperId
    ) internal returns (bool) {
        if (premium > underlyingLiquidity) {
            revert InsuffientLiquidity();
        }
        allLpPositions[strikeToken][lpIndex].underlyingLiquidity -= premium;
        allLpPositions[strikeToken][lpIndex].underlyingLiquidityUsed += premium;
        getOptionTokenInfo[strikeToken].underlyingLiquidity -= premium;

        if (
            allLpPositions[strikeToken][lpIndex].underlyingLiquidity <
            TOKEN_DUST_THRESHOLD
        ) {
            _clearLpDust(strikeToken, lpIndex);
        }

        if (outUsd) {
            uint256 usdPremium = _swapUnderlyingToUsd(
                premium,
                minAmountOut,
                swapperId
            );
            IERC20(addresses.usd).safeTransfer(msg.sender, usdPremium);
        } else {
            IERC20(addresses.underlying).safeTransfer(msg.sender, premium);
        }

        return true;
    }

    /// @dev helper function to clear Lp dust position at index
    function _clearLpDust(address strikeToken, uint256 lpIndex)
        internal
        returns (bool)
    {
        LpPosition memory lpPosition = allLpPositions[strikeToken][lpIndex];

        _killAndTransfer(
            strikeToken,
            lpIndex,
            lpPosition.buyer,
            lpPosition.usdLiquidity,
            lpPosition.underlyingLiquidity
        );

        emit LpDustCleared(strikeToken, lpIndex);
        return true;
    }

    /**
     * Kills an active Lp position
     * @param strikeToken epoch strike token address
     * @param lpIndex Index of Lp position
     * @return Whether Lp position is killed
     */
    function killLpPosition(address strikeToken, uint256 lpIndex)
        external
        nonReentrant
        returns (bool)
    {
        _isEligibleSender();
        _whenNotPaused();

        if (getOptionTokenInfo[strikeToken].ssov == address(0)) {
            revert SsovDoesNotExist();
        }
        _killLpPosition(strikeToken, lpIndex);
        return true;
    }

    /**
     * Kills multiple active Lp positions
     * @param strikeToken epoch strike token address
     * @param lpIndices Indices of Lp position
     * @return Whether Lp positions are killed
     */
    function multiKillLpPosition(
        address strikeToken,
        uint256[] memory lpIndices
    ) external nonReentrant returns (bool) {
        _isEligibleSender();
        _whenNotPaused();

        if (getOptionTokenInfo[strikeToken].ssov == address(0)) {
            revert SsovDoesNotExist();
        }
        if (lpIndices.length == 0) {
            revert InvalidParams();
        }
        for (uint256 i; i < lpIndices.length; ++i) {
            _killLpPosition(strikeToken, lpIndices[i]);
        }
        return true;
    }

    /// @dev helper function to kill an Lp position at index
    function _killLpPosition(address strikeToken, uint256 lpIndex)
        internal
        returns (bool)
    {
        if (lpIndex >= allLpPositions[strikeToken].length) {
            revert InvalidLpIndex();
        }

        LpPosition memory lpPosition = allLpPositions[strikeToken][lpIndex];
        if (lpPosition.buyer != msg.sender) {
            revert OnlyBuyerCanKill();
        }
        if (lpPosition.killed) {
            revert LpPositionDead();
        }
        _killAndTransfer(
            strikeToken,
            lpIndex,
            lpPosition.buyer,
            lpPosition.usdLiquidity,
            lpPosition.underlyingLiquidity
        );
        emit LpPositionKilled(strikeToken, lpIndex);
        return true;
    }

    /// @dev helper function to kill position and transfer liquidity left in position back to Lp. This does not update liquidity in Lp position.
    function _killAndTransfer(
        address strikeToken,
        uint256 lpIndex,
        address buyer,
        uint256 usdLiquidity,
        uint256 underlyingLiquidity
    ) internal returns (bool) {
        allLpPositions[strikeToken][lpIndex].killed = true;

        if (usdLiquidity != 0) {
            getOptionTokenInfo[strikeToken].usdLiquidity -= usdLiquidity;
            IERC20(addresses.usd).safeTransfer(buyer, usdLiquidity);
        } else if (underlyingLiquidity != 0) {
            getOptionTokenInfo[strikeToken]
                .underlyingLiquidity -= underlyingLiquidity;
            IERC20(addresses.underlying).safeTransfer(
                buyer,
                underlyingLiquidity
            );
        }
        return true;
    }

    /*==== VIEW METHODS ====*/

    /**
     * @notice Returns all Lp positions for a given user
     * @param user address of user
     * @param strikeToken epoch strike token address
     * @return positions the user's Lp positions
     */
    function getUserLpPositions(address user, address strikeToken)
        external
        view
        returns (LpPosition[] memory positions)
    {
        uint256[] memory userPositionsId = userLpPositions[user][strikeToken];
        uint256 numPositions = userPositionsId.length;
        positions = new LpPosition[](numPositions);
        for (uint256 i; i < numPositions; ) {
            positions[i] = allLpPositions[strikeToken][userPositionsId[i]];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns all Lp positions for a given strikeToken
     * @param strikeToken epoch strike token address
     * @return all Lp positions
     */
    function getAllLpPositions(address strikeToken)
        external
        view
        returns (LpPosition[] memory)
    {
        return allLpPositions[strikeToken];
    }
}

contract SsovLpFactory is Ownable {
    mapping(address => bool) ssovLpContracts;

    address public immutable ssovLpImplementation;

    event Deploy(address ssovLp);

    constructor() {
        ssovLpImplementation = address(new SsovLp());
    }

    function deploy(
        string memory _name,
        string memory _underlyingSymbol,
        SsovLp.Addresses memory _addresses
    ) external onlyOwner returns (address ssovLp) {
        ssovLp = Clones.clone(ssovLpImplementation);

        SsovLp(ssovLp).initialize(
            _name,
            _underlyingSymbol,
            _addresses,
            msg.sender
        );

        ssovLpContracts[ssovLp] = true;

        emit Deploy(ssovLp);
    }
}