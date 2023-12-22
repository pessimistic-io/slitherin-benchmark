// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8;

import {SafeCastLib} from "./SafeCastLib.sol";
import {Math} from "./Math.sol";

contract RebasingERC20 {
    using SafeCastLib for uint256;

    uint256 internal constant MAX_INCREASE = 110_000_000;
    uint256 internal constant MAX_DECREASE = 90_000_000;
    uint256 internal constant CHANGE_PRECISION = 100_000_000;
    uint256 internal constant MIN_DURATION = 1 hours;
    
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    struct Rebase {
        uint128 totalShares;
        uint128 totalSupply;
        uint32 change;
        uint32 startTime;
        uint32 endTime;
    }

    Rebase public rebase = Rebase({
        totalShares: 0,
        totalSupply: 0,
        change: uint32(CHANGE_PRECISION),
        startTime: 0,
        endTime: 0
    });

    /// @dev Instead of keeping track of user balances, we keep track of the user's share of the total supply.
    mapping(address => uint256) internal _shares;
    /// @dev Allowances are nominated in token amounts, not token shares.
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event SetRebase(uint32 change, uint32 startTime, uint32 endTime);

    error InvalidTimeFrame();
    error InvalidRebase();

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return rebase.totalSupply * rebaseProgress() / CHANGE_PRECISION;
    }

    function rebaseProgress() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime <= rebase.startTime) {
            return CHANGE_PRECISION;
        } else if (currentTime <= rebase.endTime) {
            return Math.interpolate(CHANGE_PRECISION, rebase.change, currentTime - rebase.startTime, rebase.endTime - rebase.startTime);
        } else {
            return rebase.change;
        }
    }

    function totalShares() public view returns (uint256) {
        return rebase.totalShares;
    }

    function getSharesForTokenAmount(uint256 amount) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return amount;
        return amount * totalShares() / _totalSupply;
    }

    function getTokenAmountForShares(uint256 shares) public view returns (uint256) {
        uint256 _totalShares = totalShares();
        if (_totalShares == 0) return shares;
        return shares * totalSupply() / _totalShares;
    }

    function balanceOf(address account) public view returns (uint256) {
        return getTokenAmountForShares(_shares[account]);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferShares(address to, uint256 shares) public returns (bool) {
        _shares[msg.sender] -= shares;
        unchecked {
            _shares[to] += shares;
        }
        emit Transfer(msg.sender, to, getTokenAmountForShares(shares));
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _decreaseAllowance(from, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _decreaseAllowance(address from, uint256 amount) internal {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        uint256 shares = getSharesForTokenAmount(amount);
        _shares[from] -= shares;
        unchecked {
            _shares[to] += shares;
        }
        emit Transfer(from, to, amount);
    }

    function _setRebase(uint32 change, uint32 startTime, uint32 endTime) internal {
        if (startTime < block.timestamp || endTime - startTime < MIN_DURATION) {
            revert InvalidTimeFrame();
        }
        uint256 _totalSupply = totalSupply();
        if (change > MAX_INCREASE || change < MAX_DECREASE || _totalSupply * change / CHANGE_PRECISION > type(uint128).max) {
            revert InvalidRebase();
        }
        rebase.totalSupply = _totalSupply.safeCastTo128();
        rebase.change = change;
        rebase.startTime = startTime;
        rebase.endTime = endTime;
        emit SetRebase(change, startTime, endTime);
    }

    function _mint(address to, uint256 amount) internal {
        uint256 shares = getSharesForTokenAmount(amount);
        rebase.totalShares += shares.safeCastTo128();
        // We calculate what the change in rebase.totalSupply should be, so that totalSupply() returns the correct value.
        uint256 retrospectiveSupplyIncrease = amount * CHANGE_PRECISION / rebaseProgress();
        rebase.totalSupply += retrospectiveSupplyIncrease.safeCastTo128();
        unchecked {
            _shares[to] += shares;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint128 shares = getSharesForTokenAmount(amount).safeCastTo128();
        rebase.totalShares -= shares;
        uint256 retrospectiveSupplyDecrease = amount * CHANGE_PRECISION / rebaseProgress();
        rebase.totalSupply -= retrospectiveSupplyDecrease.safeCastTo128();
        _shares[from] -= shares;
        emit Transfer(from, address(0), amount);
    }
}

