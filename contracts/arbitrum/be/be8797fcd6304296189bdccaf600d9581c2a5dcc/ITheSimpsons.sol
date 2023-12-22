pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

abstract contract ITheSimpsons {
    /**
     * @notice Event emitted when tokens are rebased
     */
    event Rebase(
        uint256 epoch,
        uint256 prevEggssScalingFactor,
        uint256 newEggssScalingFactor
    );

    /* - Extra Events - */
    /**
     * @notice Tokens minted event
     */
    event Mint(address to, uint256 amount);

    /**
     * @notice Tokens burned event
     */
    event Burn(address from, uint256 amount);

    event NewFeesChangedEvent(uint buyTaxFee, uint sellTaxFee);
    event FeeDistributedEvent(address beneficiary, uint fee);
    event MinterChangedEvent(address newMinter);
    event MintableChangedEvent(bool mintable);

}
