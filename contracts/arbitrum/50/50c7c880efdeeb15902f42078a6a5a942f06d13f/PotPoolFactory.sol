// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./ERC20.sol";
import "./Governable.sol";
import "./OwnableWhitelist.sol";
import "./IPoolFactory.sol";
import "./PotPool.sol";

contract PotPoolFactory is OwnableWhitelist, IPoolFactory {
  address public iFARM = 0x9dCA587dc65AC0a043828B0acd946d71eb8D46c1;
  uint256 public poolDefaultDuration = 604800; // 7 days

  function setPoolDefaultDuration(uint256 _value) external onlyOwner {
    poolDefaultDuration = _value;
  }

  function deploy(address actualStorage, address vault) override external onlyWhitelisted returns (address) {
    address actualGovernance = Governable(vault).governance();

    string memory tokenSymbol = ERC20(vault).symbol();
    address[] memory rewardDistribution = new address[](1);
    rewardDistribution[0] = actualGovernance;
    address[] memory rewardTokens = new address[](1);
    rewardTokens[0] = iFARM;
    PotPool pool = new PotPool(
      rewardTokens,
      vault,
      poolDefaultDuration,
      rewardDistribution,
      actualStorage,
      string(abi.encodePacked("p", tokenSymbol)),
      string(abi.encodePacked("p", tokenSymbol)),
      ERC20(vault).decimals()
    );

    Ownable(pool).transferOwnership(actualGovernance);

    return address(pool);
  }
}

