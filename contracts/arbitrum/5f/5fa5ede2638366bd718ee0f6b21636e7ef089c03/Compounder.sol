// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { UniV3LiquidityMining } from "./UniV3LiquidityMining.sol";

import { IStaking } from "./IStaking.sol";
import { TLCStaking } from "./TLCStaking.sol";

contract Compounder is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  error Compounder_InconsistentLength();

  address public dp;
  address public destinationCompoundPool;
  address[] public tokens;
  mapping(address => bool) public isCompoundableTokens;
  address public tlcStaking;
  address public uniV3LiquidityMining;

  event LogAddToken(address token, bool isCompoundToken);
  event LogRemoveToken(address token);
  event LogSetCompoundToken(address token, bool isCompoundToken);
  event LogSetDestinationCompoundPool(
    address oldDestinationCompoundPool_,
    address newDestinationCompoundPool
  );

  function initialize(
    address dp_,
    address destinationCompoundPool_,
    address[] memory tokens_,
    bool[] memory isCompoundTokens_,
    address tlcStaking_,
    address uniV3LiquidityMining_
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    dp = dp_;
    destinationCompoundPool = destinationCompoundPool_;
    addToken(tokens_, isCompoundTokens_);
    tlcStaking = tlcStaking_;
    uniV3LiquidityMining = uniV3LiquidityMining_;
  }

  function addToken(
    address[] memory newTokens,
    bool[] memory newIsCompoundTokens
  ) public onlyOwner {
    uint256 length = newTokens.length;
    if (length != newIsCompoundTokens.length) revert Compounder_InconsistentLength();

    for (uint256 i = 0; i < length; ) {
      tokens.push(newTokens[i]);
      setCompoundToken(tokens[i], newIsCompoundTokens[i]);

      emit LogAddToken(tokens[i], newIsCompoundTokens[i]);
      unchecked {
        ++i;
      }
    }
  }

  function removeToken(address token) external onlyOwner {
    uint256 length = tokens.length;

    for (uint256 i = 0; i < length; ) {
      if (tokens[i] == token) {
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();

        setCompoundToken(token, false);
        emit LogRemoveToken(token);
        break;
      }

      unchecked {
        ++i;
      }
    }
  }

  function setCompoundToken(address token, bool isCompoundToken) public onlyOwner {
    isCompoundableTokens[token] = isCompoundToken;

    if (isCompoundToken)
      IERC20Upgradeable(token).approve(destinationCompoundPool, type(uint256).max);

    emit LogSetCompoundToken(token, isCompoundToken);
  }

  function setDestinationCompoundPool(address _destinationCompoundPool) external onlyOwner {
    emit LogSetDestinationCompoundPool(destinationCompoundPool, _destinationCompoundPool);

    destinationCompoundPool = _destinationCompoundPool;
  }

  function claimAll(
    address[] memory pools,
    address[][] memory rewarders,
    uint256 startEpochTimestamp,
    uint256 noOfEpochs,
    uint256[] calldata tokenIds
  ) external {
    _claimAll(pools, rewarders, startEpochTimestamp, noOfEpochs);
    _claimUniV3(tokenIds);
    _compoundOrTransfer(false);
  }

  function compound(
    address[] memory pools,
    address[][] memory rewarders,
    uint256 startEpochTimestamp,
    uint256 noOfEpochs,
    uint256[] calldata tokenIds
  ) external {
    _claimAll(pools, rewarders, startEpochTimestamp, noOfEpochs);
    _claimUniV3(tokenIds);
    _compoundOrTransfer(true);
  }

  function _compoundOrTransfer(bool isCompound) internal {
    uint256 length = tokens.length;
    for (uint256 i = 0; i < length; ) {
      uint256 amount = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
      if (amount > 0) {
        // always compound dragon point
        if (tokens[i] == dp || (isCompound && isCompoundableTokens[tokens[i]])) {
          IERC20Upgradeable(tokens[i]).approve(destinationCompoundPool, type(uint256).max);
          IStaking(destinationCompoundPool).deposit(msg.sender, tokens[i], amount);
          IERC20Upgradeable(tokens[i]).approve(destinationCompoundPool, 0);
        } else {
          IERC20Upgradeable(tokens[i]).safeTransfer(msg.sender, amount);
        }
      }

      unchecked {
        ++i;
      }
    }
  }

  function _claimAll(
    address[] memory pools,
    address[][] memory rewarders,
    uint256 startEpochTimestamp,
    uint256 noOfEpochs
  ) internal {
    uint256 length = pools.length;
    for (uint256 i = 0; i < length; ) {
      if (tlcStaking == pools[i]) {
        TLCStaking(pools[i]).harvestToCompounder(
          msg.sender,
          startEpochTimestamp,
          noOfEpochs,
          rewarders[i]
        );
      } else {
        IStaking(pools[i]).harvestToCompounder(msg.sender, rewarders[i]);
      }

      unchecked {
        ++i;
      }
    }
  }

  function _claimUniV3(uint256[] memory tokenIds) internal {
    UniV3LiquidityMining pool = UniV3LiquidityMining(uniV3LiquidityMining);
    for (uint256 i = 0; i < tokenIds.length; ) {
      // Unstake LP to update rewards
      pool.unstake(tokenIds[i]);

      // Restake LP in case the current incentive is still active
      (, , , , uint64 endTime) = pool.incentives(pool.activeIncentiveId());
      if (block.timestamp < endTime) pool.stake(tokenIds[i]);

      unchecked {
        ++i;
      }
    }
    if (pool.rewards(msg.sender) > 0)
      pool.harvestToCompounder(msg.sender, type(uint256).max, address(this));
  }

  receive() external payable {}

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

