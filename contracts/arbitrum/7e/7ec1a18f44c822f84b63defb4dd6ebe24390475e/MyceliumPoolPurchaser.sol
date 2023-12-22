// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPurchaser, Purchase} from "./IPurchaser.sol";
import {IPoolCommitter} from "./IPoolCommitter.sol";
import {ERC20} from "./ERC20.sol";

contract MyceliumPoolPurchaser is IPurchaser {
  IPoolCommitter private poolCommitter;
  ERC20 private usdcToken;
  address private leveragedPoolAddress;
  constructor (address _poolCommitterAddress, address _usdcAddress, address _leveragedPoolAddress) {
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
    usdcToken = ERC20(_usdcAddress);
    leveragedPoolAddress = _leveragedPoolAddress; 
  }

  function Purchase(uint256 usdcAmount) external returns (Purchase memory) {
    bytes memory commit = abi.encodePacked(usdcAmount);
    usdcToken.approve(leveragedPoolAddress, usdcAmount);
    poolCommitter.commit(bytes32(commit));

    return Purchase({
      usdcAmount: usdcAmount,
      // Token amount is 0 as tokens are not minted straight away
      tokenAmount: 0
    });
  }
}

