// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ArbSys.sol";
import "./OwnableUpgradeable.sol";

abstract contract AbstractToken {
  mapping(address => uint256) public emissions;

  function getBaseBalance() external view virtual returns (uint256);

  function totalSupply() public view virtual returns (uint256);

  function getTotalStaked() external view virtual returns (uint256);
}

contract ArbPoolReader is OwnableUpgradeable {
  struct PoolStat {
    uint256 liquidityBalance;
    uint256 liquiditySupply;
    uint256 unwStaked;
    uint256 unwSupply;
    uint256 esUnwStaked;
    uint256 esUnwSupply;
    uint256 ulpEmission;
    uint256 unwEmission;
    uint256 esUnwEmission;
    uint256 l1BlockNumber;
    uint256 l2BlockNumber;
    uint256 timestamp;
  }

  address unwStaker;

  event SetUNWStakerEvent(address unwStaker);

  function initialize(address _owner, address _unwStaker) external initializer {
    __Ownable_init();
    _transferOwnership(_owner);

    unwStaker = _unwStaker;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function setUNWStaker(address _unwStaker) external onlyOwner {
    unwStaker = _unwStaker;
    emit SetUNWStakerEvent(unwStaker);
  }

  function getPoolStat(
    address liquidityPoolAddress,
    address unwAddress,
    address esunwAddress
  ) external view returns (PoolStat memory) {
    return
      PoolStat(
        AbstractToken(liquidityPoolAddress).getBaseBalance(),
        AbstractToken(liquidityPoolAddress).totalSupply(),
        AbstractToken(unwStaker).getTotalStaked(),
        AbstractToken(unwAddress).totalSupply(),
        AbstractToken(esunwAddress).getTotalStaked(),
        AbstractToken(esunwAddress).totalSupply(),
        AbstractToken(esunwAddress).emissions(liquidityPoolAddress),
        AbstractToken(esunwAddress).emissions(unwAddress),
        AbstractToken(esunwAddress).emissions(esunwAddress),
        block.number,
        ArbSys(address(0x64)).arbBlockNumber(),
        block.timestamp
      );
  }
}

