// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {Admin} from "./Admin.sol";
import {InitializableInterface, Initializable} from "./Initializable.sol";

contract Byte3IncOnChainServicesProxy is Admin, Initializable {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.BYTE3.onChainServices')) - 1)
   */
  bytes32 constant _byte3IncOnChainServicesSlot = 0xdcf48dd9c7dab193663c81db86bc26830048c7343421ef8042e45fac76aef060;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.BYTE3.fractionToken')) - 1)
   */
  bytes32 constant _fractionTokenSlot = 0xabbde9d588642a8feacb536d35c2f63246a01aeb35d1c74374133210bbc3cd94;

  constructor() {}

  function init(bytes memory data) external override returns (bytes4) {
    require(!_isInitialized(), "BYTE3: already initialized");
    (address adminAddress, address byte3IncOnChainServices, address fractionToken) = abi.decode(
      data,
      (address, address, address)
    );
    assembly {
      sstore(_adminSlot, adminAddress)
      sstore(_byte3IncOnChainServicesSlot, byte3IncOnChainServices)
      sstore(_fractionTokenSlot, fractionToken)
    }
    (bool success, bytes memory returnData) = byte3IncOnChainServices.delegatecall(
      abi.encodeWithSelector(InitializableInterface.init.selector, "")
    );
    bytes4 selector = abi.decode(returnData, (bytes4));
    require(success && selector == InitializableInterface.init.selector, "initialization failed");
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  function getByte3IncOnChainServices() external view returns (address byte3IncOnChainServices) {
    assembly {
      byte3IncOnChainServices := sload(_byte3IncOnChainServicesSlot)
    }
  }

  function setByte3IncOnChainServices(address byte3IncOnChainServices) external onlyAdmin {
    assembly {
      sstore(_byte3IncOnChainServicesSlot, byte3IncOnChainServices)
    }
  }

  function getFractionToken() external view returns (address fractionToken) {
    assembly {
      fractionToken := sload(_fractionTokenSlot)
    }
  }

  function setFractionToken(address fractionToken) external onlyAdmin {
    assembly {
      sstore(_fractionTokenSlot, fractionToken)
    }
  }

  receive() external payable {}

  fallback() external payable {
    assembly {
      let byte3IncOnChainServices := sload(_byte3IncOnChainServicesSlot)
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), byte3IncOnChainServices, 0, calldatasize(), 0, 0)
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

