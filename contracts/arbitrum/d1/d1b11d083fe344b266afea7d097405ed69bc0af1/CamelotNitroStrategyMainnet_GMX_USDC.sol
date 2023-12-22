//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_GMX_USDC is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x913398d79438e8D709211cFC3DC8566F6C67e1A8);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x978E469E8242cd18af5926A1b60B8D93A550a391);
    address nitroPool = address(0xf54E40b1dB413476324636292cD6c547E4012204);
    CamelotNitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0),
      address(0)
    );
    rewardTokens = [grail];
  }
}

