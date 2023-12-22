//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./SushiStrategy.sol";

contract SushiStrategyMainnet_MAGIC_ETH is SushiStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9);
    address magic = address(0x539bdE0d7Dbd336b79148AA742883198BBF60342);
    address sushi = address(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
    address miniChef = address(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);
    SushiStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      miniChef,
      13        // Pool id
    );
    rewardTokens = [magic, sushi];
    reward2WETH[magic] = [magic, weth];
    reward2WETH[sushi] = [sushi, weth];
    WETH2deposit[magic] = [weth, magic];
  }
}

