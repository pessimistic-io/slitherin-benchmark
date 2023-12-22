// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "./Test.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {NetTokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {ERC20} from "./ERC20.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {RebalanceAction} from "./RebalanceAction.sol";
import {ProtohedgeVault} from "./ProtohedgeVault.sol";

uint256 constant FACTOR_ONE_MULTIPLIER = 1*10**6;
uint256 constant FACTOR_TWO_MULTIPLIER = 1*10**12;
uint256 constant FACTOR_THREE_MULTIPLIER = 1*10**18;


contract DeltaNeutralRebalancer {
  address private usdcAddress;
  mapping(address => ProtohedgeVault) vaults;

  constructor(address _usdcAddress) {
    usdcAddress = _usdcAddress; 
  }


}

