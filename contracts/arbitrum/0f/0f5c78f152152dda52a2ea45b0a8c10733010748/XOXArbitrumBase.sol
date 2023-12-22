// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Context.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./IKyberRouter.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
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
contract XOXArbitrumBase is Context, IERC20, IERC20Metadata, Ownable {
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    address private _operator; // wallet operator
    address payable private _feeWallet;

    uint256 private _taxFee = 10;
    uint256 private _baseFee = 100;
    uint256 private _startTrading;
    uint256 private _maxTotalSupply = 180000000 ether;

    // State of swap and liquify
    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;

    mapping(uint256 => mapping(bytes32 => bool)) public checkIsMinted;

    mapping(address => bool) private _listFeePair; // list address other pair

    address[] private _path; // Swap path
    address[] private _poolsPath; // Swap path

    IKyberRouter private _kyberRouter;

    // Prevent processing while already processing!
    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address operator_,
        address feeWallet_,
        address kyberRouter_,
        uint256 startTrading_
    ) {
        require(operator_.isContract(), "ERC20: operator is smartcontract");
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _operator = operator_;
        _feeWallet = payable(feeWallet_);
        _kyberRouter = IKyberRouter(kyberRouter_);
        _startTrading = startTrading_;
    }

    /**
     * @dev add new pair to feePair
     */
    function addFeePair(address pair_, bool status_) external {
        require(msg.sender == _operator, "not permission");
        require(pair_.isContract(), "pair wrong");
        _listFeePair[pair_] = status_;
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
        return _decimals;
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
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
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
        bool isOwner = false;
        if (_listFeePair[to] || _listFeePair[from]) {
            if (to != owner() && from != owner()) {
                require(
                    _startTrading < block.timestamp,
                    "XOX: not open for buy"
                );
            } else {
                isOwner = true;
            }
        }
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        if (
            _listFeePair[to] &&
            swapAndLiquifyEnabled &&
            !inSwapAndLiquify &&
            !isOwner
        ) {
            uint256 feeAmount = (amount * _taxFee) / _baseFee;
            if (feeAmount > 0) {
                amount -= feeAmount;
                _balances[address(this)] = _balances[address(this)] + feeAmount;
                emit Transfer(from, address(this), feeAmount);
                swapAndLiquify(feeAmount);
            }
        }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    /*

    PROCESSING FEES

    Fees are added to the contract as tokens, these functions exchange the tokens for BNB and send to the wallet.
    One wallet is used for ALL fees. This includes liquidity,buyback & burn, marketing, development costs etc.

    */

    // Processing tokens from contract
    function swapAndLiquify(uint256 _feeAmount) private lockTheSwap {
        if (_path[_path.length - 1] == _kyberRouter.weth()) {
            swapTokensForNative(_feeAmount);
        } else {
            swapTokensForTokens(_feeAmount);
        }
    }

    // Swapping tokens for native using DEXs (Uniswap, Pancake,...)
    function swapTokensForNative(uint256 tokenAmount) private {
        _approve(address(this), address(_kyberRouter), tokenAmount);
        _kyberRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            _poolsPath,
            _path,
            _feeWallet,
            block.timestamp
        );
    }

    // Swapping tokens for tokens using DEXs (Uniswap, Pancake)
    function swapTokensForTokens(uint256 tokenAmount) private {
        _approve(address(this), address(_kyberRouter), tokenAmount);
        _kyberRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            _poolsPath,
            _path,
            _feeWallet,
            block.timestamp
        );
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
    function _mint(
        address account,
        uint256 amount,
        bytes32 txSource,
        uint256 chainIdSource
    ) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        require(
            !checkIsMinted[chainIdSource][txSource],
            "XOX: Processed before"
        );
        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        require(
            _totalSupply <= _maxTotalSupply,
            "ERC20: can not mint over 180 million token"
        );
        _balances[account] += amount;
        checkIsMinted[chainIdSource][txSource] = true;
        emit Transfer(address(0), account, amount);
        emit MintBridge(account, amount, chainIdSource, txSource);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event MintBridge(
        address indexed account,
        uint256 value,
        uint256 chainIdSource,
        bytes32 txSource
    );

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
        }
        _totalSupply -= amount;

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

    /**
     * @dev Change feeTax when sell XOX on Other Dex (Pancake, Uni,...)
     */
    function _changeTaxFee(uint256 taxFee) internal virtual {
        require(taxFee <= 15, "ERC20 XOX: fee cannot be set greater 15");
        _taxFee = taxFee;
        emit ChangeTaxFee(taxFee);
    }

    // Called when admin change tax fee
    event ChangeTaxFee(uint256 taxFee);

    /**
     * @dev Change wallet address that take fee when sell XOX on Other Dex (Pancake, Uni,...)
     */
    function _changeFeeWallet(address feeWallet) internal virtual {
        require(
            feeWallet != address(0),
            "ERC20 XOX: fee wallet cannot be zero address"
        );
        _feeWallet = payable(feeWallet);
        emit ChangeFeeWallet(feeWallet);
    }

    // Called when admin change fee wallet
    event ChangeFeeWallet(address feeWallet);

    /**
     * @dev Change path that swap router will process when execute swap (Pancake, Uni,...)
     */
    function _changeSwapPath(
        address[] memory path_,
        address[] memory poolsPath_
    ) internal virtual {
        _path = path_;
        _poolsPath = poolsPath_;
    }

    // This will set the number of transactions required before the 'swapAndLiquify' function triggers

    // Toggle on and off to auto swapping sold XOX to stable coin
    function _setSwapAndLiquifyEnabled(
        bool swapAndLiquifyEnabled_
    ) internal virtual {
        swapAndLiquifyEnabled = swapAndLiquifyEnabled_;
        emit SwapAndLiquifyEnabledUpdated(swapAndLiquifyEnabled_);
    }

    // Called when admin toggle the swap and liquify on or off
    event SwapAndLiquifyEnabledUpdated(bool swapAndLiquifyEnabled_);

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {BurnBridge} event
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burnBridge(
        address account,
        address to,
        uint256 amount,
        uint256 chainId
    ) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        emit BurnBridge(account, to, amount, chainId);
    }

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event BurnBridge(
        address indexed from,
        address indexed to,
        uint256 value,
        uint256 chainIdDest
    );

    function transferOperator(address operator_) external onlyOwner {
        require(
            operator_.isContract(),
            "XOXToken: operator is a smartcontract"
        );
        _operator = operator_;
        emit OperatorshipTransferred(_operator, operator_);
    }

    event OperatorshipTransferred(
        address indexed previousOperator,
        address indexed newOperator
    );

    /**
     * @dev Change routerSwap
     */
    function changeRouterSwap(
        address router,
        address[] memory path,
        address[] memory poolsPath
    ) external onlyOwner {
        require(router.isContract(), "ERC20 XOX: Router is a smartcontract");
        _kyberRouter = IKyberRouter(router);
        _path = path;
        _poolsPath = poolsPath;
        emit ChangeFeeWallet(router);
    }

    // Called when admin change fee wallet
    event ChangeRouterSwap(address router);

    /**
     * @dev Change start trading time that users can buy/sell when this time is over
     */
    function changeStartTrading(uint256 time) external onlyOwner {
        _startTrading = time;
    }
}

