// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPirexGmxDepositRouter {
    /**
     * @notice Deposit GMX for pxGMX
     * @dev Try to swap GMX for WETH on UniswapV3, then swap WETH for pxGMX on Camelot
     *     If unsuccessful deposit GMX for pxGMX on PirexGmx
     *  @param  amount         uint256  GMX amount
     *  @param  receiver       address  pxGMX receiver
     *  @return amountOut      uint256  pxGMX minted for the receiver
     *  @return feeAmount      uint256  pxGMX distributed as fees
     */
    function depositGmx(uint256 amount, address receiver)
        external
        returns (uint256 amountOut, uint256 feeAmount);
}

