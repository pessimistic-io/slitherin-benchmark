// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPurchaser, Purchase} from "./IPurchaser.sol";
import {IPoolCommitter} from "./IPoolCommitter.sol";

contract MyceliumPoolPurchaser is IPurchaser {
  IPoolCommitter private poolCommitter;
  constructor (address _poolCommitterAddress) {
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
  }

  function Purchase(uint256 usdcAmount) external returns (Purchase memory) {
    bytes memory commit = abi.encodePacked(usdcAmount);

    poolCommitter.commit(bytes32(commit));

    return Purchase({
      usdcAmount: usdcAmount,
      // Token amount is 0 as tokens are not minted straight away
      tokenAmount: 0
    });
  }
}

