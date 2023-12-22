// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import {SafeCastLib} from "./SafeCastLib.sol";
import {Math} from "./Math.sol";
import {RebaseConstants as RC} from "./RebaseConstants.sol";
import {Base, Initializable} from "./token_Base.sol";

/// @title RebasingToken
/// @dev An abstract contract for rebasing token logic, extending Base contract.
/// @custom:oz-upgrades
abstract contract RebasingToken is Initializable, Base {
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

    /// @dev Stores rebase information.
    Rebase internal _rebase;

    /// @notice Account's shares.
    mapping(address => uint256) public sharesOf;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __RebasingToken_init_(string memory name, string memory symbol, uint8 decimals) onlyInitializing public {
        __Base_init_(name, symbol, decimals);
        _rebase = Rebase({totalShares: 0, lastTotalSupply: 0, change: uint32(RC.CHANGE_PRECISION), startTime: 0, endTime: 0});
    }

    /// @notice Gets current rebase settings.
    function getRebase() external view returns (
        uint128 _totalShares,
        uint128 _lastTotalSupply,
        uint32 _change,
        uint32 _startTime,
        uint32 _endTime
    ) {
        return (_rebase.totalShares, _rebase.lastTotalSupply, _rebase.change, _rebase.startTime, _rebase.endTime);
    }

    /// @notice Calculates the total supply of the token, considering the rebase.
    /// @return The total supply.
    function totalSupply() public view override returns (uint256) {
        return _rebase.lastTotalSupply * rebaseProgress() / RC.CHANGE_PRECISION;
    }

    /// @notice Computes the rebase progress based on current time.
    /// @return The relative change so far.
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

    /// @notice Total shares of the token.
    function totalShares() public view returns (uint256) {
        return _rebase.totalShares;
    }

    /// @notice Converts token amount to shares.
    /// @param amount The amount of tokens.
    /// @return The equivalent shares.
    function getSharesForTokenAmount(uint256 amount) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return amount;
        return amount * totalShares() / _totalSupply;
    }

    /// @notice Converts shares to token amount.
    /// @param shares The number of shares.
    /// @return The equivalent token amount.
    function getTokenAmountForShares(uint256 shares) public view returns (uint256) {
        uint256 _totalShares = totalShares();
        if (_totalShares == 0) return shares;
        return shares * totalSupply() / _totalShares;
    }

    /// @notice Gets the balance of an account considering rebase.
    /// @param account Address of the account.
    /// @return The balance of the account.
    function balanceOf(address account) public view override returns (uint256) {
        return getTokenAmountForShares(sharesOf[account]);
    }

    /// @notice Transfers shares between addresses.
    /// @param to Destination address.
    /// @param shares Number of shares to transfer.
    /// @return amountTransfered The amount of tokens transferred.
    function transferShares(address to, uint256 shares) public returns (uint256 amountTransfered) {
        amountTransfered = getTokenAmountForShares(shares);
        sharesOf[msg.sender] -= shares;
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(msg.sender, to, amountTransfered);
    }

    /// @dev Internal function to handle token transfers.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount to transfer.
    function _transfer(address from, address to, uint256 amount) internal virtual override {
        uint256 shares = getSharesForTokenAmount(amount);
        sharesOf[from] -= shares;
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(from, to, amount);
    }

    /// @dev Internal function to set rebase parameters.
    /// @param change The change rate.
    /// @param startTime The start time of the rebase.
    /// @param endTime The end time of the rebase.
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

    /// @dev Internal function for minting tokens.
    /// @param to The address to mint tokens to.
    /// @param amount The amount to mint.
    /// @return shares The number of shares minted.
    function _mint(address to, uint256 amount) internal override returns (uint256 shares) {
        shares = getSharesForTokenAmount(amount);
        _rebase.totalShares += shares.safeCastTo128();
        _rebase.lastTotalSupply += _principalAmount(amount).safeCastTo128();
        unchecked {
            sharesOf[to] += shares;
        }
        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal function for burning tokens.
    /// @param from The address to burn tokens from.
    /// @param amount The amount to burn.
    /// @return shares The number of shares burned.
    function _burn(address from, uint256 amount) internal override returns (uint256 shares) {
        shares = getSharesForTokenAmount(amount);
        _rebase.totalShares -= shares.safeCastTo128();
        _rebase.lastTotalSupply -= _principalAmount(amount).safeCastTo128();
        sharesOf[from] -= shares;
        emit Transfer(from, address(0), amount);
    }

    /// @dev Calculates the principal amount before rebase adjustment.
    /// @param amount The amount to adjust.
    /// @return The principal amount.
    function _principalAmount(uint256 amount) internal view returns (uint256) {
        return amount * RC.CHANGE_PRECISION / rebaseProgress();
    }
}

