// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {FractionTreasuryInterface} from "./FractionTreasuryInterface.sol";

import {Owner} from "./Owner.sol";
import {InitializableInterface, Initializable} from "./Initializable.sol";

contract FractionTokenProxy is Owner, Initializable {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.treasury')) - 1)
   */
  bytes32 constant _fractionTreasurySlot = 0x1136b6b83da8d61ba4fa1d68b5ef128602c708583193e4c55add5660847fff03;

  constructor() {}

  function init(bytes memory data) external override returns (bytes4) {
    require(!_isInitialized(), "FRACT10N: already initialized");
    (address fractionTreasury, bytes memory initCode) = abi.decode(data, (address, bytes));
    assembly {
      sstore(_fractionTreasurySlot, fractionTreasury)
      sstore(_ownerSlot, fractionTreasury)
    }
    (bool success, bytes memory returnData) = FractionTreasuryInterface(fractionTreasury).getSourceERC20().delegatecall(
      abi.encodeWithSelector(InitializableInterface.init.selector, initCode)
    );
    bytes4 selector = abi.decode(returnData, (bytes4));
    require(success && selector == InitializableInterface.init.selector, "initialization failed");
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  function getFractionToken() external view returns (address fractionToken) {
    address fractionTreasury;
    assembly {
      fractionTreasury := sload(_fractionTreasurySlot)
    }
    fractionToken = FractionTreasuryInterface(fractionTreasury).getSourceERC20();
  }

  function getFractionTreasury() external view returns (address fractionTreasury) {
    assembly {
      fractionTreasury := sload(_fractionTreasurySlot)
    }
  }

  function setFractionTreasury(address fractionTreasury) external onlyOwner {
    assembly {
      sstore(_fractionTreasurySlot, fractionTreasury)
    }
  }

  receive() external payable {}

  fallback() external payable {
    address fractionTreasury;
    assembly {
      fractionTreasury := sload(_fractionTreasurySlot)
    }
    address fractionToken = FractionTreasuryInterface(fractionTreasury).getSourceERC20();
    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), fractionToken, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }
}

