// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IDistToken.sol";
import "./ILockBox.sol";
import "./IRewardHandler.sol";
import "./ITokenTransferProxy.sol";

interface ILiquidityBox {
    function setTokenTransferProxy(ITokenTransferProxy) external;
    function setFeeHandler1(IRewardHandler) external;
    function setFeeHandler2(IRewardHandler) external;
    function setRewardHandler1(IRewardHandler) external;
    function setRewardHandler2(IRewardHandler) external;
    function setFees(uint8, uint8, uint8) external;
    function getTokenBalance(address) external view returns (uint256);
    function getFullBalance(address) external view returns (uint256);
    function getDistTokenBalanceFromToken(address, address)
        external
        view
        returns (uint256);
    function getMatchingTokenAmount(address, uint256)
        external
        view
        returns (uint256);
    function getMatchingDistTokenAmount(address, uint256)
        external
        view
        returns (uint256);
}

