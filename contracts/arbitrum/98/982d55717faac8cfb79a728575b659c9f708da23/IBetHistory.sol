// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IMarketHistory.sol";
import "./ILockBox.sol";
import "./IRewardHandler.sol";
import "./IBetHelper.sol";
import "./ITokenTransferProxy.sol";
import "./BetData.sol";

interface IBetHistory {
    function setLiquidityPool(IBetHelper) external;
    function setBetLockBox(ILockBox) external;
    function setMarketHistory(IMarketHistory) external;
    function setTokenTransferProxy(ITokenTransferProxy) external;
    function setFeeHandler1(IRewardHandler) external;
    function setFeeHandler2(IRewardHandler) external;
    function setFees(uint8, uint8, uint8) external;
    function createBet(BetData.Bet calldata) external;
    function settleBet(bytes32)
        external
        returns (BetData.BetSettleResult memory);
    function cancelBet(bytes32)
        external
        returns (BetData.BetSettleResult memory);
    function getBetExists(bytes32) external view returns(bool);
    function allBets(bytes32)
        external
        view
        returns (bytes32, address, uint256, uint256, uint256, address);
    function unsettledPots(bytes32) external view returns (uint256);
    function marketBetted(bytes32, address) external view returns (uint256);
    function marketMatched(bytes32, address) external view returns (uint256);
}

