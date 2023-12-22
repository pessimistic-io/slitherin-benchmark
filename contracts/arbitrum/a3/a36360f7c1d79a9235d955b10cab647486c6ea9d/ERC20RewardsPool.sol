// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

contract ERC20RewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  event ERC20VaultDepleted(
    uint64 subPool,
    uint256 subPoolIndex,
    address token,
    uint256 amount,
    address receiver
  );

  //=======================================
  // Addresses
  //=======================================
  address public vaultAddress;

  //=======================================
  // Structs
  //=======================================
  struct ERC20RewardsDistribution {
    uint256[] tokenAmounts;
    address[] tokenAddresses;
    uint256[] tokenChances;
    uint256 totalChance;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => ERC20RewardsDistribution) public rewardDistributions;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _vault) ManagerModifier(_manager) {
    vaultAddress = _vault;
  }

  //=======================================
  // External
  //=======================================
  // Dispense token rewards to the receiver based on the sub-pool ID and random number
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    ERC20RewardsDistribution storage dist = rewardDistributions[_subPoolId];

    DispensedReward[] memory rewards = new DispensedReward[](1);
    (uint256 roll, uint256 nextBase) = Random.getNextRandom(
      _randomBase,
      dist.totalChance
    );

    for (uint256 i = 0; i < dist.tokenChances.length; i++) {
      if (roll < dist.tokenChances[i]) {
        // Return 0 rewards on null token
        if (dist.tokenAddresses[i] == address(0)) {
          return DispensedRewards(nextBase, new DispensedReward[](0));
        }

        IERC20 token = IERC20(dist.tokenAddresses[i]);
        // If there is enough balance in the bank, transfer the reward to the receiver
        if (token.balanceOf(vaultAddress) >= dist.tokenAmounts[i]
          && token.allowance(vaultAddress, address(this)) >= dist.tokenAmounts[i]) {
          try token.transferFrom(vaultAddress, _receiver, dist.tokenAmounts[i]) {
            rewards[0] = DispensedReward(
              RewardTokenType.ERC20,
              dist.tokenAddresses[i],
              0,
              dist.tokenAmounts[i]
            );
          }
          catch {
            rewards = new DispensedReward[](0);
          }
          return DispensedRewards(nextBase, rewards);
        } else {
          emit ERC20VaultDepleted(
            _subPoolId,
            i,
            dist.tokenAddresses[i],
            dist.tokenAmounts[i],
            _receiver
          );
          return DispensedRewards(nextBase, new DispensedReward[](0));
        }
      } else {
        if (roll < dist.tokenChances[i]) {
          roll = 0;
        } else {
          roll -= dist.tokenChances[i];
        }
      }
    }

    // If the rewards pool is empty, and there is no backup pool we return 0 rewards
    return DispensedRewards(nextBase, new DispensedReward[](0));
  }

  //=======================================
  // Admin
  //=======================================
  function configureVault(address _vault) external onlyAdmin {
    vaultAddress = _vault;
  }

  function configureSubPool(
    uint64 _subPoolId,
    uint256[] calldata _tokenChances,
    address[] calldata _tokenAddresses,
    uint256[] calldata _tokenAmounts
  ) external onlyAdmin {
    require(_tokenAmounts.length == _tokenAddresses.length);
    require(_tokenAmounts.length == _tokenChances.length);

    uint256 totalChance = 0;
    for (uint256 i = 0; i < _tokenAmounts.length; i++) {
      totalChance += _tokenChances[i];
    }

    rewardDistributions[_subPoolId] = ERC20RewardsDistribution(
      _tokenAmounts,
      _tokenAddresses,
      _tokenChances,
      totalChance
    );
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

