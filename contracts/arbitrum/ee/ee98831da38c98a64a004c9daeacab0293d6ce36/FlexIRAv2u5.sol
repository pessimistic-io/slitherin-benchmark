// Sources flattened with hardhat v2.12.5 https://hardhat.org
// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol@v4.8.1

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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

pragma solidity ^0.8.2;

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
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
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


// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v4.8.1


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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
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


// File @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol@v4.8.1


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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

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
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol@v4.8.1


// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;




/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v4.8.0


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


// File contracts/dpt/DividendPayingTokenInterface.sol



pragma solidity ^0.8.6;


/// @title Dividend-Paying Token Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev An interface for a dividend-paying token contract.
interface DividendPayingTokenInterface {
  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function dividendOf(address _owner) external view returns(uint256);

  /// @notice Distributes ether to token holders as dividends.
  /// @dev SHOULD distribute the paid ether to token holders as dividends.
  ///  SHOULD NOT directly transfer ether to token holders in this function.
  ///  MUST emit a `DividendsDistributed` event when the amount of distributed ether is greater than 0.
  function distributeDividends() external payable;

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev SHOULD transfer `dividendOf(msg.sender)` wei to `msg.sender`, and `dividendOf(msg.sender)` SHOULD be 0 after the transfer.
  ///  MUST emit a `DividendWithdrawn` event if the amount of ether transferred is greater than 0.
  function withdrawDividend() external;

  /// @dev This event MUST emit when ether is distributed to token holders.
  /// @param from The address which sends ether to this contract.
  /// @param weiAmount The amount of distributed ether in wei.
  event DividendsDistributed(
    address indexed from,
    uint256 weiAmount
  );

  /// @dev This event MUST emit when an address withdraws their dividend.
  /// @param to The address which withdraws ether from this contract.
  /// @param weiAmount The amount of withdrawn ether in wei.
  event DividendWithdrawn(
    address indexed to,
    uint256 weiAmount
  );
}


// File contracts/dpt/DividendPayingTokenOptionalInterface.sol



pragma solidity ^0.8.6;


/// @title Dividend-Paying Token Optional Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev OPTIONAL functions for a dividend-paying token contract.
interface DividendPayingTokenOptionalInterface {
  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function withdrawableDividendOf(address _owner) external view returns(uint256);

  /// @notice View the amount of dividend in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has withdrawn.
  function withdrawnDividendOf(address _owner) external view returns(uint256);

  /// @notice View the amount of dividend in wei that an address has earned in total.
  /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has earned in total.
  function accumulativeDividendOf(address _owner) external view returns(uint256);
}


// File contracts/dpt/math/SafeMath.sol

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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


// File contracts/dpt/math/SafeMathInt.sol

pragma solidity ^0.8.6;

/**
 * @title SafeMathInt
 * @dev Math operations with safety checks that revert on error
 * @dev SafeMath adapted for int256
 * Based on code of  https://github.com/RequestNetwork/requestNetwork/blob/master/packages/requestNetworkSmartContracts/contracts/base/math/SafeMathInt.sol
 */
library SafeMathInt {
  function mul(int256 a, int256 b) internal pure returns (int256) {
    // Prevent overflow when multiplying INT256_MIN with -1
    // https://github.com/RequestNetwork/requestNetwork/issues/43
    require(!(a == - 2**255 && b == -1) && !(b == - 2**255 && a == -1));

    int256 c = a * b;
    require((b == 0) || (c / b == a));
    return c;
  }

  function div(int256 a, int256 b) internal pure returns (int256) {
    // Prevent overflow when dividing INT256_MIN by -1
    // https://github.com/RequestNetwork/requestNetwork/issues/43
    require(!(a == - 2**255 && b == -1) && (b > 0));

    return a / b;
  }

  function sub(int256 a, int256 b) internal pure returns (int256) {
    require((b >= 0 && a - b <= a) || (b < 0 && a - b > a));

    return a - b;
  }

  function add(int256 a, int256 b) internal pure returns (int256) {
    int256 c = a + b;
    require((b >= 0 && c >= a) || (b < 0 && c < a));
    return c;
  }

  function toUint256Safe(int256 a) internal pure returns (uint256) {
    require(a >= 0);
    return uint256(a);
  }
}


// File contracts/dpt/math/SafeMathUint.sol

pragma solidity ^0.8.6;

/**
 * @title SafeMathUint
 * @dev Math operations with safety checks that revert on error
 */
library SafeMathUint {
  function toInt256Safe(uint256 a) internal pure returns (int256) {
    int256 b = int256(a);
    require(b >= 0);
    return b;
  }
}


// File contracts/IFlexIRARefLottery.sol



pragma solidity ^0.8.0;

interface IFlexIRARefLottery {

    struct LotteryResultState {
        uint lotteryId;
        address winner;
        uint winnerTicket;
        uint winnerTotalTickets;
        uint totalTickets;
        uint amount;
        uint tsSec;
    }

    function transfer(address to, uint amount) external;
    function addTickets(address user, uint amount) external;
    function runLottery() external returns (LotteryResultState memory);

}


// File contracts/FlexIRAv2u5.sol

/**
 *
 *   /$$$$$$$$ /$$                     /$$$$$$ /$$$$$$$   /$$$$$$
 *  | $$_____/| $$                    |_  $$_/| $$__  $$ /$$__  $$
 *  | $$      | $$  /$$$$$$  /$$   /$$  | $$  | $$  \ $$| $$  \ $$
 *  | $$$$$   | $$ /$$__  $$|  $$ /$$/  | $$  | $$$$$$$/| $$$$$$$$
 *  | $$__/   | $$| $$$$$$$$ \  $$$$/   | $$  | $$__  $$| $$__  $$
 *  | $$      | $$| $$_____/  >$$  $$   | $$  | $$  \ $$| $$  | $$
 *  | $$      | $$|  $$$$$$$ /$$/\  $$ /$$$$$$| $$  | $$| $$  | $$
 *  |__/      |__/ \_______/|__/  \__/|______/|__/  |__/|__/  |__/
 *
 *  Version 2 update 5
 *
 *  FlexIRA (FIRA)
 *  https://fira.flex.community
 *
 */
pragma solidity ^0.8.6;

/// @title FlexIRA
/// @dev Based on Roger Wu's Dividend-Paying Token (https://github.com/roger-wu)
///  A mintable ERC20 token that allows anyone to pay and distribute ERC20 tokens
///  to token holders as dividends and allows token holders to withdraw their dividends.
contract FlexIRAv2u5 is ERC20Upgradeable, DividendPayingTokenInterface, DividendPayingTokenOptionalInterface, OwnableUpgradeable {

    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    // With `magnitude`, we can properly distribute dividends even if the amount of received ether is small.
    // For more discussion about choosing the value of `magnitude`,
    //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
    uint256 constant internal magnitude = 2 ** 128;

    uint256 internal magnifiedDividendPerShare;

    // About dividendCorrection:
    // If the token balance of a `_user` is never changed, the dividend of `_user` can be computed with:
    //   `dividendOf(_user) = dividendPerShare * balanceOf(_user)`.
    // When `balanceOf(_user)` is changed (via minting/burning/transferring tokens),
    //   `dividendOf(_user)` should not be changed,
    //   but the computed value of `dividendPerShare * balanceOf(_user)` is changed.
    // To keep the `dividendOf(_user)` unchanged, we add a correction term:
    //   `dividendOf(_user) = dividendPerShare * balanceOf(_user) + dividendCorrectionOf(_user)`,
    //   where `dividendCorrectionOf(_user)` is updated whenever `balanceOf(_user)` is changed:
    //   `dividendCorrectionOf(_user) = dividendPerShare * (old balanceOf(_user)) - (new balanceOf(_user))`.
    // So now `dividendOf(_user)` returns the same value before and after `balanceOf(_user)` is changed.
    mapping(address => int256) internal magnifiedDividendCorrections;
    mapping(address => uint256) internal withdrawnDividends;

    IERC20 public token;

    address public assetFundWallet;
    address public depositFeeWallet;
    address public devWallet;

    uint256 public minUserDeposit;
    uint256 public maxUserDeposit;

    uint256 public maxTotalSupply;
    mapping(address => uint256) internal maxUserSupply;

    // V2
    uint256 constant SECONDS_IN_DAY = 60 * 60 * 24;

    uint256 public devFeePct100;
    uint256 public depositFeePct100;

    struct WithdrawReq {
        address user;
        uint256 amount;
        uint256 createdAt;
        uint256 filledAt;
    }

    WithdrawReq[] public withdrawRequestQueue;
    uint256 public curWithdrawRequestIndex;
    uint256 public withdrawRequestsTotal;

    mapping(address => uint256[]) public withdrawRequestQueueIndexByUser;
    mapping(address => uint256) public curWithdrawRequestByUser;
    mapping(address => uint256) public withdrawRequestsBalanceByUser;

    mapping(uint256 => uint256) public withdrawRequestCountByDay;
    mapping(uint256 => uint256) public withdrawRequestTotalByDay;

    uint256 public filledWithdrawRequestTotal;
    mapping(uint256 => uint256) public filledWithdrawRequestCountByDay;
    mapping(uint256 => uint256) public filledWithdrawRequestTotalByDay;

    uint256 public withdrawPoolBalance;

    uint256 public totalDistributedDividends;
    bool public ignoreMaxTotalSupplyLimitOnCompound;

    // v2.1
    IFlexIRARefLottery public lottery;

    bool public depositOnlyWithRef;
    mapping(address => uint8) public userVersion;
    mapping(address => uint) public userEnterDate;
    mapping(address => address) public userReferrer;
    mapping(address => uint) public userReferralLevel;

    uint256 public depositFeeV2u1Pct100;
    uint256 public referralFeePct1000;
    uint256 public lotteryFeePct1000;
    mapping(address => uint256) public referralBonus;
    mapping(address => uint256) public refereeCount;

    uint256 public totalUsers;
    uint256 public totalUsersLimit;
    mapping(address => bool) public totalUsersLimitExclude;

    uint public totalReferralPerUserLimit;
    mapping(uint256 => uint256) public totalReferralForLevelLimit;
    mapping(address => uint256) public totalReferralForUserLimit;

    // v2.2
    event DividendWithdrawn2(
        address indexed to,
        uint256 weiAmount
    );
    event DividendCompounded2(
        address indexed to,
        uint256 weiAmount
    );

    mapping(address => uint256) public compoundedDividends;

    mapping(address => uint256) public compoundInvites_lastInviteDate;
    uint256 public compoundInvites_periodSec;
    uint256 public compoundInvites_compoundPerc100;

    uint256 public depositLockTimeSec;
    mapping(address => uint256) public depositLockTimeSecForUser;
    bool public paused;

    // V2.3
    mapping(address => uint256) public removedReferralForUser;

    // V2.4
    uint256 public minUserFirstDeposit;

    function getVersion() public view returns (uint256, uint256) {
        return (2, 5);
    }

    function initialize(address token_, address assetFund_, address devWalletAddr_, address depositFeeWallet_) public initializer {
        __ERC20_init("FlexIRAv2", "FIRA");
        __Ownable_init();

        token = IERC20(token_);
        assetFundWallet = assetFund_;
        devWallet = devWalletAddr_;
        depositFeeWallet = depositFeeWallet_;

        minUserDeposit = 1 ether;
        maxUserDeposit = 100000 ether;
        maxTotalSupply = 0 ether;

        devFeePct100 = 2;
        depositFeePct100 = 5;

        curWithdrawRequestIndex = 0;
        withdrawRequestsTotal = 0;
        ignoreMaxTotalSupplyLimitOnCompound = true;
    }

    function initializeV2u1(IFlexIRARefLottery lottery_, uint totalUsers_, uint totalUsersLimit_) public reinitializer(2) {
        depositOnlyWithRef = true;

        depositFeeV2u1Pct100 = 8;
        referralFeePct1000 = 25;
        lotteryFeePct1000 = 25;

        totalReferralPerUserLimit = 0;

        lottery = lottery_;
        totalUsers = totalUsers_;
        totalUsersLimit = totalUsersLimit_;
    }

    function initializeV2u2() public reinitializer(3) {
        compoundInvites_periodSec = 30 days;
        compoundInvites_compoundPerc100 = 75;

        depositLockTimeSec = 180 days;
        paused = true;
    }

    function set_assetFundWallet(address addr) public onlyOwner {
        assetFundWallet = addr;
    }

    function set_devWallet(address addr) public onlyOwner {
        devWallet = addr;
    }

    function set_depositFeeWallet(address addr) public onlyOwner {
        depositFeeWallet = addr;
    }

    function set_minUserDeposit(uint256 value) public onlyOwner {
        minUserDeposit = value;
    }

    function set_minUserFirstDeposit(uint256 value) public onlyOwner {
        minUserFirstDeposit = value;
    }

    function set_maxUserDeposit(uint256 value) public onlyOwner {
        maxUserDeposit = value;
    }

    function set_maxTotalSupply(uint256 value) public onlyOwner {
        maxTotalSupply = value;
    }

    function set_maxUserSupply(address account, uint256 value) public onlyOwner {
        maxUserSupply[account] = value;
    }

    function set_devFee(uint256 value) public onlyOwner {
        devFeePct100 = value;
    }

    function set_depositFee(uint256 value) public onlyOwner {
        depositFeePct100 = value;
    }

    function set_ignoreMaxTotalSupplyLimit(bool value) public onlyOwner {
        ignoreMaxTotalSupplyLimitOnCompound = value;
    }

    function set_depositOnlyWithRef(bool value) public onlyOwner {
        depositOnlyWithRef = value;
    }

    function set_lottery(IFlexIRARefLottery value) public onlyOwner {
        lottery = value;
    }

    function set_depositFeeV2u1Pct100(uint value) public onlyOwner {
        depositFeeV2u1Pct100 = value;
    }

    function set_referralFeePct1000(uint value) public onlyOwner {
        referralFeePct1000 = value;
    }

    function set_lotteryFeePct1000(uint value) public onlyOwner {
        lotteryFeePct1000 = value;
    }

    function set_totalUsersLimit(uint value) public onlyOwner {
        totalUsersLimit = value;
    }

    function set_totalReferralPerUserLimit(uint value) public onlyOwner {
        totalReferralPerUserLimit = value;
    }

    function set_totalReferralForLevelLimit(uint level, uint value) public onlyOwner {
        totalReferralForLevelLimit[level] = value;
    }

    function set_compoundInvites_periodSec(uint256 value) public onlyOwner {
        compoundInvites_periodSec = value;
    }
    function set_compoundInvites_compoundPerc100(uint256 value) public onlyOwner {
        compoundInvites_compoundPerc100 = value;
    }

    function set_usersVersion(address[] calldata user, uint8 version, bool adjustTotalUsers) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            if (adjustTotalUsers) {
                if (userVersion[user[i]] == 0) {
                    totalUsers++;
                    userEnterDate[user[i]] = block.timestamp;
                }
            }
            userVersion[user[i]] = version;
        }
    }

    function set_totalUsersLimitExclude(address[] calldata user, bool value) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            totalUsersLimitExclude[user[i]] = value;
        }
    }

    function set_totalReferralForUserLimit(address[] calldata user, uint256 value) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            totalReferralForUserLimit[user[i]] = value;
        }
    }

    function set_compoundedDividends(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            compoundedDividends[user[i]] = values[i];
        }
    }

    function set_depositLockTimeSec(uint256 value) public onlyOwner {
        depositLockTimeSec = value;
    }

    function set_depositLockTimeSecForUser(address[] calldata user, uint256 value) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            depositLockTimeSecForUser[user[i]] = value;
        }
    }

    function set_paused(bool value) public onlyOwner {
        paused = value;
    }

    function getInitializedVersion() public view returns (uint8) {
        return _getInitializedVersion();
    }


    function getUserReferralLimit(address user) public view returns (uint256) {
        if (userVersion[user] == 0) {
            return 0;
        }
        uint256 totalLimit = totalReferralForUserLimit[user] + totalReferralForLevelLimit[userReferralLevel[user]] + totalReferralPerUserLimit;
        uint256 removed =  removedReferralForUser[user];
        if (totalLimit > removed) {
            return totalLimit - removed;
        } else {
            return 0;
        }
    }

    function getUserReferralLeft(address user) public view returns (uint256) {
        uint limit = getUserReferralLimit(user);
        uint used = refereeCount[user];
        if (limit < used) {
            return 0;
        }
        return limit - used;
    }

    // Correct total users for whitelisted
    function changeTotalUsers(bool add, uint value) public onlyOwner {
        if (add) {
            totalUsers += value;
        } else {
            totalUsers -= value;
        }
    }

    function deposit(uint256 amount) public {
        require(!paused, "FlexIRA: contract is paused");
        require(userVersion[msg.sender] == 1, "Deposit without Referrer available only for old users");
        depositWithRef(amount, address(0));
    }

    function depositWithRef(uint256 amount, address referrer) public {
        require(!paused, "FlexIRA: contract is paused");

        if (userVersion[msg.sender] == 0) {
            require(amount >= minUserFirstDeposit, "FlexIRA: first deposit less than required");

            if (!totalUsersLimitExclude[msg.sender]) {
                require(totalUsers < totalUsersLimit, "FlexIRA: total user limit reached");
            }
            totalUsers++;

            userVersion[msg.sender] = 2;
            userEnterDate[msg.sender] = block.timestamp;

            if (depositOnlyWithRef) {
                require(referrer != address(0), "Referrer is required");
                require(referrer != msg.sender, "Sender can not be referrer");
                require(userVersion[referrer] > 0, "Referrer must be in contract");
            }

            if (referrer != address(0) && referrer != msg.sender && userVersion[referrer] > 0) {
                userReferrer[msg.sender] = referrer;
                require(getUserReferralLimit(referrer) > refereeCount[referrer], "FlexIRA: user's referral limit is reached");
                userReferralLevel[msg.sender] = userReferralLevel[referrer] + 1;
                refereeCount[referrer]++;
            }

        }

        require(amount >= minUserDeposit, "FlexIRA: deposit is less than min user's deposit");
        require(amount <= maxUserDeposit, "FlexIRA: deposit is greater than max user's deposit");

        _safeTransferTokensFrom(msg.sender, address(this), amount);

        _processDeposit(amount, false);
    }

    function _processDeposit(uint256 amount, bool ignoreMaxTotalSupply) internal {
        address ref = userReferrer[msg.sender];

        // Fees
        uint256 devFee = amount * devFeePct100 / 100;
        uint256 depositFee = amount * depositFeePct100 / 100;
        if (userVersion[msg.sender] > 1) {
            depositFee = amount * depositFeeV2u1Pct100 / 100;
        }

        uint256 referrerFee = 0;
        uint256 lotteryFee = 0;
        if (ref != address(0)) {
            referrerFee = amount * referralFeePct1000 / 1000;
            lotteryFee = amount * lotteryFeePct1000 / 1000;

            _safeTransferTokens(address(lottery), lotteryFee);
            lottery.addTickets(ref, lotteryFee);

            referralBonus[ref] += referrerFee;
            _mintWithLimit(ref, referrerFee, true);
        }

        _safeTransferTokens(devWallet, devFee);
        _safeTransferTokens(depositFeeWallet, depositFee);

        uint256 netAmount = amount.sub(devFee).sub(depositFee).sub(referrerFee).sub(lotteryFee);

        _safeTransferTokens(assetFundWallet, netAmount.add(referrerFee));

        _mintWithLimit(msg.sender, netAmount, ignoreMaxTotalSupply);
    }

    function addReferralForUsers(address[] calldata user, uint256 amount) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            _addReferralForUser(user[i], amount);
        }
    }

    function removeReferralForUsers(address[] calldata user, int256 amount) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            if (amount >= 0) {
                removedReferralForUser[user[i]] += uint256(amount);
            } else {
                uint256 absAmount = uint(-amount);
                if (absAmount > removedReferralForUser[user[i]]) {
                    removedReferralForUser[user[i]] = 0;
                } else {
                    removedReferralForUser[user[i]] -= absAmount;
                }
            }
        }
    }

    function _addReferralForUser(address user, uint256 amount) internal {
        totalReferralForUserLimit[user] += amount;
    }

    function withdrawAllDeposit() public {
        withdrawDeposit(balanceOf(msg.sender));
    }

    function withdrawDeposit(uint256 amount) public {
        require(!paused, "FlexIRA: contract is paused");

        uint256 myBalance = balanceOf(msg.sender);
        require(myBalance > 0, "FlexIRA: balance is empty");
        require(myBalance >= amount, "FlexIRA: amount exceed balance");

        require(depositLockLeftSec(msg.sender) == 0, "FlexIRA: deposits can be withdrawn after the lock period only");

        uint todayMidnight = currentDayMidnight();

        WithdrawReq memory wreq = WithdrawReq({
        user : msg.sender,
        amount : amount,
        createdAt : block.timestamp,
        filledAt : 0
        });
        withdrawRequestQueueIndexByUser[msg.sender].push(withdrawRequestQueue.length);
        withdrawRequestQueue.push(wreq);
        withdrawRequestsTotal += amount;
        withdrawRequestTotalByDay[todayMidnight] += amount;
        withdrawRequestCountByDay[todayMidnight]++;
        withdrawRequestsBalanceByUser[msg.sender] += amount;

        _burn(msg.sender, amount);
    }

    function fillWithdrawRequests(uint256 amount, uint256 maxWithdrawRequests) public {
        require(!paused, "FlexIRA: contract is paused");

        if (amount > 0) {
            _safeTransferTokensFrom(msg.sender, address(this), amount);
            withdrawPoolBalance += amount;
        }

        WithdrawReq storage wr;
        while (true) {
            if (maxWithdrawRequests <= 0) {
                return;
            }
            maxWithdrawRequests--;

            if (curWithdrawRequestIndex >= withdrawRequestQueue.length) {
                return;
            }

            wr = withdrawRequestQueue[curWithdrawRequestIndex];

            if (wr.amount <= withdrawPoolBalance) {
                uint midnight = wr.createdAt / SECONDS_IN_DAY * SECONDS_IN_DAY;

                _safeTransferTokens(wr.user, wr.amount);

                withdrawPoolBalance -= wr.amount;
                withdrawRequestsBalanceByUser[wr.user] -= wr.amount;
                curWithdrawRequestByUser[wr.user]++;
                filledWithdrawRequestTotal += wr.amount;
                filledWithdrawRequestTotalByDay[midnight] += wr.amount;
                filledWithdrawRequestCountByDay[midnight]++;

                wr.filledAt = block.timestamp;
                curWithdrawRequestIndex++;
            } else {
                return;
            }
        }
    }

    function _safeTransferTokens(address to, uint value) internal {
        require(token.transfer(to, value), 'FlexIRA: transfer failed');
    }

    function _safeTransferTokensFrom(address from, address to, uint value) internal {
        require(token.transferFrom(from, to, value), 'FlexIRA: transfer from failed');
    }

    /// @dev Distributes dividends whenever ether is paid to this contract.
    // receive() external payable {
    //     distributeDividends();
    // }

    /// @notice Distributes ether to token holders as dividends.
    /// @dev It reverts if the total supply of tokens is 0.
    /// It emits the `DividendsDistributed` event if the amount of received ether is greater than 0.
    /// About undistributed ether:
    ///   In each distribution, there is a small amount of ether not distributed,
    ///     the magnified amount of which is
    ///     `(msg.value * magnitude) % totalSupply()`.
    ///   With a well-chosen `magnitude`, the amount of undistributed ether
    ///     (de-magnified) in a distribution can be less than 1 wei.
    ///   We can actually keep track of the undistributed ether in a distribution
    ///     and try to distribute it in the next distribution,
    ///     but keeping track of such data on-chain costs much more than
    ///     the saved ether, so we don't do that.
    function distributeDividends() public override payable {
        revert("not supported");
    }

    function distributeTokenDividends(uint256 amount) public {
        require(!paused, "FlexIRA: contract is paused");
        require(totalSupply() > 0, "FlexIRA: no holders");

        if (amount > 0) {
            _safeTransferTokensFrom(msg.sender, address(this), amount);

            totalDistributedDividends += amount;

            magnifiedDividendPerShare = magnifiedDividendPerShare.add(
                (amount).mul(magnitude) / totalSupply()
            );

            emit DividendsDistributed(msg.sender, amount);

        }
    }

    /// @notice Withdraws the ether distributed to the sender.
    /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
    function withdrawDividend() public override {
        uint256 _withdrawableDividend = withdrawableDividendOf(msg.sender);
        withdrawDividendAndCompoundRest(_withdrawableDividend);
    }

    function compoundDividend() public {
        withdrawDividendAndCompoundRest(0);
    }

    function withdrawDividendAndCompoundRest(uint256 withdrawAmount) public {
        require(!paused, "FlexIRA: contract is paused");

        uint256 _withdrawableDividend = withdrawableDividendOf(msg.sender);
        require(withdrawAmount <= _withdrawableDividend, "FlexIRA: withdrawAmount more than user's dividends");
        if (_withdrawableDividend > 0) {
            uint256 compoundAmount = _withdrawableDividend.sub(withdrawAmount);

            if (withdrawAmount > 0) {
                withdrawnDividends[msg.sender] = withdrawnDividends[msg.sender].add(withdrawAmount);
                _safeTransferTokens(msg.sender, withdrawAmount);
                emit DividendWithdrawn2(msg.sender, _withdrawableDividend);
            }
            if (compoundAmount > 0) {
                withdrawnDividends[msg.sender] = withdrawnDividends[msg.sender].add(compoundAmount);
                compoundedDividends[msg.sender] = compoundedDividends[msg.sender].add(compoundAmount);
                // deposit dividends instead of withdraw
                _processDeposit(compoundAmount, ignoreMaxTotalSupplyLimitOnCompound);
                emit DividendCompounded2(msg.sender, _withdrawableDividend);
            }

            if (compoundInvites_periodSec > 0) {
                uint lastInvite = compoundInvites_lastInviteDate[msg.sender] > 0 ? compoundInvites_lastInviteDate[msg.sender] : userEnterDate[msg.sender];
                if (block.timestamp - lastInvite >= compoundInvites_periodSec) {
                    if (compoundedDividends[msg.sender] * 100 / withdrawnDividends[msg.sender] >= compoundInvites_compoundPerc100) {
                        compoundInvites_lastInviteDate[msg.sender] = block.timestamp;
                        _addReferralForUser(msg.sender, 1);
                    }
                }
            }
        }
    }

    function calcWithdrawCompoundByWeights(uint256 dividends, uint256 compoundWeight, uint256 withdrawWeight) public view
    returns (uint256 compound, uint256 withdraw) {
        uint256 totalWeight = compoundWeight + withdrawWeight;
        if (totalWeight == 0) {
            return (dividends, 0);
        }
        withdraw = dividends * withdrawWeight / totalWeight;
        compound = dividends - withdraw;
        return (compound, withdraw);
    }


    function withdrawDividendAndCompoundByWeights(uint256 compoundWeight, uint256 withdrawWeight) public {
        uint256 _withdrawableDividend = withdrawableDividendOf(msg.sender);
        if (_withdrawableDividend > 0) {
            (uint256 compound, uint256 withdraw) = calcWithdrawCompoundByWeights(_withdrawableDividend, compoundWeight, withdrawWeight);
            withdrawDividendAndCompoundRest(withdraw);
        }
    }

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function dividendOf(address _owner) public view override returns (uint256) {
        return withdrawableDividendOf(_owner);
    }

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function withdrawableDividendOf(address _owner) public view override returns (uint256) {
        return accumulativeDividendOf(_owner).sub(withdrawnDividends[_owner]);
    }

    /// @notice View the amount of dividend in wei that an address has withdrawn.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has withdrawn.
    function withdrawnDividendOf(address _owner) public view override returns (uint256) {
        return withdrawnDividends[_owner];
    }


    /// @notice View the amount of dividend in wei that an address has earned in total.
    /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
    /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has earned in total.
    function accumulativeDividendOf(address _owner) public view override returns (uint256) {
        return magnifiedDividendPerShare.mul(balanceOf(_owner)).toInt256Safe()
        .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / magnitude;
    }

    /// @dev Internal function that transfer tokens from one address to another.
    /// Update magnifiedDividendCorrections to keep dividends unchanged.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param value The amount to be transferred.
    function _transfer(address from, address to, uint256 value) internal override {
        require(false, "FlexIRA: no transfers allowed");
    }

    function _approve(address from, address to, uint256 value) internal override {
        require(false, "FlexIRA: approving is not allowed");
    }

    /// @dev Internal function that mints tokens to an account.
    /// Update magnifiedDividendCorrections to keep dividends unchanged.
    /// @param account The account that will receive the created tokens.
    /// @param value The amount that will be created.
    function _mintWithLimit(address account, uint256 value, bool ignoreMaxTotalSupply) internal {
        super._mint(account, value);
        // If user are out of user personal limit check global limit
        if (!ignoreMaxTotalSupply) {
            if (balanceOf(account) > maxUserSupply[account]) {
                require(totalSupply() < maxTotalSupply, "FlexIRA: total deposit pool exceed allowance");
            }
        }

        magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
        .sub((magnifiedDividendPerShare.mul(value)).toInt256Safe());
    }

    /// @dev Internal function that burns an amount of the token of a given account.
    /// Update magnifiedDividendCorrections to keep dividends unchanged.
    /// @param account The account whose tokens will be burnt.
    /// @param value The amount that will be burnt.
    function _burn(address account, uint256 value) internal override {
        super._burn(account, value);

        magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
        .add((magnifiedDividendPerShare.mul(value)).toInt256Safe());
    }

    function getWithdrawRequestsQueueLength() public view returns (uint256) {
        return withdrawRequestQueue.length;
    }

    function getActiveWithdrawRequests() public view returns (uint256) {
        return withdrawRequestQueue.length - curWithdrawRequestIndex;
    }

    function getActiveWithdrawRequestsForUser(address user) public view returns (uint256) {
        return withdrawRequestQueueIndexByUser[user].length - curWithdrawRequestByUser[user];
    }

    function getActiveWithdrawRequestForUserAt(address user, uint256 pos) public view returns (WithdrawReq memory) {
        uint256 posIndexInQueue = withdrawRequestQueueIndexByUser[user][curWithdrawRequestByUser[user] + pos];
        return withdrawRequestQueue[posIndexInQueue];
    }

    function getWithdrawRequestForUserAt(address user, uint256 pos) public view returns (WithdrawReq memory) {
        uint256 posIndexInQueue = withdrawRequestQueueIndexByUser[user][pos];
        return withdrawRequestQueue[posIndexInQueue];
    }

    function currentDayMidnight() virtual public view returns (uint256) {
        return block.timestamp / SECONDS_IN_DAY * SECONDS_IN_DAY;
    }

    function depositLockLeftSec(address user) virtual public view returns (uint256) {
        if (userEnterDate[user] == 0) {
            return 0;
        }
        uint myDepositTimeSec = block.timestamp - userEnterDate[user];
        uint myDepositLockTimeSec = depositLockTimeSecForUser[user] > 0 ? depositLockTimeSecForUser[user] : depositLockTimeSec;
        if (myDepositTimeSec >= myDepositLockTimeSec) {
            return 0;
        }
        return myDepositLockTimeSec - myDepositTimeSec;
    }

    function maxUint256(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? a : b;
    }

    function runLottery() public onlyOwner {
        IFlexIRARefLottery.LotteryResultState memory lotteryResult = lottery.runLottery();

        lottery.transfer(assetFundWallet, lotteryResult.amount);
        _mintWithLimit(lotteryResult.winner, lotteryResult.amount, true);
    }


    //////////////////////////////////////////// Migration
    function transferTokensFromContract(IERC20 token, address to, uint amount) public onlyOwner  {
        token.transfer(to, amount);
    }

    // mapping(address => uint256) internal maxUserSupply;
    function get_maxUserSupply(address addr) public view returns (uint256) {
        return maxUserSupply[addr];
    }


    // uint256 internal magnifiedDividendPerShare;
    function get_magnifiedDividendPerShare() public view returns (uint256) {
        return magnifiedDividendPerShare;
    }

    function restore_magnifiedDividendPerShare(uint256 value) public onlyOwner {
        magnifiedDividendPerShare = value;
    }

    // mapping(address => int256) internal magnifiedDividendCorrections;
    function get_magnifiedDividendCorrections(address addr) public view returns (int256) {
        return magnifiedDividendCorrections[addr];
    }

    function restore_magnifiedDividendCorrections(address[] calldata user, int256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            magnifiedDividendCorrections[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) internal withdrawnDividends;
    function restore_withdrawnDividends(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            withdrawnDividends[user[i]] = values[i];
        }
    }

    // uint256 public totalDistributedDividends;
    function restore_totalDistributedDividends(uint256 value) public onlyOwner {
        totalDistributedDividends = value;
    }

    // mapping(address => uint) public userEnterDate;
    function restore_userEnterDate(address[] calldata user, uint[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            userEnterDate[user[i]] = values[i];
        }
    }

    // mapping(address => uint) public userEnterDate;
    function restore_userReferrer(address[] calldata user, address[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            userReferrer[user[i]] = values[i];
        }
    }

    // mapping(address => uint) public userReferralLevel;
    function restore_userReferralLevel(address[] calldata user, uint[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            userReferralLevel[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) public referralBonus;
    function restore_referralBonus(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            referralBonus[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) public referralBonus;
    function restore_refereeCount(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            refereeCount[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) public compoundInvites_lastInviteDate;
    function restore_compoundInvites_lastInviteDate(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            compoundInvites_lastInviteDate[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) public removedReferralForUser;
    function restore_removedReferralForUser(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            removedReferralForUser[user[i]] = values[i];
        }
    }

    // mapping(address => uint256) public totalReferralForUserLimit;
    function restore_totalReferralForUserLimit(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            totalReferralForUserLimit[user[i]] = values[i];
        }
    }

    // mapping(address => uint) public userEnterDate;
    function restore_userVersion(address[] calldata user, uint8[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            userVersion[user[i]] = values[i];
        }
    }

    function restore_balances(address[] calldata user, uint256[] calldata values) public onlyOwner {
        for (uint i = 0; i < user.length; i++) {
            uint256 value = values[i];
            uint256 userBalance = balanceOf(user[i]);
            if (userBalance > value) {
                _burn(user[i], value - userBalance);
            }
            if (userBalance < value) {
                _mint(user[i], value - userBalance);
            }
        }
    }

}