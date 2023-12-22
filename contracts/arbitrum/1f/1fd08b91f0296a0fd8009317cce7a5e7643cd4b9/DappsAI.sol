/**
// Website:  https://DefiApps.AI Telegram: https://t.me/DefiAppsAI Twitter: https://twitter.com/dappsai
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
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

/**
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * ////IMPORTANT: Beware that changing an allowance with this method brings the risk
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

/**
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;

////import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
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

/**
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity 0.8.19;

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

// pragma solidity >=0.6.2;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/**
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;

////import "../utils/Context.sol";

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
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
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

////import "./IERC20.sol";
////import "./extensions/IERC20Metadata.sol";
////import "../../utils/Context.sol";

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
contract ERC20 is Context, IERC20, IERC20Metadata {
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
    constructor(string memory name_, string memory symbol_) {
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
    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
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
    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
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
    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
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
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
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
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
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
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
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
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
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
}

/**
 *  SourceUnit: /Users/jmf/dev/DappsAI/contracts/DappsAI.sol
 */

//  SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

////import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
////import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
////import "@openzeppelin/contracts/access/Ownable.sol";
////import "./interfaces/IUniswap.sol";

contract DappsAI is ERC20, Ownable {
    mapping(address => bool) public blacklist;
    mapping(address => bool) public feeExempt;
    mapping(address => bool) public maxTxExempt;
    mapping(address => uint) private lastTx;
    mapping(address => bool) private cooldownWhitelist;
    mapping(address => bool) public preExemption;
    mapping(address => bool) public maxWalletExempt;

    uint8 public constant blockCooldown = 5;

    address public marketing;
    address public stakingPool;

    uint public totalBuyFee;
    uint public totalSellFee;

    uint public maxWalletAmount;
    uint public maxTxAmount;
    uint public maxBuyTxAmount;
    uint public maxSellTxAmount;

    uint public marketingFees;
    uint public stakingFees;
    uint public liquidityFees;

    uint public totalMarketingFees;
    uint public totalStakingFees;
    uint public totalLiquidityFees;

    uint public swapThreshold = 10 ether;

    uint8[3] public buyFees;
    uint8[3] public sellFees;
    uint256 public constant BASE = 100;
    address public constant DEAD_WALLET =
        0x000000000000000000000000000000000000dEaD;

    bool public tradingOpen = false;
    bool public limitsRemoved = false;
    bool private swapping = false;

    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    /// @notice Modifier to check if this is an internal swap
    modifier swapExecuting() {
        swapping = true;
        _;
        swapping = false;
    }

    constructor(address _mkt, address _stk) ERC20("Dapps AI", "DappsAI") {
        require(_mkt != address(0) && _stk != address(0), "Invalid address");
        marketing = _mkt;
        stakingPool = _stk;
        // 100 million tokens
        _mint(msg.sender, 100_000_000 ether);
        // max Tx amount is 1% of total supply
        maxTxAmount = 100_000_000 ether / 100;
        maxBuyTxAmount = maxTxAmount;
        maxSellTxAmount = maxTxAmount;
        // max wallet amount is 2% of total supply
        maxWalletAmount = maxTxAmount * 3;

        buyFees[0] = 6;
        buyFees[1] = 1;
        buyFees[2] = 1;
        sellFees[0] = 6;
        sellFees[1] = 1;
        sellFees[2] = 1;

        totalBuyFee = buyFees[0] + buyFees[1] + buyFees[2];
        totalSellFee = sellFees[0] + sellFees[1] + sellFees[2];

        // Set Uniswap V2 Router for both ETH and ARBITRUM
        if (block.chainid == 1) {
            router = IUniswapV2Router02(
                0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
            );
        } else if (block.chainid == 42161) {
            // need to double check this address on ARBITRUM
            router = IUniswapV2Router02(
                0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
            );
        } else revert("Chain not supported");

        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        pair = IUniswapV2Pair(factory.createPair(address(this), router.WETH()));

        setFeeExempt(address(this), true);
        setFeeExempt(owner(), true);
        setMaxTxExempt(address(this), true);
        setMaxTxExempt(owner(), true);
        setCooldownWhitelist(address(this), true);
        setCooldownWhitelist(owner(), true);
        setCooldownWhitelist(marketing, true);
        setCooldownWhitelist(address(pair), true);
        setCooldownWhitelist(address(router), true);
        setMaxWalletExempt(address(this), true);
        setMaxWalletExempt(owner(), true);
        setMaxWalletExempt(marketing, true);
        setMaxWalletExempt(address(pair), true);
        setMaxWalletExempt(address(router), true);
        setPreExemption(address(this), true);
        setPreExemption(owner(), true);
    }

    /// @notice Allowed to receive ETH
    receive() external payable {}

    /// @notice Checks before Token Transfer
    /// @param from Address of sender
    /// @param to Address of receiver
    /// @param amount Amount of tokens to transfer
    /// @dev Checks if the sender and receiver are blacklisted or if amounts are within limits
    function _beforeTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (limitsRemoved || from == address(0) || to == address(0) || swapping)
            return;
        require(
            !blacklist[from] && !blacklist[to],
            "DappsAI: Blacklisted address"
        );
        // Only Owner can transfer tokens before trading is open
        if (!tradingOpen) require(preExemption[from], "DappsAI: Trading blocked");

        if (!maxTxExempt[from]) {
            if (from == address(pair)) {
                require(
                    amount <= maxBuyTxAmount,
                    "DappsAI: Max buy amount exceeded"
                );
            } else if (to == address(pair)) {
                require(
                    amount <= maxSellTxAmount,
                    "DappsAI: Max sell amount exceeded"
                );
            }
        }
        if (!maxWalletExempt[to]) {
            require(
                balanceOf(to) + amount <= maxWalletAmount,
                "DappsAI: Max wallet amount exceeded"
            );
        }
        if (!cooldownWhitelist[from]) {
            require(lastTx[from] <= block.number, "DappsAI: Bot?");
            lastTx[from] = block.number + blockCooldown;
        }
    }

    /// @notice Burn tokens from sender address
    /// @param amount Amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn tokens from other owners as long as it is approved
    /// @param account Address of owner
    /// @param amount Amount of tokens to burn
    function burnFrom(address account, uint256 amount) external {
        require(
            amount <= allowance(account, msg.sender),
            "DappsAI: Not enough allowance"
        );
        uint256 decreasedAllowance = allowance(account, msg.sender) - amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }

    /// @notice Internal transfer tokens
    /// @param sender Address of receiver
    /// @param recipient Address of receiver
    /// @param amount Amount of tokens to transfer
    /// @dev calls _beforeTokenTransfer, manages taxes and transfers tokens
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        _beforeTransfer(sender, recipient, amount);
        if (!swapping) {
            uint currentTokensHeld = balanceOf(address(this));
            if (
                currentTokensHeld >= swapThreshold &&
                sender != address(pair) &&
                sender != address(router)
            ) {
                _handleSwapAndDistribute(currentTokensHeld);
            }

            if (
                ((sender == address(pair) && !feeExempt[recipient]) ||
                    (recipient == address(pair) && !feeExempt[sender]))
            ) {
                uint totalFee = takeFee(amount, sender == address(pair));
                super._transfer(sender, address(this), totalFee);
                amount -= totalFee;
            }
        }

        super._transfer(sender, recipient, amount);
    }

    /// @notice Set the fee for a specific transaction type
    /// @param amount Amount of transaction
    /// @param isBuy True if transaction is a buy, false if transaction is a sell
    /// @return totalFee Total fee taken in this transaction
    function takeFee(
        uint256 amount,
        bool isBuy
    ) internal returns (uint256 totalFee) {
        uint selectedFee = isBuy ? totalBuyFee : totalSellFee;
        totalFee = (selectedFee * amount) / BASE;

        uint8[3] storage fees = isBuy ? buyFees : sellFees;

        uint marketingFee = (fees[0] * totalFee) / selectedFee;
        uint poolFee = (fees[1] * totalFee) / selectedFee;
        uint liqFee = totalFee - marketingFee - poolFee;

        marketingFees += marketingFee;
        stakingFees += poolFee;
        liquidityFees += liqFee;
    }

    /// @notice Swap tokens for ETH and distribute to marketing, liquidity and staking
    /// @param tokensHeld Amount of tokens held in contract to swap
    /// @dev to make the most out of the liquidity that is added, the contract will swap and add liquidity before swapping the amount to distribute
    function _handleSwapAndDistribute(uint tokensHeld) private swapExecuting {
        uint totalFees = marketingFees + stakingFees + liquidityFees;

        uint mkt = marketingFees;
        uint stk = stakingFees;
        uint liq = liquidityFees;

        if (totalFees != tokensHeld) {
            mkt = (marketingFees * tokensHeld) / totalFees;
            stk = (stakingFees * tokensHeld) / totalFees;
            liq = tokensHeld - mkt - stk;
        }
        if (liq > 0) _swapAndLiquify(liq);

        if (mkt + stk > 0) {
            swapTokensForEth(mkt + stk);
            uint ethBalance = address(this).balance;
            bool succ;
            if (mkt > 0) {
                mkt = (mkt * ethBalance) / (mkt + stk);
                (succ, ) = payable(marketing).call{value: mkt}("");
                require(succ);
                totalMarketingFees += mkt;
            }
            if (stk > 0) {
                stk = ethBalance - mkt;
                (succ, ) = payable(stakingPool).call{value: stk}("");
                require(succ);
                totalStakingFees += stk;
            }
        }
        marketingFees = 0;
        stakingFees = 0;
        liquidityFees = 0;
    }

    /// @notice Swap half of tokens for ETH and create liquidity from an external call
    function swapAndLiquify() public swapExecuting {
        require(
            liquidityFees >= balanceOf(address(this)),
            "DappsAI: Not enough tokens"
        );
        _swapAndLiquify(liquidityFees);
        liquidityFees = 0;
    }

    /// @notice Swap half tokens for ETH and create liquidity internally
    /// @param tokens Amount of tokens to swap
    function _swapAndLiquify(uint tokens) private {
        uint half = tokens / 2;
        uint otherHalf = tokens - half;

        uint initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint newBalance = address(this).balance - initialBalance;

        _approve(address(this), address(router), otherHalf);
        (, , uint liquidity) = router.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0,
            0,
            DEAD_WALLET,
            block.timestamp
        );

        totalLiquidityFees += liquidity;

        emit SwapAndLiquify(half, newBalance, liquidity);
    }

    /// @notice Swap tokens for ETH
    function swapTokensForEth(uint tokens) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokens);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // Only Owner section
    ///@notice Set the fee for buy transactions
    ///@param _marketing Marketing fee
    ///@param _pool Staking Pool fee
    ///@param _liq Liquidity fee
    ///@dev Fees are in percentage and cant be more than 25%
    function setBuyFees(
        uint8 _marketing,
        uint8 _pool,
        uint8 _liq
    ) external onlyOwner {
        totalBuyFee = _marketing + _pool + _liq;
        require(totalBuyFee <= 25, "Fees cannot be more than 25%");
        buyFees = [_marketing, _pool, _liq];
    }

    ///@notice Set the fee for sell transactions
    ///@param _marketing Marketing fee
    ///@param _pool Staking Pool fee
    ///@param _liq Liquidity fee
    ///@dev Fees are in percentage and cant be more than 25%
    function setSellFees(
        uint8 _marketing,
        uint8 _pool,
        uint8 _liq
    ) external onlyOwner {
        totalSellFee = _marketing + _pool + _liq;
        require(totalSellFee <= 25, "Fees cannot be more than 25%");
        sellFees = [_marketing, _pool, _liq];
    }

    ///@notice set address to be exempt from fees
    ///@param _address Address to be exempt
    ///@param exempt true or false
    function setFeeExempt(address _address, bool exempt) public onlyOwner {
        feeExempt[_address] = exempt;
    }

    ///@notice set address to be blacklisted
    ///@param _address Address to be blacklisted
    ///@param _blacklist true or false
    function setBlacklist(
        address _address,
        bool _blacklist
    ) external onlyOwner {
        blacklist[_address] = _blacklist;
    }

    ///@notice allow token trading to start
    function openTrade() external onlyOwner {
        tradingOpen = true;
    }

    ///@notice get tokens sent "mistakenly" to the contract
    ///@param _token Address of the token to be recovered
    function recoverToken(address _token) external onlyOwner {
        require(_token != address(this), "Cannot withdraw DappsAI");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

    /// @notice recover ETH sent to the contract
    function recoverETH() external onlyOwner {
        (bool succ, ) = payable(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(succ, "Transfer failed");
    }

    ///@notice set the marketing wallet address
    ///@param _marketing Address of the new marketing wallet
    ///@dev Marketing wallet address cannot be 0x0 or the current marketing wallet address
    function setMarketingWallet(address _marketing) external onlyOwner {
        require(
            _marketing != address(0) && _marketing != marketing,
            "Invalid address"
        );
        marketing = _marketing;
    }

    ///@notice set the staking pool address
    ///@param _stakingPool Address of the new staking pool
    ///@dev Staking pool address cannot be 0x0 or the current staking pool address
    function setStakingPool(address _stakingPool) external onlyOwner {
        require(
            _stakingPool != address(0) && _stakingPool != stakingPool,
            "Invalid address"
        );
        stakingPool = _stakingPool;
    }

    ///@notice set address to be exempt from max buys and sells
    ///@param _address Address to be exempt
    ///@param exempt true or false
    function setMaxTxExempt(address _address, bool exempt) public onlyOwner {
        maxTxExempt[_address] = exempt;
    }

    function setMaxBuy(uint256 _amount) external onlyOwner {
        require(_amount >= maxTxAmount, "Invalid Max Buy Amount");
        maxBuyTxAmount = _amount;
    }

    function setMaxSell(uint256 _amount) external onlyOwner {
        require(_amount >= maxTxAmount, "Invalid Max Sell Amount");
        maxSellTxAmount = _amount;
    }

    function setMaxTxAmount(uint256 _amount) external onlyOwner {
        require(_amount >= totalSupply() / 100, "Invalid Max Tx Amount");
        maxTxAmount = _amount;
    }

    function setMaxWalletAmount(uint256 _amount) external onlyOwner {
        require(_amount >= totalSupply() / 100, "Invalid Max Wallet Amount");
        maxWalletAmount = _amount;
    }

    function setSwapThreshold(uint256 _amount) external onlyOwner {
        require(_amount >= 0, "Invalid Min Token Swap Amount");
        swapThreshold = _amount;
    }

    function setCooldownWhitelist(
        address _address,
        bool _whitelist
    ) public onlyOwner {
        cooldownWhitelist[_address] = _whitelist;
    }

    function setPreExemption(address _address, bool _exempt) public onlyOwner {
        preExemption[_address] = _exempt;
    }

    function setMaxWalletExempt(
        address _address,
        bool _exempt
    ) public onlyOwner {
        maxWalletExempt[_address] = _exempt;
    }

    function removeAllLimits() external onlyOwner {
        limitsRemoved = true;
    }
}