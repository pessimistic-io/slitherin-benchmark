// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {SafeCastLib} from "./SafeCastLib.sol";
import {Math} from "./Math.sol";
import {RebaseConstants as RC} from "./RebaseConstants.sol";
import {Base} from "./token_Base.sol";

abstract contract RebasingToken is Base {
    using SafeCastLib for uint256;

    struct Rebase {
        uint128 totalShares;
        uint128 lastTotalSupply;
        uint32 change;
        uint32 startTime;
        uint32 endTime;
    }

    event SetRebase(uint32 change, uint32 startTime, uint32 endTime);

    error InvalidTimeFrame();
    error InvalidRebase();

    Rebase internal _rebase =
        Rebase({totalShares: 0, lastTotalSupply: 0, change: uint32(RC.CHANGE_PRECISION), startTime: 0, endTime: 0});

    mapping(address => uint256) public sharesOf;

    constructor(string memory name, string memory symbol, uint8 decimals) Base(name, symbol, decimals) {}

    function setRebase(uint32 change, uint32 startTime, uint32 endTime) external virtual;

    function getRebase() external view returns (Rebase memory) {
        return _rebase;
    }

    function totalSupply() public view override returns (uint256) {
        return _rebase.lastTotalSupply * rebaseProgress() / RC.CHANGE_PRECISION;
    }

    function rebaseProgress() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime <= _rebase.startTime) {
            return RC.CHANGE_PRECISION;
        } else if (currentTime <= _rebase.endTime) {
            return Math.interpolate(
                RC.CHANGE_PRECISION,
                _rebase.change,
                currentTime - _rebase.startTime,
                _rebase.endTime - _rebase.startTime
            );
        } else {
            return _rebase.change;
        }
    }

    function totalShares() public view returns (uint256) {
        return _rebase.totalShares;
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

    function balanceOf(address account) public view override returns (uint256) {
        return getTokenAmountForShares(sharesOf[account]);
    }

    function transferShares(address to, uint256 shares) public returns (uint256 amountTransfered) {
        amountTransfered = getTokenAmountForShares(shares);
        sharesOf[msg.sender] -= shares;
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(msg.sender, to, amountTransfered);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        uint256 shares = getSharesForTokenAmount(amount);
        sharesOf[from] -= shares;
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(from, to, amount);
    }

    function _setRebase(uint32 change, uint32 startTime, uint32 endTime) internal {
        if (endTime - startTime < RC.MIN_DURATION) {
            revert InvalidTimeFrame();
        }
        uint256 _totalSupply = totalSupply();
        if (
            change > RC.MAX_INCREASE || change < RC.MAX_DECREASE
                || _totalSupply * change / RC.CHANGE_PRECISION > type(uint128).max
        ) {
            revert InvalidRebase();
        }
        _rebase.lastTotalSupply = _totalSupply.safeCastTo128();
        _rebase.change = change;
        _rebase.startTime = startTime;
        _rebase.endTime = endTime;
        emit SetRebase(change, startTime, endTime);
    }

    function _mint(address to, uint256 amount) internal override returns (uint256 shares) {
        shares = getSharesForTokenAmount(amount);
        _rebase.totalShares += shares.safeCastTo128();
        _rebase.lastTotalSupply += _principalAmount(amount).safeCastTo128();
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal override returns (uint256 shares) {
        shares = getSharesForTokenAmount(amount);
        _rebase.totalShares -= shares.safeCastTo128();
        _rebase.lastTotalSupply -= _principalAmount(amount).safeCastTo128();
        sharesOf[from] -= shares;
        emit Transfer(from, address(0), amount);
    }

    function _principalAmount(uint256 amount) internal view returns (uint256) {
        return amount * RC.CHANGE_PRECISION / rebaseProgress();
    }
}

