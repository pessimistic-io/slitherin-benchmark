// Sources flattened with hardhat v2.12.6 https://hardhat.org

// File @openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol@v4.8.1

// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControlUpgradeable {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
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
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

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
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

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
    function renounceRole(bytes32 role, address account) external;
}

// File @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol@v4.8.1

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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
        return
            functionCallWithValue(target, data, value, "Address: low-level call with value failed");
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
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
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

// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v4.8.1

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
            (isTopLevelCall && _initialized < 1) ||
                (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
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
        require(
            !_initializing && _initialized < version,
            "Initializable: contract is already initialized"
        );
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

// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v4.8.1

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {}

    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// File @openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol@v4.8.1

// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
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

// File @openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol@v4.8.1

// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

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
abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    function __ERC165_init() internal onlyInitializing {}

    function __ERC165_init_unchained() internal onlyInitializing {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// File @openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library MathUpgradeable {
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
        // ΓåÆ `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // ΓåÆ `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
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
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
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
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
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

// File @openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.8.0) (utils/Strings.sol)

/**
 * @dev String operations.
 */
library StringsUpgradeable {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = MathUpgradeable.log10(value) + 1;
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
            return toHexString(value, MathUpgradeable.log256(value) + 1);
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

// File @openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.8.0) (access/AccessControl.sol)

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
abstract contract AccessControlUpgradeable is
    Initializable,
    ContextUpgradeable,
    IAccessControlUpgradeable,
    ERC165Upgradeable
{
    function __AccessControl_init() internal onlyInitializing {}

    function __AccessControl_init_unchained() internal onlyInitializing {}

    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IAccessControlUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `_msgSender()` is missing `role`.
     * Overriding this function changes the behavior of the {onlyRole} modifier.
     *
     * Format of the revert message is described in {_checkRole}.
     *
     * _Available since v4.6._
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        StringsUpgradeable.toHexString(account),
                        " is missing role ",
                        StringsUpgradeable.toHexString(uint256(role), 32)
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
    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
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
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
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
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     *
     * May emit a {RoleRevoked} event.
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
     * May emit a {RoleGranted} event.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     *
     * NOTE: This function is deprecated in favor of {_grantRole}.
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
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// File @openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
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
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// File @openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol@v4.8.1
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20PermitUpgradeable {
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

// File @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// File @openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol@v4.8.1
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20Upgradeable token,
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
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
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
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
        );
    }

    function safeDecreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(
                token,
                abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
            );
        }
    }

    function safePermit(
        IERC20PermitUpgradeable token,
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
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File contracts/interfaces/beefy/IStrategyV7.sol

interface IStrategyV7 {
    function vault() external view returns (address);

    function asset() external view returns (IERC20Upgradeable);

    function beforeDeposit() external;

    function deposit(address) external;

    function withdraw(uint256, address) external;

    function balanceOfAsset() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function harvest() external;

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;

    function pendingHarvestRewards()
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);
}

// File contracts/interfaces/arbidex/ArbidexMasterChef.sol

struct ArbidexUserInfo {
    uint256 amount;
    uint256 arxRewardDebt;
    uint256 WETHRewardDebt;
}

interface ArbidexMasterChef {
    function userInfo(uint256 _pid, address _user) external view returns (ArbidexUserInfo memory);

    function pendingArx(uint256 _pid, address _user) external view returns (uint256);

    function pendingWETH(uint256 _pid, address _user) external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function WETH() external view returns (address);
}

// File contracts/interfaces/common/tokens/IERC721.sol

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

// File contracts/interfaces/common/IUniswapRouterETH.sol

interface IUniswapRouterETH {
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

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

// File contracts/interfaces/common/IUniswapV2Pair.sol

interface IUniswapV2Pair {
    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(address to) external returns (uint amount0, uint amount1);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint256);

    function kLast() external view returns (uint256);
}

// File contracts/interfaces/beefy/IFees.sol

struct IFees {
    uint256 callFee;
    uint256 strategist;
    uint256 withdrawFee; // Fee that goes to remaining depositors
    uint256 protocolHarvestFee;
    uint256 protocolDepositFee;
    uint256 protocolWithdrawFee;
    uint256 totalFees;
}

// File contracts/strategies/common/StrategyFeesBase.sol

abstract contract StrategyFeesBase is AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant DIVISOR = 1 ether;
    uint256 public constant WITHDRAW_FEE_CAP = 100; // 10%
    uint256 public constant DEPOSIT_FEE_CAP = 100; // 10%
    // Sum of all fee types
    uint256 public constant MAX_TOTAL_FEE = 200; // 20%
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant WITHDRAW_MAX = 10000;

    uint256 internal _pendingDepositWithdrawFees;

    address internal _beefyFeeRecipient;
    IFees internal _feeConfig;

    mapping(address => bool) private _feeExemptions;

    event SetStratFeeId(uint256 feeId);
    event SetDepositFee(uint256 depositFee);
    event SetWithdrawalFee(uint256 withdrawalFee);
    event SetBeefyFeeRecipient(address beefyFeeRecipient);
    event SetFeeConfig(uint256 totalFees);
    event UpdateFeeExempt(address indexed who, bool exempt);
    event FeeWithdraw(uint256 amount);

    modifier onlyManager() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || hasRole(OPERATOR_ROLE, _msgSender()),
            "Not a manager"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __StrategyFeesBase_init(
        IFees calldata feeConfig,
        address beefyFeeRecipient
    ) internal initializer {
        require(beefyFeeRecipient != address(0), "beefyFeeRecipient not provided");
        _validatConfig(feeConfig);
        __AccessControl_init();
        __Pausable_init();

        _beefyFeeRecipient = beefyFeeRecipient;
        _feeConfig = feeConfig;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(OPERATOR_ROLE, _msgSender());
    }

    function _giveAllowances() internal virtual;

    function _removeAllowances() internal virtual;

    // ================================ VIEW ==================================== //

    /**
     * @dev Various checks for fee exemption cases.
     * Inheriting contracts can override and call up as needed.
     * Fees are disabled here also if contract is paused.
     */
    function isFeeExempt(address who) public virtual returns (bool) {
        return paused() || _feeExemptions[who];
    }

    function getBeefyFeeRecipient() public view returns (address) {
        return _beefyFeeRecipient;
    }

    function getFeeConfig() public view returns (IFees memory) {
        return _feeConfig;
    }

    function getProtocolDepositFee() public view returns (uint256) {
        return _feeConfig.protocolDepositFee;
    }

    function getProtocolDepositFeeForAmount(uint256 amount) public view returns (uint256) {
        return _getFeeAmount(amount, _feeConfig.protocolDepositFee);
    }

    function getProtocolWithdrawFeeForAmount(uint256 amount) public view returns (uint256) {
        return _getFeeAmount(amount, _feeConfig.protocolWithdrawFee);
    }

    function getProtocolHarvestFeeForAmount(uint256 amount) public view returns (uint256) {
        return _getFeeAmount(amount, _feeConfig.protocolHarvestFee);
    }

    function getTotalFeesForAmount() public view returns (uint256) {}

    /// @dev Amount deducted to increase base amount for the remaining depositors
    function getDepositorsWithdrawFeeBonus(uint256 amount) public view returns (uint256) {
        return _getFeeAmount(amount, _feeConfig.withdrawFee);
    }

    function getProtocolWithdrawFee() public view returns (uint256) {
        return paused() ? 0 : _feeConfig.protocolWithdrawFee;
    }

    function getPendingProtocolFees() public view returns (uint256) {
        return _pendingDepositWithdrawFees;
    }

    function _getFeeAmount(uint256 amount, uint256 fee) internal view virtual returns (uint256) {
        return paused() ? 0 : (amount * fee) / FEE_DENOMINATOR;
    }

    // ================================= ADMIN STATE TRANSITIONS ===================================== //

    function _updatePendingFees(uint256 amount) internal {
        // Pay for the check to save an SSTORE.
        // Not all strategies will have fees set but we want this to be freely callable
        // by inheriting contracts to simplify their needed logic.
        if (amount > 0) {
            _pendingDepositWithdrawFees += amount;
        }
    }

    // Fee contract has no concept of the deposit token.
    // So it is left to inheriting contracts to implement. Based here to keep fee logic grouped together.
    function withdrawPendingFees() external virtual;

    function updateFeeExemption(address who, bool exempt) external onlyManager {
        _updateFeeExempt(who, exempt);
    }

    function updateFeeExemptions(
        address[] calldata users,
        bool[] calldata exemptions
    ) external onlyManager {
        uint256 userCount = users.length;
        require(userCount == exemptions.length, "Mismatched lengths");

        // Shouldn't be an issue with stack too deep here
        for (uint256 i = 0; i < userCount; ) {
            _updateFeeExempt(users[i], exemptions[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _updateFeeExempt(address who, bool exempt) private {
        _feeExemptions[who] = exempt;
        emit UpdateFeeExempt(who, exempt);
    }

    // Adjust deposit fee
    function setDepositFee(uint256 fee) public onlyManager {
        require(fee <= DEPOSIT_FEE_CAP, "Deposit fee over max fee");

        _feeConfig.protocolDepositFee = fee;
        emit SetDepositFee(fee);
    }

    // Adjust withdrawal fee
    function setWithdrawFee(uint256 fee) public onlyManager {
        require(fee <= WITHDRAW_FEE_CAP, "Withdraw fee over max fee");

        _feeConfig.protocolWithdrawFee = fee;
        emit SetWithdrawalFee(fee);
    }

    // Set new beefy fee address to receive beefy fees
    function setBeefyFeeRecipient(address beefyFeeRecipient) external onlyManager {
        _beefyFeeRecipient = beefyFeeRecipient;
        emit SetBeefyFeeRecipient(beefyFeeRecipient);
    }

    function setFeeConfig(IFees calldata feeConfig) external onlyManager {
        uint256 totalFees = _validatConfig(feeConfig);
        _feeConfig = feeConfig;
        emit SetFeeConfig(totalFees);
    }

    function _validatConfig(IFees calldata feeConfig) private pure returns (uint256 totalFees) {
        totalFees =
            feeConfig.protocolDepositFee +
            feeConfig.protocolWithdrawFee +
            feeConfig.withdrawFee +
            feeConfig.callFee +
            feeConfig.strategist +
            feeConfig.protocolHarvestFee;

        require(feeConfig.totalFees == totalFees, "Total fees do not match");
        require(totalFees <= MAX_TOTAL_FEE, "Total fees over max");
    }
}

// File contracts/strategies/common/StrategyBase.sol

abstract contract StrategyBase is StrategyFeesBase {
    struct CommonAddresses {
        address vault;
        address keeper;
        address strategist;
        address beefyFeeRecipient;
    }

    // Common addresses for the strategy
    address internal _vault;
    address public keeper;
    address public strategist;

    event SetVault(address vault);
    event SetKeeper(address keeper);
    event SetStrategist(address strategist);
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    error ZeroAmount();

    modifier onlyVault() {
        require(_msgSender() == _vault, "Not the vault");
        _;
    }

    function __StrategyBase_init(
        CommonAddresses calldata _commonAddresses
    ) internal onlyInitializing {
        _vault = _commonAddresses.vault;
        keeper = _commonAddresses.keeper;
        strategist = _commonAddresses.strategist;
    }

    // =================================== VIEW ===================================== //

    function getContractTokenBalance(address token) public view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(address(this));
    }

    // =============================== ADMIN STATE TRANSISIONS =================================== //

    // Set new vault (only for strategy upgrades)
    function setVault(address vault) external onlyManager {
        _vault = vault;
        emit SetVault(vault);
    }

    // Set new keeper to manage strat
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    /**
     * Set new strategist address to receive strat fees.
     * Can only be updated by the current strategist.
     */
    function setStrategist(address _strategist) external {
        require(_msgSender() == strategist, "Not the strategist");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }
}

// File contracts/strategies/common/UniswapStrategyBase.sol

abstract contract UniswapStrategyBase is StrategyBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UniswapStrategyCommonFields {
        uint256 poolId;
        address depositToken;
        address router;
        address masterChef;
        address[] outputToNativeRoute;
        address[] outputToLp0Route;
        address[] outputToLp1Route;
    }

    uint256 public poolId;

    uint256 public lastHarvest;

    address public native;

    address public output;

    IERC20Upgradeable public depositToken;

    address public lpToken0;

    address public lpToken1;

    IUniswapRouterETH public router;

    address public chef;

    bool public harvestOnDeposit;

    // Routes
    address[] public outputToNativeRoute;

    address[] public outputToLp0Route;

    address[] public outputToLp1Route;

    event SetRouter(address routerAddress);

    function __UniswapStrategyBase_init(
        CommonAddresses calldata _commonAddresses,
        UniswapStrategyCommonFields memory stratFields
    ) public initializer {
        __StrategyBase_init(_commonAddresses);

        // Token info
        output = stratFields.outputToNativeRoute[0];
        native = stratFields.outputToNativeRoute[stratFields.outputToNativeRoute.length - 1];
        outputToNativeRoute = stratFields.outputToNativeRoute;

        // Setup lp routing
        lpToken0 = IUniswapV2Pair(stratFields.depositToken).token0();
        address[] memory _outputToLp0Route = stratFields.outputToLp0Route;

        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(
            _outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0,
            "outputToLp0Route[last] != lpToken0"
        );

        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IUniswapV2Pair(stratFields.depositToken).token1();
        address[] memory _outputToLp1Route = stratFields.outputToLp1Route;

        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(
            _outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1,
            "outputToLp1Route[last] != lpToken1"
        );

        outputToLp1Route = _outputToLp1Route;

        // Pool info
        depositToken = IERC20Upgradeable(stratFields.depositToken);
        poolId = stratFields.poolId;
        router = IUniswapRouterETH(stratFields.router);
        chef = stratFields.masterChef;

        _giveAllowances();
    }

    // ======================================= VIEW ========================================= //

    /// @dev Get the contracts balance for token
    /// The balance needs to account for any deposit/withdraw fees not withdrawn yet
    /// Otherwise calculations will be off (and continue to diverge)
    function balanceOfDepositToken() public view returns (uint256) {
        return depositToken.balanceOf(address(this)) - getPendingProtocolFees();
    }

    // ================================= ADMIN STATE TRANSITIONS =================================== //

    // @note Not access controlled
    function withdrawPendingFees() external override {
        uint256 pending = _pendingDepositWithdrawFees;
        _pendingDepositWithdrawFees = 0;

        emit FeeWithdraw(pending);

        // There is a zero address check for fee recipient during intialization
        depositToken.safeTransfer(_beefyFeeRecipient, pending);
    }

    // Set new router
    function setRouter(address _router) external onlyManager {
        router = IUniswapRouterETH(_router);
        emit SetRouter(address(_router));
    }

    /// @dev Allow updating to a more optimal routing path if needed
    function setOutputToLp0(address[] memory path) external onlyManager {
        require(path.length >= 2, "!path");

        outputToLp0Route = path;
    }

    /// @dev Allow updating to a more optimal routing path if needed
    function setOutputToLp1(address[] memory path) external onlyManager {
        require(path.length >= 2, "!path");

        outputToLp1Route = path;
    }

    /// @dev Allow updating to a more optimal routing path if needed
    function setOutputToNative(address[] memory path) external onlyManager {
        require(path.length >= 2, "!path");

        outputToNativeRoute = path;
    }

    // ================================= INTERNAL FUNCTIONS ===================================== //

    function _giveAllowances() internal override {
        uint256 maxInt = type(uint256).max;
        address routerAddress = address(router);

        _removeAllowances();

        IERC20Upgradeable(depositToken).safeApprove(chef, maxInt);
        IERC20Upgradeable(output).safeApprove(routerAddress, maxInt);
        IERC20Upgradeable(lpToken0).safeApprove(routerAddress, maxInt);
        IERC20Upgradeable(lpToken1).safeApprove(routerAddress, maxInt);
    }

    function _removeAllowances() internal override {
        address routerAddress = address(router);

        IERC20Upgradeable(depositToken).safeApprove(chef, 0);
        IERC20Upgradeable(output).safeApprove(routerAddress, 0);
        IERC20Upgradeable(lpToken0).safeApprove(routerAddress, 0);
        IERC20Upgradeable(lpToken1).safeApprove(routerAddress, 0);
    }
}

// File contracts/strategies/Arbidex/ArbidexStrategyBase.sol

contract ArbidexStrategyBase is UniswapStrategyBase, IStrategyV7 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    ArbidexMasterChef public masterChef;

    // Harvesting for this strat includes ARX rewards as well as WETH
    address[] private _wethToLp0Route;
    address[] private _wethToLp1Route;

    function __ArbidexStrategyBase_init(
        CommonAddresses calldata commonAddresses,
        UniswapStrategyCommonFields calldata stratFields,
        address[] calldata wethToLp0Route,
        address[] calldata wethToLp1Route
    ) public initializer {
        __UniswapStrategyBase_init(commonAddresses, stratFields);

        masterChef = ArbidexMasterChef(stratFields.masterChef);
        _wethToLp0Route = wethToLp0Route;
        _wethToLp1Route = wethToLp1Route;

        // For compounding WETH rewards also
        _doApprovals();
    }

    // ================================= COMPOUNDING ===================================== //

    function beforeDeposit() external virtual {}

    function deposit(address) external virtual {}

    function withdraw(uint256, address) external virtual {}

    function harvest() public override {
        _harvest(tx.origin);
    }

    function _harvest(address callFeeRecipient) internal whenNotPaused {
        require(callFeeRecipient != address(0), "callFeeRecipient not provided");

        // Harvest
        // Results in ARX and WETH rewards for this strategy
        masterChef.deposit(poolId, 0);

        uint256 rewardTokenBalance = getContractTokenBalance(output);

        if (rewardTokenBalance > 0) {
            _chargeFees(callFeeRecipient);
            _swapArxRewards();
            _swapWethRewards();
            _addLiquidity();

            // Get final LP amount received after swaps
            uint256 lpTokenAmount = balanceOfDepositToken();
            masterChef.deposit(poolId, lpTokenAmount);

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, lpTokenAmount, balanceOfAsset());
        }
    }

    function _chargeFees(address callFeeRecipient) private {
        // At this point we know we have some workable amount for fees
        // uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        uint256 nativeAmount = getProtocolHarvestFeeForAmount(getContractTokenBalance(output));
        // IUniswapRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(toNative, 0, outputToNativeRoute, address(this), now);
        // uint256 nativeBal = IERC20(native).balanceOf(address(this));
        // uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        // IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);
        // uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        // IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);
        // uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        // IERC20(native).safeTransfer(strategist, strategistFee);
    }

    function _addLiquidity() internal {
        // Both ARX and WETH are swapped into CGLD and USDT now as needed
        uint256 lpToken0Balance = getContractTokenBalance(lpToken0);
        uint256 lpToken1Balance = getContractTokenBalance(lpToken1);

        // This might not work for all cases here and need to go with zero
        router.addLiquidity(
            lpToken0,
            lpToken1,
            lpToken0Balance,
            lpToken1Balance,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _swapArxRewards() internal {
        uint256 arxHalf = getContractTokenBalance(output) / 2;

        if (lpToken0 != output) {
            router.swapExactTokensForTokens(
                arxHalf,
                0,
                outputToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != output) {
            router.swapExactTokensForTokens(
                arxHalf,
                0,
                outputToLp1Route,
                address(this),
                block.timestamp
            );
        }
    }

    function _swapWethRewards() internal {
        address weth = masterChef.WETH();
        uint256 wethHalf = getContractTokenBalance(weth) / 2;

        // TODO: Find out how the WETH rewards are distributed (timing/frequenct, etc.)
        if (wethHalf == 0) {
            return;
        }

        if (lpToken0 != weth) {
            router.swapExactTokensForTokens(
                wethHalf,
                0,
                _wethToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != weth) {
            router.swapExactTokensForTokens(
                wethHalf,
                0,
                _wethToLp1Route,
                address(this),
                block.timestamp
            );
        }
    }

    // =================================== VIEW ====================================== //

    function vault() public view returns (address) {
        return _vault;
    }

    function asset() public view override returns (IERC20Upgradeable) {
        return depositToken;
    }

    // Calculate the total underlaying deposit token held by the strat.
    // Could be a scenario where contract does not have all tokens deposited in pool.
    // So calculation is combination of contract balance and amount deposited in chef.
    function balanceOfAsset() public view override returns (uint256) {
        return balanceOfDepositToken() + balanceOfPool();
    }

    function balanceOfPool() public view override returns (uint256) {
        ArbidexUserInfo memory info = getPoolDepositInfo();
        return info.amount;
    }

    /// @dev Helper to pull amount and pending rewards
    function getPoolDepositInfo() public view returns (ArbidexUserInfo memory) {
        return masterChef.userInfo(poolId, address(this));
    }

    function pendingHarvestRewards()
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](2);
        amounts = new uint256[](2);

        tokens[0] = address(depositToken);
        tokens[1] = masterChef.WETH();

        amounts[0] = masterChef.pendingArx(poolId, address(this));
        amounts[1] = masterChef.pendingWETH(poolId, address(this));
    }

    function getWethOutputLp0Route() public view returns (address[] memory) {
        return _wethToLp0Route;
    }

    function getWethOutputLp1Route() public view returns (address[] memory) {
        return _wethToLp1Route;
    }

    // ================================= ADMIN STATE TRANSITIONS ===================================== //

    function retireStrat() external override onlyManager {}

    /**
     * @dev Pauses deposits and withdraws all funds from third party systems.
     * Will also remove current deposits from the farm due the "panic" situation.
     */
    function panic() external override onlyManager {
        _pause();
        masterChef.emergencyWithdraw(poolId);
    }

    function pause() external override onlyManager {
        _pause();
        _removeApprovals();
    }

    function unpause() external override onlyManager {
        _unpause();
        _doApprovals();
    }

    function setWethLp0Route(address[] calldata route) external onlyManager {
        _wethToLp0Route = route;
    }

    function setWethLp1Route(address[] calldata route) external onlyManager {
        _wethToLp0Route = route;
    }

    function _doApprovals() private {
        super._giveAllowances();
        address wethAddress = masterChef.WETH();
        IERC20Upgradeable weth = IERC20Upgradeable(wethAddress);
        weth.safeApprove(address(router), 0);
        weth.safeApprove(address(router), type(uint256).max);
    }

    function _removeApprovals() private {
        super._removeAllowances();
        IERC20Upgradeable(masterChef.WETH()).safeApprove(address(router), 0);
    }
}

// File contracts/strategies/CollectiveFi/CollectiveFiStrategy.sol

contract CollectiveFiStrategy is ArbidexStrategyBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private _nftAddress;

    function initialize(
        CommonAddresses calldata commonAddresses,
        UniswapStrategyCommonFields calldata stratFields,
        IFees calldata feeData,
        address[] calldata wethToLp0Path,
        address[] calldata wethToLp1Path,
        address nftContract
    ) public initializer {
        __StrategyFeesBase_init(feeData, commonAddresses.beefyFeeRecipient);
        __ArbidexStrategyBase_init(commonAddresses, stratFields, wethToLp0Path, wethToLp1Path);

        _nftAddress = nftContract;
    }

    // ================================= STATE TRANSITIONS ===================================== //

    /**
     * @dev Deposits into farm to put funds to work.
     * Users do not interact with strategies directly.
     * The vault acts as an intermediary and transfers user funds to this strategy
     * before calling the deposit function.
     */
    function deposit(address user) external override whenNotPaused onlyVault {
        // Use this function to account for fees
        uint256 tokenBalance = balanceOfDepositToken();

        if (tokenBalance > 0) {
            // The count of vaults with a deposit fee makes the read here worth the check
            // for overall gas saving purposes.
            uint256 depositFee = getProtocolDepositFee();
            if (!isFeeExempt(user) && depositFee > 0) {
                uint256 feeAmount = _getFeeAmount(tokenBalance, depositFee);
                _updatePendingFees(feeAmount);
                tokenBalance -= feeAmount;
            }

            masterChef.deposit(poolId, tokenBalance);

            // Emits for new Total Value Locked of the strategy
            emit Deposit(balanceOfAsset());
        }
    }

    /**
     * @dev Runs withdraw process for a user.
     * Only callable by the vault and vault provides the account address.
     * Withdraw fees are subtracted from withdraw amount as needed.
     */
    function withdraw(uint256 amount, address user) external override onlyVault {
        // Use this function to account for protocol fees not withdrawn yet
        uint256 tokenBalance = balanceOfDepositToken();

        // Remove amount needed from farm
        if (tokenBalance < amount) {
            masterChef.withdraw(poolId, amount - tokenBalance);
            // Update local balance after withdraw
            tokenBalance = balanceOfDepositToken();
        }

        // Cap amount that can be used for rest of calculations
        if (tokenBalance > amount) {
            tokenBalance = amount;
        }

        // Deduct withdrawal fees as needed
        if (!isFeeExempt(user)) {
            // Standard withdraw fee for remaining depositors.
            // Happens whether protocol fee is set or not.
            // Take this fee first to benefit users
            tokenBalance -= getDepositorsWithdrawFeeBonus(tokenBalance);

            // Protocol portion
            uint256 withdrawFee = getProtocolWithdrawFee();
            if (withdrawFee > 0) {
                uint256 protocolWithdrawalFeeAmount = _getFeeAmount(tokenBalance, withdrawFee);
                _updatePendingFees(protocolWithdrawalFeeAmount);
                tokenBalance -= protocolWithdrawalFeeAmount;
            }
        }

        // Vault will complete process for user withdraw as needed
        depositToken.safeTransfer(_vault, tokenBalance);

        emit Withdraw(balanceOfDepositToken());
    }

    // =================================== VIEW ====================================== //

    function isFeeExempt(address who) public override returns (bool) {
        // Short circuit with NFT check if possible
        if (_nftAddress != address(0) && IERC721(_nftAddress).balanceOf(who) > 0) {
            return true;
        }

        return super.isFeeExempt(who);
    }

    // ================================= ADMIN STATE TRANSITIONS ===================================== //

    /// @dev Update NFT contract used for fee exemptions.
    /// @dev Send address zero to disable NFT fee exemption feature.
    function updateNftAddress(address _nftContract) external onlyManager {
        _nftAddress = _nftContract;
    }
}