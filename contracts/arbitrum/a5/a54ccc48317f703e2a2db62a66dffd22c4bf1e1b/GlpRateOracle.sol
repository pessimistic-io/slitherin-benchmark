/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

import {IRateOracle, IERC165} from "./IRateOracle.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IVault} from "./IVault.sol";
import {IRewardRouter} from "./IRewardRouter.sol";
import {IGlpManager} from "./IGlpManager.sol";
import { UD60x18, ud, mulDiv } from "./UD60x18.sol";
import {IERC20} from "./IERC20.sol";

/// @notice GP stands for GLP PRECISION (1e30)
contract GlpRateOracle is IRateOracle {
  error InexistentGlpRewardRouter();
  error NonMatchingUnderlyings();
  error FailedGlpPriceFetch();
  error UnorderedRewardIndex();

  address public immutable underlying;
  
  uint256 public constant GLP_PRECISION = 1e30;
  uint256 public constant MIN_SECONDS_BETWEEN_STATE_UPDATES = 12 * 60 * 60; // 12 hours

  struct GlpContracts {
    IRewardRouter rewardRouter;
    IGlpManager glpManager;
    IRewardTracker rewardTracker;
    IVault vault;
    IERC20 glp;
  }
  GlpContracts public glpContracts;

  struct State {
    UD60x18 lastIndex;
    uint256 lastEthPriceInGlpGP;
    uint256 lastCumulativeRewardPerTokenGP;
    uint256 earliestStateUpdate;
  }
  State public state;

  constructor(IRewardRouter _rewardRouter, address _underlying) {
    if (address(_rewardRouter) == address(0)) {
      revert InexistentGlpRewardRouter();
    }

    glpContracts.rewardRouter = _rewardRouter;
    underlying = _underlying;

    glpContracts.glpManager = IGlpManager(_rewardRouter.glpManager());
    glpContracts.rewardTracker = IRewardTracker(_rewardRouter.feeGlpTracker());
    glpContracts.vault = glpContracts.glpManager.vault();
    glpContracts.glp = IERC20(glpContracts.glpManager.glp());
    if (glpContracts.rewardTracker.rewardToken() != address(underlying)) {
      revert NonMatchingUnderlyings();
    }

    updateState();
  }

  /// @inheritdoc IRateOracle
  function hasState() external override pure returns (bool) {
    return true;
  }

  /// @inheritdoc IRateOracle
  function earliestStateUpdate() external override view returns (uint256) {
    return state.earliestStateUpdate;
  }
  
  /// @inheritdoc IRateOracle
  function updateState() public override {
    if (block.timestamp < state.earliestStateUpdate) {
      revert StateUpdateTooEarly();
    }

    _updateState();
    
    state.earliestStateUpdate = block.timestamp + MIN_SECONDS_BETWEEN_STATE_UPDATES;
  }

  function _updateState() internal {
    // average over min & max price of GLP price feeds
    // see https://github.com/gmx-io/gmx-contracts/blob/master/contracts/core/VaultPriceFeed.sol
    uint256 ethPriceMinInUsdGP = glpContracts.vault.getMinPrice(address(underlying));
    uint256 ethPriceMaxInUsdGP = glpContracts.vault.getMaxPrice(address(underlying));

    UD60x18 glpSupply = ud(glpContracts.glp.totalSupply());
    
    uint256 glpPriceMinInUsdGP = ud(glpContracts.glpManager.getAum(false)).div(glpSupply).unwrap();
    uint256 glpPriceMaxInUsdGP = ud(glpContracts.glpManager.getAum(true)).div(glpSupply).unwrap();

    if (
      ethPriceMinInUsdGP + ethPriceMaxInUsdGP == 0 || 
      glpPriceMinInUsdGP + glpPriceMaxInUsdGP == 0
    ) {
      revert FailedGlpPriceFetch();
    }

    uint256 ethPriceInGlpGP = mulDiv(
      ethPriceMinInUsdGP + ethPriceMaxInUsdGP, 
      GLP_PRECISION, 
      glpPriceMinInUsdGP + glpPriceMaxInUsdGP
    );

    uint256 currentRewardGP = glpContracts.rewardTracker.cumulativeRewardPerToken();
    if (currentRewardGP < state.lastCumulativeRewardPerTokenGP) {
      revert UnorderedRewardIndex();
    }

    state.lastIndex = getCurrentIndex();
    state.lastEthPriceInGlpGP = ethPriceInGlpGP;
    state.lastCumulativeRewardPerTokenGP = currentRewardGP;
  }

  /// @inheritdoc IRateOracle
  function getCurrentIndex() public view override returns (UD60x18 liquidityIndex) {
    // calculate rate increase since last update
    uint256 cumulativeRewardPerTokenGP = glpContracts.rewardTracker.cumulativeRewardPerToken();
    if (cumulativeRewardPerTokenGP < state.lastCumulativeRewardPerTokenGP) {
        revert UnorderedRewardIndex();
    }

    uint256 rewardsRateSinceLastUpdateGP = mulDiv(
      cumulativeRewardPerTokenGP - state.lastCumulativeRewardPerTokenGP,
      state.lastEthPriceInGlpGP,
      GLP_PRECISION
    );

    UD60x18 rewardsRateSinceLastUpdate = ud(rewardsRateSinceLastUpdateGP).div(ud(GLP_PRECISION));

    // compute index using rate increase & last index
    liquidityIndex = state.lastIndex.add(rewardsRateSinceLastUpdate);
  }

  /**
    * @inheritdoc IERC165
    */
  function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
    return interfaceId == type(IRateOracle).interfaceId || interfaceId == this.supportsInterface.selector;
  }
}

