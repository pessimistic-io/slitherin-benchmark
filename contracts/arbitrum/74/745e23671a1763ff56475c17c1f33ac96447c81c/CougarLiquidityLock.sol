// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Ownable.sol";
import "./SafeBEP20.sol";

/**
 * @dev CougarLiquidityLock contract locks the initial liquidity for a year (LP tokens).
 * Unlock time stamp: 1678838400.
 * 
 * Q: Why don't we just burn the liquidity or lock the liquidity on other platforms?
 * A: If there is an upgrade of CougarSwap AMM, we can migrate the liquidity to our new version exchange.
 *
 */

contract CougarLiquidityLock is Ownable {
    using SafeBEP20 for IBEP20;

    uint256 public constant unlockTimeStamp = 1678838400;

    event Unlocked(address indexed token, address indexed recipient, uint256 amount);

    function unlock(IBEP20 _token, address _recipient) public onlyOwner {
        require(_recipient != address(0), "CougarLiquidityLock::unlock: ZERO address.");

        require(
            block.timestamp >= unlockTimeStamp,
            "cannot unlock"
        );

        uint256 amount = _token.balanceOf(address(this));
        _token.safeTransfer(_recipient, amount);
        emit Unlocked(address(_token), _recipient, amount);
    }
}
