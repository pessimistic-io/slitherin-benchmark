// File: @chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol


pragma solidity ^0.8.0;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

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

// File: contracts/common/uniswap/IWETH.sol


pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function approve(address guy, uint wad) external returns (bool);

}
// File: contracts/common/uniswap/IUniswapV2Router01.sol


pragma solidity ^0.8.0;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}
// {"mode":"full","isActive":false}
// File: contracts/common/uniswap/IUniswapV2Router02.sol


pragma solidity ^0.8.0;


interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}
// {"mode":"full","isActive":false}
// File: contracts/taxing/IGeneralTaxDistributor.sol


pragma solidity ^0.8.0;

interface IGeneralTaxDistributor {
    function distributeTax(address token) external returns (uint256);
    function distributeTaxAvoidOrigin(address token, address origin) external returns (uint256);
}
// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

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

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;


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

// File: contracts/common/WithAdmin.sol


pragma solidity 0.8.2;


contract WithAdmin is Ownable {
	address public admin;
	event AdminSet(address admin);

	function setAdmin(address _admin) external onlyOwner {
		admin = _admin;
		emit AdminSet(_admin);
	}

	modifier onlyAdmin() {
		require(msg.sender == admin || msg.sender == owner(), "WA: not admin");
		_;
	}
}
// File: @openzeppelin/contracts/utils/math/Math.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

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

// File: @openzeppelin/contracts/utils/Strings.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/Strings.sol)

pragma solidity ^0.8.0;


/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/ECDSA.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/cryptography/ECDSA.sol)

pragma solidity ^0.8.0;


/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV // Deprecated in v4.8
    }

    function _throwError(RecoverError error) private pure {
        if (error == RecoverError.NoError) {
            return; // no error: do nothing
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature` or error string. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     *
     * _Available since v4.3._
     */
    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            /// @solidity memory-safe-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength);
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, signature);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[EIP-2098 short signatures]
     *
     * _Available since v4.3._
     */
    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     *
     * _Available since v4.2._
     */
    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
     * `r` and `s` signature fields separately.
     *
     * _Available since v4.3._
     */
    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }

        return (signer, RecoverError.NoError);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from `s`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    /**
     * @dev Returns an Ethereum Signed Typed Data, created from a
     * `domainSeparator` and a `structHash`. This produces hash corresponding
     * to the one signed with the
     * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`]
     * JSON-RPC method as part of EIP-712.
     *
     * See {recover}.
     */
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

// File: @openzeppelin/contracts/utils/cryptography/EIP712.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/cryptography/EIP712.sol)

pragma solidity ^0.8.0;


/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP 712] is a standard for hashing and signing of typed structured data.
 *
 * The encoding specified in the EIP is very generic, and such a generic implementation in Solidity is not feasible,
 * thus this contract does not implement the encoding itself. Protocols need to implement the type-specific encoding
 * they need in their contracts using a combination of `abi.encode` and `keccak256`.
 *
 * This contract implements the EIP 712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest that is then signed via ECDSA
 * ({_hashTypedDataV4}).
 *
 * The implementation of the domain separator was designed to be as efficient as possible while still properly updating
 * the chain id to protect against replay attacks on an eventual fork of the chain.
 *
 * NOTE: This contract implements the version of the encoding known as "v4", as implemented by the JSON RPC method
 * https://docs.metamask.io/guide/signing-data.html[`eth_signTypedDataV4` in MetaMask].
 *
 * _Available since v3.4._
 */
abstract contract EIP712 {
    /* solhint-disable var-name-mixedcase */
    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    /* solhint-enable var-name-mixedcase */

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP 712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _CACHED_THIS = address(this);
        _TYPE_HASH = typeHash;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _CACHED_THIS && block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/draft-EIP712.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/cryptography/draft-EIP712.sol)

pragma solidity ^0.8.0;

// EIP-712 is Final as of 2022-08-11. This file is deprecated.


// File: contracts/common/signature/SigCheckable.sol


pragma solidity ^0.8.0;



/**
 @dev Make sure to define method signatures
 */
abstract contract SigCheckable is EIP712 {
    mapping(bytes32=>bool) public usedHashes;

    function signerUnique(
        bytes32 message,
        bytes memory signature) internal returns (address _signer) {
        bytes32 digest;
        (digest, _signer) = signer(message, signature);
        // require(!usedHashes[digest], "Message already used");
        usedHashes[digest] = true;
    }

    /*
        @dev example message;

        bytes32 constant METHOD_SIG =
            keccak256("WithdrawSigned(address token,address payee,uint256 amount,bytes32 salt)");
        bytes32 message = keccak256(abi.encode(
          METHOD_SIG,
          token,
          payee,
          amount,
          salt
    */
    function signer(
        bytes32 message,
        bytes memory signature) internal view returns (bytes32 digest, address _signer) {
        digest = _hashTypedDataV4(message);
        _signer = ECDSA.recover(digest, signature);
    }
}
// File: @openzeppelin/contracts/utils/Address.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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

// File: @openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol


// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

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

// File: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol


// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;




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

    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: contracts/common/SafeAmount.sol


pragma solidity 0.8.2;

// import "@openzeppelin//contracts/token/ERC20/IERC20.sol";

library SafeAmount {
    using SafeERC20 for IERC20;

    /**
     @notice transfer tokens from. Incorporate fee on transfer tokens
     @param token The token
     @param from From address
     @param to To address
     @param amount The amount
     @return result The actual amount transferred
     */
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount) internal returns (uint256 result) {
        uint256 preBalance = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 postBalance = IERC20(token).balanceOf(to);
        result = postBalance - preBalance;
        require(result <= amount, "SA: actual amount larger than transfer amount");
    }

    /**
     @notice Sends ETH
     @param to The to address
     @param value The amount
     */
	function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
}
// File: contracts/upgradeable-Bridge/FundManager.sol


pragma solidity 0.8.2;






contract FundManager is SigCheckable, WithAdmin{
    using SafeERC20 for IERC20;

    address public router;
    uint256 constant MAX_FEE = 0.1 * 10000; // 10% max fee
    string constant NAME = "FERRUM_TOKEN_BRIDGE_POOL";
    string constant VERSION = "000.004";
    bytes32 constant WITHDRAW_SIGNED_METHOD =
        keccak256(
            "WithdrawSigned(address token,address payee,uint256 amount,bytes32 salt)"
        );

    event TransferBySignature(
        address signer,
        address receiver,
        address token,
        uint256 amount,
        uint256 fee
    );
    event BridgeLiquidityAdded(address actor, address token, uint256 amount);
    event BridgeLiquidityRemoved(address actor, address token, uint256 amount);
    event BridgeSwap(
        address from,
        address indexed token,
        uint256 targetNetwork,
        address targetToken,
        address targetAddrdess,
        uint256 amount
    );
    event nonEvmBridgeSwap(
        address from,
        address indexed token,
        string targetNetwork,
        string targetToken,
        string targetAddrdess,
        uint256 amount
    );

    mapping(address => bool) public signers;
    mapping(address => mapping(address => uint256)) private liquidities;
    mapping(address => uint256) public fees;
    mapping(address => mapping(uint256 => address)) public allowedTargets;
    mapping(address => mapping(string => string)) public nonEvmAllowedTargets;
    address public feeDistributor;
    mapping(address => bool) public isFoundryAsset;

    modifier onlyRouter() {
        require(msg.sender == router, "BP: Only router method");
        _;
    }

    //initialize function is constructor for upgradeable smart contract
    constructor () EIP712(NAME, VERSION) { }

    /**
     *************** Owner only operations ***************
     */

    /*
     @notice sets the router
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "BP: router requried");
        router = _router;
    }

    function addSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Bad signer");
        signers[_signer] = true;
    }

    function removeSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Bad signer");
        delete signers[_signer];
    }

    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        feeDistributor = _feeDistributor;
    }

    /**
     *************** Admin operations ***************
     */

    function setFee(address token, uint256 fee10000) external onlyAdmin {
        require(token != address(0), "Bad token");
        require(fee10000 <= MAX_FEE, "Fee too large");
        fees[token] = fee10000;
    }

    function allowTarget(
        address token,
        uint256 chainId,
        address targetToken
    ) external onlyAdmin {
        require(token != address(0), "Bad token");
        require(targetToken != address(0), "Bad targetToken");
        require(chainId != 0, "Bad chainId");
        allowedTargets[token][chainId] = targetToken;
    }

    function nonEvmAllowTarget(
        address token,
        string memory chainId,
        string memory targetToken
    ) external onlyAdmin {
        require(token != address(0), "Bad token");
        nonEvmAllowedTargets[token][chainId] = targetToken;
    }

    function disallowTarget(address token, uint256 chainId) external onlyAdmin {
        require(token != address(0), "Bad token");
        require(chainId != 0, "Bad chainId");
        delete allowedTargets[token][chainId];
    }
    
    function nonEvmDisallowTarget(address token, string memory chainId) external onlyAdmin {
        require(token != address(0), "Bad token");
        delete nonEvmAllowedTargets[token][chainId];
    }

    function addFoundryAsset(address token) external onlyAdmin {
        require(token != address(0), "Bad token");
        isFoundryAsset[token] = true;
    }

    function removeFoundryAsset(address token) external onlyAdmin {
        require(token != address(0), "Bad token");
        isFoundryAsset[token] = false;
    }

    /**
     *************** Public operations ***************
     */

    function swap(
        address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken
    ) external onlyRouter returns (uint256) {
        return
            _swap(
                msg.sender,
                token,
                amount,
                targetNetwork,
                targetToken,
                msg.sender
            );
    }

    function swapToAddress(
        address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken,
        address targetAddress
    ) external onlyRouter returns (uint256) {
        require(
            targetAddress != address(0),
            "BridgePool: targetAddress is required"
        );
        return
            _swap(
                msg.sender,
                token,
                amount,
                targetNetwork,
                targetToken,
                targetAddress
            );
    }

    function nonEvmSwapToAddress(
        address token,
        uint256 amount,
        string memory targetNetwork,
        string memory targetToken,
        string memory targetAddress
    ) external onlyRouter returns (uint256) {
        return
            _nonEvmSwap(
                msg.sender,
                token,
                amount,
                targetNetwork,
                targetToken,
                targetAddress
            );
    }

    function _swap(
        address from,
        address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken,
        address targetAddress
    ) internal returns (uint256) {
        require(from != address(0), "BP: bad from");
        require(token != address(0), "BP: bad token");
        require(targetNetwork != 0, "BP: targetNetwork is requried");
        require(targetToken != address(0), "BP: bad target token");
        require(amount != 0, "BP: bad amount");
        require(
            allowedTargets[token][targetNetwork] == targetToken,
            "BP: target not allowed"
        );
        amount = SafeAmount.safeTransferFrom(
            token,
            from,
            address(this),
            amount
        );
        emit BridgeSwap(
            from,
            token,
            targetNetwork,
            targetToken,
            targetAddress,
            amount
        );
        return amount;
    }

    function _nonEvmSwap(
        address from,
        address token,
        uint256 amount,
        string memory targetNetwork,
        string memory targetToken,
        string memory targetAddress
    ) internal returns (uint256) {
        require(from != address(0), "BP: bad from");
        require(token != address(0), "BP: bad token");
        require(amount != 0, "BP: bad amount");
        require(
            
            keccak256(abi.encodePacked(nonEvmAllowedTargets[token][targetNetwork])) == keccak256(abi.encodePacked(targetToken)),
            "BP: target not allowed"
        );
        amount = SafeAmount.safeTransferFrom(
            token,
            from,
            address(this),
            amount
        );
        emit nonEvmBridgeSwap(
            from,
            token,
            targetNetwork,
            targetToken,
            targetAddress,
            amount
        );
        return amount;
    }

    function withdrawSigned(
        address token,
        address payee,
        uint256 amount,
        bytes32 salt,
        bytes memory signature
    ) external onlyRouter returns (uint256) {
        require(token != address(0), "BP: bad token");
        require(payee != address(0), "BP: bad payee");
        require(salt != 0, "BP: bad salt");
        require(amount != 0, "BP: bad amount");
        bytes32 message = withdrawSignedMessage(token, payee, amount, salt);
        address _signer = signerUnique(message, signature);
        require(signers[_signer], "BridgePool: Invalid signer");

        uint256 fee = 0;
        address _feeDistributor = feeDistributor;
        if (_feeDistributor != address(0)) {
            fee = (amount * fees[token]) / 10000;
            amount = amount - fee;
            if (fee != 0) {
                IERC20(token).safeTransfer(_feeDistributor, fee);
                IGeneralTaxDistributor(_feeDistributor).distributeTax(token);
            }
        }
        IERC20(token).safeTransfer(payee, amount);
        emit TransferBySignature(_signer, payee, token, amount, fee);
        return amount;
    }

    function withdraw(
        address token,
        address payee,
        uint256 amount
    ) external onlyRouter returns (uint256) {
        require(token != address(0), "BP: bad token");
        require(payee != address(0), "BP: bad payee");
        require(amount != 0, "BP: bad amount");
        require(isFoundryAsset[token] == true, "token is not foundry asset");
        uint256 contractBalance = IERC20(token).balanceOf(
            address(this)
        );
        require(
            contractBalance >= amount,
            "insufficient foundry asset liquidity amount"
        );
        IERC20(token).safeTransfer(payee, amount);
        return amount;
    }

    function withdrawSignedVerify(
        address token,
        address payee,
        uint256 amount,
        bytes32 salt,
        bytes calldata signature
    ) external view returns (bytes32, address) {
        bytes32 message = withdrawSignedMessage(token, payee, amount, salt);
        (bytes32 digest, address _signer) = signer(message, signature);
        return (digest, _signer);
    }

    function withdrawSignedMessage(
        address token,
        address payee,
        uint256 amount,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(WITHDRAW_SIGNED_METHOD, token, payee, amount, salt)
            );
    }

    function addLiquidity(address token, uint256 amount) external {
        require(amount != 0, "Amount must be positive");
        require(token != address(0), "Bad token");
        require(
            isFoundryAsset[token] == true,
            "Only foundry assets can be added"
        );
        amount = SafeAmount.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );
        liquidities[token][msg.sender] =
            liquidities[token][msg.sender] +
            amount;
        emit BridgeLiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidityIfPossible(address token, uint256 amount)
        external
        returns (uint256)
    {
        require(amount != 0, "Amount must be positive");
        require(token != address(0), "Bad token");
        require(
            isFoundryAsset[token] == true,
            "Only foundry assets can be removed"
        );
        uint256 liq = liquidities[token][msg.sender];
        require(liq >= amount, "Not enough liquidity");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 actualLiq = balance > amount ? amount : balance;
        liquidities[token][msg.sender] =
            liquidities[token][msg.sender] -
            actualLiq;
        if (actualLiq != 0) {
            IERC20(token).safeTransfer(msg.sender, actualLiq);
            emit BridgeLiquidityRemoved(msg.sender, token, amount);
        }
        return actualLiq;
    }

    function liquidity(address token, address liquidityAdder)
        public
        view
        returns (uint256)
    {
        return liquidities[token][liquidityAdder];
    }
}
// File: contracts/upgradeable-Bridge/FiberRouter.sol


pragma solidity 0.8.2;







/**
 @author The ferrum network.
 @title This is a vesting contract named as FiberRouter.
*/
contract FiberRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    address public pool;
    mapping(address => AggregatorV3Interface) public priceFeed;

    event Swap(
        address sourceToken,
        address targetToken,
        uint256 sourceChainId,
        uint256 targetChainId,
        uint256 sourceAmount,
        address sourceAddress,
        address targetAddress,
        uint256 swapBridgeAmount
    );

    event Withdraw(
        address token,
        address receiver,
        uint256 amount,
        bytes32 salt,
        bytes signature
    );

    event NonEvmSwap(
        address sourceToken,
        string targetToken,
        uint256 sourceChainId,
        string targetChainId,
        uint256 sourceAmount,
        address sourceAddress,
        string targetAddress
    );

    /**
     @notice The payable receive method
     */
    receive() external payable {}

    // /**
    //  @notice Initialization of contract
    // */
    // function initialize() external initializer {
    //     // __Ownable_init();
    //     // __ReentrancyGuard_init();
    // }

    /**
     @notice Sets the fund manager contract.
     @param _pool The fund manager
     */
    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }

    /**
     @notice Sets the oracle for foundry tokens.
     @param _token The foundry token address
     @param _oracleAddress The oracle address for price feed
     */
    function setOracle(address _token, AggregatorV3Interface _oracleAddress)
        external
        onlyOwner
    {
        priceFeed[_token] = _oracleAddress;
    }

    function getFoundryTokenPrice(address _token)
        public
        view
        returns (uint256)
    {
        (
            ,
            /*uint80 roundID*/
            int256 price,
            ,
            ,

        ) = /*uint startedAt*/
            /*uint timeStamp*/
            /*uint80 answeredInRound*/
            priceFeed[_token].latestRoundData();
        uint8 baseDecimals = priceFeed[_token].decimals();
        return uint256(price) * 10**(18 - baseDecimals);
        // return uint(price);
    }

    /*
     @notice Initiate an x-chain swap.
     @param token The source token to be swaped
     @param amount The source amount
     @param targetNetwork The chain ID for the target network
     @param targetToken The target token address
     @param swapTargetTokenTo Swap the target token to a new token
     @param targetAddress Final destination on target
     */
    function swap(
        address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken,
        address targetAddress,
        uint256 swapBridgeAmount
    ) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(pool, amount);
        FundManager(pool).swapToAddress(
            token,
            amount,
            targetNetwork,
            targetToken,
            targetAddress
        );
        emit Swap(
            token,
            targetToken,
            block.chainid,
            targetNetwork,
            amount,
            _msgSender(),
            targetAddress,
            swapBridgeAmount
        );
    }

    /*
     @notice Initiate an x-chain swap.
     @param token The source token to be swaped
     @param amount The source amount
     @param targetNetwork The chain ID for the target network
     @param targetToken The target token address
     @param swapTargetTokenTo Swap the target token to a new token
     @param targetAddress Final destination on target
     */
    function nonEvmSwap(
        address token,
        uint256 amount,
        string memory targetNetwork,
        string memory targetToken,
        string memory targetAddress
    ) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(pool, amount);
        FundManager(pool).nonEvmSwapToAddress(
            token,
            amount,
            targetNetwork,
            targetToken,
            targetAddress
        );
        NonEvmSwap(
            token,
            targetToken,
            block.chainid,
            targetNetwork,
            amount,
            _msgSender(),
            targetAddress
        );
    }

    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountIn The amount in
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function swapAndCrossOneInch(
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, // amountOutMin on uniswap
        uint256 crossTargetNetwork,
        address crossTargetToken,
        address crossTargetAddress,
        uint256 swapBridgeAmount,
        bytes memory _calldata,
        address fromToken,
        address foundryToken
    ) external nonReentrant {
        amountIn = SafeAmount.safeTransferFrom(
            fromToken,
            msg.sender,
            address(this),
            amountIn
        );
        IERC20(fromToken).approve(swapRouter, amountIn);
        IERC20(foundryToken).approve(pool, amountCrossMin);
        _swapAndCrossOneInch(
            crossTargetAddress,
            swapRouter,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            _calldata,
            foundryToken
        );
        emit Swap(
            fromToken,
            crossTargetToken,
            block.chainid,
            crossTargetNetwork,
            amountIn,
            _msgSender(),
            crossTargetAddress,
            swapBridgeAmount
        );
    }

    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountIn The amount in
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function swapAndCross(
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline,
        uint256 crossTargetNetwork,
        address crossTargetToken,
        address crossTargetAddress,
        uint256 swapBridgeAmount
    ) external nonReentrant {
        amountIn = SafeAmount.safeTransferFrom(
            path[0],
            msg.sender,
            address(this),
            amountIn
        );
        IERC20(path[0]).approve(swapRouter, amountIn);
        _swapAndCross(
            msg.sender,
            swapRouter,
            amountIn,
            amountCrossMin,
            path,
            deadline,
            crossTargetNetwork,
            crossTargetToken
        );
        emit Swap(
            path[0],
            crossTargetToken,
            block.chainid,
            crossTargetNetwork,
            amountIn,
            _msgSender(),
            crossTargetAddress,
            swapBridgeAmount
        );
    }

    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountIn The amount in
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function nonEvmSwapAndCrossOneInch(
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, // amountOutMin on uniswap
        string memory crossTargetNetwork,
        string memory crossTargetToken,
        string memory crossTargetAddress,
        uint256 swapBridgeAmount,
        bytes memory _calldata,
        address fromToken,
        address foundryToken
    ) external nonReentrant {
        amountIn = SafeAmount.safeTransferFrom(
            fromToken,
            msg.sender,
            address(this),
            amountIn
        );
        IERC20(fromToken).approve(swapRouter, amountIn);
        IERC20(foundryToken).approve(pool, amountIn);
        _nonEvmSwapAndCrossOneInch(
            crossTargetAddress,
            swapRouter,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            _calldata,
            foundryToken
        );
        NonEvmSwap(
            fromToken,
            crossTargetToken,
            block.chainid,
            crossTargetNetwork,
            amountIn,
            _msgSender(),
            crossTargetAddress
        );
    }

    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountIn The amount in
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function nonEvmSwapAndCross(
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline,
        string memory crossTargetNetwork,
        string memory crossTargetToken,
        string memory crossTargetAddress
    ) external nonReentrant {
        amountIn = SafeAmount.safeTransferFrom(
            path[0],
            msg.sender,
            address(this),
            amountIn
        );
        IERC20(path[0]).approve(swapRouter, amountIn);
        _nonEvmSwapAndCross(
            crossTargetAddress,
            swapRouter,
            amountIn,
            amountCrossMin,
            path,
            deadline,
            crossTargetNetwork,
            crossTargetToken
        );
        NonEvmSwap(
            path[0],
            crossTargetToken,
            block.chainid,
            crossTargetNetwork,
            amountIn,
            _msgSender(),
            crossTargetAddress
        );
    }

    /*
     @notice Withdraws funds based on a multisig
     @dev For signature swapToToken must be the same as token
     @param token The token to withdraw
     @param payee Address for where to send the tokens to
     @param amount The mount
     @param sourceChainId The source chain initiating the tx
     @param swapTxId The txId for the swap from the source chain
     @param multiSignature The multisig validator signature
     */
    function withdrawSigned(
        address token,
        address payee,
        uint256 amount,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        FundManager(pool).withdrawSigned(
            token,
            payee,
            amount,
            salt,
            multiSignature
        );

        emit Withdraw(token, payee, amount, salt, multiSignature);
    }

    /*
     @notice Withdraws funds and swaps to a new token
     @param to Address for where to send the tokens to
     @param swapRouter The swap router address
     @param amountIn The amount to swap
     @param sourceChainId The source chain Id. Used for signature
     @param swapTxId The source tx Id. Used for signature
     @param amountOutMin Same as amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap deadline
     @param multiSignature The multisig validator signature
     */
    function withdrawSignedAndSwap(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOutMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        require(path.length > 1, "BR: path too short");
        FundManager(pool).withdrawSigned(
            path[0],
            address(this),
            amountIn,
            salt,
            multiSignature
        );
        amountIn = IERC20(path[0]).balanceOf(address(this)); // Actual amount received
        IERC20(path[0]).approve(swapRouter, amountIn);
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
        emit Withdraw(
            path[path.length - 1],
            to,
            amountOutMin,
            salt,
            multiSignature
        );
    }

    /*
     @notice Withdraws funds and swaps to a new token
     @param to Address for where to send the tokens to
     @param swapRouter The swap router address
     @param amountIn The amount to swap
     @param sourceChainId The source chain Id. Used for signature
     @param swapTxId The source tx Id. Used for signature
     @param amountOutMin Same as amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap deadline
     @param multiSignature The multisig validator signature
     */
    function withdrawSignedAndSwapOneInch(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOutMin, // amountOutMin on uniswap
        address foundryToken,
        address targetToken,
        bytes memory _calldata,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        require(foundryToken != address(0), "Bad Token Address");

        FundManager(pool).withdrawSigned(
            foundryToken,
            address(this),
            amountIn,
            salt,
            multiSignature
        );
        amountIn = IERC20(foundryToken).balanceOf(address(this)); // Actual amount received
        IERC20(foundryToken).approve(swapRouter, amountIn);
        (bool success, ) = address(swapRouter).call(_calldata);

        if (!success) {
            revert("SWAP_FAILED");
        }
        uint256 amountOut = IERC20(targetToken).balanceOf(address(this)); // Actual amount received
        IERC20(targetToken).transfer(to, amountOut);
        emit Withdraw(foundryToken, to, amountOutMin, salt, multiSignature);
    }

    /*
    @notice Runs a local swap and then a cross chain swap
    @param to The receiver
    @param swapRouter the swap router
    @param amountIn The amount in
    @param amountCrossMin Equivalent to amountOutMin on uniswap 
    @param path The swap path
    @param deadline The swap deadline
    @param crossTargetNetwork The target chain ID
    @param crossTargetToken The target network token
    @param crossSwapTargetTokenTo The target network token after swap
    @param crossTargetAddress The receiver of tokens on the target network
    */
    function _swapAndCross(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin,
        address[] calldata path,
        uint256 deadline,
        uint256 crossTargetNetwork,
        address crossTargetToken // address crossSwapTargetTokenTo // address crossTargetAddress
    ) internal {
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountCrossMin,
                path,
                address(this),
                deadline
            );
        address crossToken = path[path.length - 1];
        IERC20(crossToken).approve(pool, amountCrossMin);
        FundManager(pool).swapToAddress(
            crossToken,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            to
        );
    }

    /*
    @notice Runs a local swap and then a cross chain swap
    @param to The receiver
    @param swapRouter the swap router
    @param amountIn The amount in
    @param amountCrossMin Equivalent to amountOutMin on uniswap 
    @param path The swap path
    @param deadline The swap deadline
    @param crossTargetNetwork The target chain ID
    @param crossTargetToken The target network token
    @param crossSwapTargetTokenTo The target network token after swap
    @param crossTargetAddress The receiver of tokens on the target network
    */
    function _swapAndCrossOneInch(
        address to,
        address swapRouter,
        uint256 amountCrossMin,
        uint256 crossTargetNetwork,
        address crossTargetToken, // address crossSwapTargetTokenTo // address crossTargetAddress
        bytes memory _calldata,
        address foundryToken
    ) internal {
        (bool success, ) = address(swapRouter).call(_calldata);

        if (!success) {
            revert("SWAP_FAILED");
        }

        FundManager(pool).swapToAddress(
            foundryToken,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            to
        );
    }

    /*
    @notice Runs a local swap and then a cross chain swap
    @param to The receiver
    @param swapRouter the swap router
    @param amountIn The amount in
    @param amountCrossMin Equivalent to amountOutMin on uniswap 
    @param path The swap path
    @param deadline The swap deadline
    @param crossTargetNetwork The target chain ID
    @param crossTargetToken The target network token
    @param crossSwapTargetTokenTo The target network token after swap
    @param crossTargetAddress The receiver of tokens on the target network
    */
    function _nonEvmSwapAndCross(
        string memory to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin,
        address[] calldata path,
        uint256 deadline,
        string memory crossTargetNetwork,
        string memory crossTargetToken // address crossSwapTargetTokenTo // address crossTargetAddress
    ) internal {
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountCrossMin,
                path,
                address(this),
                deadline
            );
        address crossToken = path[path.length - 1];
        IERC20(crossToken).approve(pool, amountCrossMin);
        FundManager(pool).nonEvmSwapToAddress(
            crossToken,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            to
        );
    }

    /*
    @notice Runs a local swap and then a cross chain swap
    @param to The receiver
    @param swapRouter the swap router
    @param amountIn The amount in
    @param amountCrossMin Equivalent to amountOutMin on uniswap 
    @param path The swap path
    @param deadline The swap deadline
    @param crossTargetNetwork The target chain ID
    @param crossTargetToken The target network token
    @param crossSwapTargetTokenTo The target network token after swap
    @param crossTargetAddress The receiver of tokens on the target network
    */
    function _nonEvmSwapAndCrossOneInch(
        string memory to,
        address swapRouter,
        uint256 amountCrossMin,
        string memory crossTargetNetwork,
        string memory crossTargetToken, // address crossSwapTargetTokenTo // address crossTargetAddress
        bytes memory _calldata,
        address foundryToken
    ) internal {
        (bool success, ) = address(swapRouter).call(_calldata);

        if (!success) {
            revert("SWAP_FAILED");
        }

        FundManager(pool).nonEvmSwapToAddress(
            foundryToken,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            to
        );
    }
}