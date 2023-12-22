//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ITwapStrategyFactory.sol";
import "./IOneInchRouter.sol";
import "./ITwapStrategyManager.sol";
import "./IAlgebraPool.sol";

interface ITwapStrategyBase {
    struct Tick {
        int24 tickLower;
        int24 tickUpper;
    }

    event ClaimFee(uint256 managerFee, uint256 protocolFee);

    function onHold() external view returns (bool);

    function accManagementFeeShares() external view returns (uint256);

    function factory() external view returns (ITwapStrategyFactory);

    function pool() external view returns (IAlgebraPool);

    function manager() external view returns (ITwapStrategyManager);

    function useTwap(uint256 index) external view returns (bool);

    function claimFee() external;
}
