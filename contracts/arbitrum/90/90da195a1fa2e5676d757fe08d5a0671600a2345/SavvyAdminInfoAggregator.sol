// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./Ownable2StepUpgradeable.sol";

import "./ISavvyAdminInfoAggregator.sol";
import "./IInfoAggregator.sol";
import "./ISavvyPositionManager.sol";
import "./IYieldStrategyManager.sol";
import "./IERC20Metadata.sol";

contract SavvyAdminInfoAggregator is Ownable2StepUpgradeable, ISavvyAdminInfoAggregator
{
    IInfoAggregator public infoAggregator;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IInfoAggregator infoAggregator_
    ) public initializer {
        Checker.checkArgument(
            address(infoAggregator_) != address(0),
            "zero infoAggregator address"
        );
        infoAggregator = infoAggregator_;

        __Ownable2Step_init();
    }

    /// @inheritdoc ISavvyAdminInfoAggregator
    function setInfoAggregator(
        address infoAggregator_
    ) external onlyOwner {
        Checker.checkArgument(
            address(infoAggregator_) != address(0),
            "zero infoAggregator address"
        );
        infoAggregator = IInfoAggregator(infoAggregator_);
    }

    /// @inheritdoc ISavvyAdminInfoAggregator
    function getYieldStrategyMetrics() external view returns (YieldStrategyMetrics[] memory) {
      uint256 yieldTokenLength;
      
      address[] memory savvyPositionManagers = infoAggregator.getSavvyPositionManagers();
      uint256 spmLength = savvyPositionManagers.length;
      for (uint256 i; i < spmLength; ++i) {
        yieldTokenLength += ISavvyPositionManager(savvyPositionManagers[i]).yieldStrategyManager().getSupportedYieldTokens().length;
      }

      YieldStrategyMetrics[] memory metrics = new YieldStrategyMetrics[](yieldTokenLength);

      uint256 metricIdx = 0;
      for (uint256 i; i < spmLength; ++i) {
        address spm = savvyPositionManagers[i];
        IYieldStrategyManager ysm = IYieldStrategyManager(ISavvyPositionManager(spm).yieldStrategyManager());
        address[] memory yieldTokens = ysm.getSupportedYieldTokens();
        yieldTokenLength = yieldTokens.length;
        for (uint256 j; j < yieldTokenLength; ++j) {
          address yieldToken = yieldTokens[j];
          IYieldStrategyManager.YieldTokenParams memory params = ysm.getYieldTokenParams(yieldToken);
          metrics[metricIdx] = YieldStrategyMetrics(
            spm,
            yieldToken,
            params.activeBalance,
            params.baseToken,
            IERC20Metadata(params.baseToken).decimals(),
            params.expectedValue,
            params.maximumExpectedValue,
            params.enabled,
            params.adapter
          );
          ++metricIdx; 
        }
      }

      return metrics;
    }
}
