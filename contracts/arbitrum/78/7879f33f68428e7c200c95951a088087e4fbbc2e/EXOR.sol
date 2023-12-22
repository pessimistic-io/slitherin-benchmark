// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./SafeMath.sol";
import "./Operator.sol";

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

contract Rebaser {
    address public rebaser;

    constructor() public {
        rebaser = msg.sender;
    }

    modifier onlyRebaser {
        require(msg.sender == rebaser, "not rebaser");
        _;
    }

    function transferRebaser(address _newRebaser) public onlyRebaser {
        rebaser = _newRebaser;
    }
}

interface IPair {
    function sync() external;
}

contract EXOR is Context, IERC20, Operator, Rebaser {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public rebaseFactor = 1000;
    uint256 public constant DENOMINATOR = 1000;

    mapping (address => bool) public isExcluded;
    address[] public excluded;
    address[] public pairs;

    constructor () public {
        _name = "Exor";
        _symbol = "EXOR";
        _decimals = 18;
        _balances[msg.sender] = 20 ether * DENOMINATOR;
        _totalSupply = 20 ether;
        emit Transfer(address(0), msg.sender, 20 ether);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        uint256 excludedSupply = 0;
        for (uint256 i = 0; i < excluded.length; i ++) {
            excludedSupply += _balances[excluded[i]];
        }
        return _totalSupply.sub(excludedSupply).mul(rebaseFactor).div(DENOMINATOR).add(excludedSupply);
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account].mul(rebaseFactor).div(DENOMINATOR * DENOMINATOR);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 scaledAmount = amount.mul(DENOMINATOR);
        uint256 scaledBalance;
        if (!isExcluded[sender]) {
            scaledBalance = _balances[sender].mul(rebaseFactor).div(DENOMINATOR);
        } else {
            scaledBalance = _balances[sender];
        }
        require(scaledBalance >= scaledAmount, "ERC20: transfer amount exceeds balance");

        if (!isExcluded[sender]) {
            _balances[sender] = _balances[sender].sub(scaledAmount.mul(DENOMINATOR).div(rebaseFactor));
        } else {
            _balances[sender] = _balances[sender].sub(scaledAmount);
        }
        if (!isExcluded[recipient]) {
            _balances[recipient] = _balances[recipient].add(scaledAmount.mul(DENOMINATOR).div(rebaseFactor));
        } else {
            _balances[recipient] = _balances[recipient].add(scaledAmount);
        }

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        uint256 scaledAmount = amount.mul(DENOMINATOR);
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(scaledAmount);
        emit Transfer(address(0), account, amount);
    }

    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 scaledAmount = amount.mul(DENOMINATOR);
        _balances[account] = _balances[account].sub(scaledAmount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOperator {
        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount, "ERC20: burn amount exceeds allowance"));
        _burn(account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }

    function excludeRebase(address _a) external onlyRebaser {
        isExcluded[_a] = true;
        for (uint256 i = 0; i < excluded.length; i ++) {
            require(excluded[i] != _a, "already excluded");
        }
        excluded.push(_a);
        _balances[_a] = _balances[_a].mul(rebaseFactor).div(DENOMINATOR);
    }

    function includeRebase(address _a) external onlyRebaser {
        require(isExcluded[_a], "not excluded");
        isExcluded[_a] = false;
        for (uint256 i = 0; i < excluded.length; i ++) {
            if (excluded[i] == _a) {
                excluded[i] = excluded[excluded.length - 1];
                excluded.pop();
                _balances[_a] = _balances[_a].mul(DENOMINATOR).div(rebaseFactor);
                return;
            }
        }
    }

    function rebase(uint256 _factor) external onlyRebaser {
        require(_factor > DENOMINATOR, "rebase too low");
        require(_factor < DENOMINATOR.mul(20), "rebase too high");
        rebaseFactor = _factor;
        for (uint256 i = 0; i < pairs.length; i ++) {
            IPair(pairs[i]).sync();
        }
    }

    function addPair(address _p) external onlyRebaser {
        for (uint256 i = 0; i < pairs.length; i ++) {
            require(pairs[i] != _p, "already added");
        }
        pairs.push(_p);
    }

    function removePair(address _p) external onlyRebaser {
        for (uint256 i = 0; i < pairs.length; i ++) {
            if (pairs[i] == _p) {
                pairs[i] = pairs[pairs.length - 1];
                pairs.pop();
                return;
            }
        }
    }
}

