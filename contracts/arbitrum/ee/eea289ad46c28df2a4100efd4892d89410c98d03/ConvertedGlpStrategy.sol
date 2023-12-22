// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { IOracleMiddleware } from "./IOracleMiddleware.sol";
import { IVaultStorage } from "./IVaultStorage.sol";
import { IGmxRewardRouterV2 } from "./IGmxRewardRouterV2.sol";

import { IGmxGlpManager } from "./IGmxGlpManager.sol";
import { IGmxRewardTracker } from "./IGmxRewardTracker.sol";

import { IConvertedGlpStrategy } from "./IConvertedGlpStrategy.sol";

contract ConvertedGlpStrategy is OwnableUpgradeable, IConvertedGlpStrategy {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  error ConvertedGlpStrategy_OnlyWhitelisted();

  IERC20Upgradeable public sglp;

  IGmxRewardRouterV2 public rewardRouter;
  IVaultStorage public vaultStorage;

  mapping(address => bool) public whitelistExecutors;
  event SetWhitelistExecutor(address indexed _account, bool _active);

  /**
   * Modifiers
   */
  modifier onlyWhitelist() {
    if (!whitelistExecutors[msg.sender]) {
      revert ConvertedGlpStrategy_OnlyWhitelisted();
    }
    _;
  }

  function initialize(
    IERC20Upgradeable _sglp,
    IGmxRewardRouterV2 _rewardRouter,
    IVaultStorage _vaultStorage
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    sglp = _sglp;
    rewardRouter = _rewardRouter;
    vaultStorage = _vaultStorage;
  }

  function setWhiteListExecutor(address _executor, bool _active) external onlyOwner {
    whitelistExecutors[_executor] = _active;
    emit SetWhitelistExecutor(_executor, _active);
  }

  function execute(
    address _tokenOut,
    uint256 _amount,
    uint256 _minAmountOut
  ) external onlyWhitelist returns (uint256 _amountOut) {
    // 1. Build calldata.
    bytes memory _callData = abi.encodeWithSelector(
      IGmxRewardRouterV2.unstakeAndRedeemGlp.selector,
      _tokenOut,
      _amount,
      _minAmountOut,
      address(this)
    );

    // 2. withdraw sglp from GMX
    bytes memory _cookResult = vaultStorage.cook(address(sglp), address(rewardRouter), _callData);
    _amountOut = abi.decode(_cookResult, (uint256));

    // 3. Transfer token to vaultStorage
    IERC20Upgradeable(_tokenOut).safeTransfer(address(vaultStorage), _amountOut);
    vaultStorage.pullToken(_tokenOut);

    return _amountOut;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

