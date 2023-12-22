//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNFTStrategy.sol";

contract CamelotNFTStrategyMainnet_GRAIL_USDC is CamelotNFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x87425D8812f44726091831a9A109f4bDc3eA34b4);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x9CB2F70C8360461ab35e31A07ae9e94B26CA8A86);
    CamelotNFTStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0)
    );
    rewardTokens = [grail];
  }
}

