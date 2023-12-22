// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBetHelper.sol";
import "./IBetHistory.sol";
import "./IMarketHistory.sol";
import "./IBonusDistribution.sol";
import "./ITokenTransferProxy.sol";

interface IBookieMain {
    function setLiquidityPool(IBetHelper) external;
    function setBetHistory(IBetHistory) external;
    function setMarketHistory(IMarketHistory) external;
    function setBonusDistribution(IBonusDistribution) external;
    function setTokenTransferProxy(ITokenTransferProxy) external;












    function makeBet(
        address,
        uint256,
        uint256,
        uint256,
        bytes32,
        bytes calldata
    ) external;
    function settleBet(bytes32) external;
    function cancelBetAsAdmin(bytes32) external;
}

