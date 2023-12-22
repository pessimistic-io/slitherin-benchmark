// SPDX-License-Identifier: BUSL-1.1
// TAZZ Contracts (last updated v0.2.0)

pragma solidity 0.8.17;

import {IGuild} from "./IGuild.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {INotionalERC20} from "./INotionalERC20.sol";
import {MintableUpgradeableERC20} from "./MintableUpgradeableERC20.sol";
import {Errors} from "./Errors.sol";
import {SafeMath} from "./SafeMath.sol";

import "./console.sol";

/**
 * @dev Implementation of notional rebase functionality.
 * @author Tazz Labs
 * Forms the basis of a notional ERC20 token, where the ERC20 interface is non-rebasing,
 * (ie, the quantities tracked by the ERC20 token are normalized), and here we create
 * functions that access the full 'rebased' quantities as a 'Notional' amount
 *
 **/
contract NotionalERC20 is MintableUpgradeableERC20, INotionalERC20 {
    using WadRayMath for uint256;
    using SafeMath for uint256;

    //Scale factor (used for Notional calculation)
    uint256 internal _nFactor;

    // Reserved storage space to allow for layout changes in the future.
    uint256[10] private ______gap;

    /**
     * @dev Constructor.
     * @dev Initializes rebase factor to 1 (in RAY)
     * @param guild The reference to the main Guild contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals The number of decimals of the token
     */
    constructor(
        IGuild guild,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) MintableUpgradeableERC20(guild, name, symbol, decimals) {
        _nFactor = WadRayMath.RAY;
    }

    /**
     * @dev gets the Notional factor
     */
    function getNotionalFactor() public view virtual override returns (uint256) {
        return _nFactor;
    }

    /**
     * @dev updates the Notional factor through a multiplicative variable
     * @param multFactor  multiplicative factor
     * @return updatedFactor returns the new updated Notional factor
     */
    function _updateNotionalFactor(uint256 multFactor) internal virtual returns (uint256 updatedFactor) {
        _nFactor = _nFactor.rayMul(multFactor);
        emit UpdateNotionalFactor(_nFactor);
        return _nFactor;
    }

    /**
     * @dev convert from Base (normalized) amount to a Notional amount
     */
    function baseToNotional(uint256 amount) public view virtual returns (uint256) {
        return _baseToNotional(amount);
    }

    /**
     * @dev convert from Notional amount to Base (normalized) amount
     */
    function notionalToBase(uint256 amount) public view virtual returns (uint256) {
        return _notionalToBase(amount);
    }

    /**
     * @dev Returns the amount of tokens in existence, expressed in Notional units
     */
    function totalNotionalSupply() public view virtual override returns (uint256) {
        return _baseToNotional(_totalSupply);
    }

    /**
     * @dev Returns the amount of tokens owned by `account`, expressed in Notional units
     */
    function balanceNotionalOf(address account) public view virtual override returns (uint256) {
        return _baseToNotional(_balances[account]);
    }

    /**
     * @dev convert from Base (normalized) amount to a Notional amount
     */
    function _baseToNotional(uint256 amount) internal view virtual returns (uint256) {
        return amount.rayMul(_nFactor);
    }

    /**
     * @dev convert from Notional amount to Base (normalized) amount
     */
    function _notionalToBase(uint256 amount) internal view virtual returns (uint256) {
        return amount.rayDiv(_nFactor);
    }
}

