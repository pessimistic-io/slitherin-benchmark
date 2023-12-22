// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./Admin.sol";
import "./Initializable.sol";

contract FractionMetadataRendererProxy is Admin, Initializable {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.fractionMetadataRenderer')) - 1)
   */
  bytes32 constant _fractionMetadataRendererSlot = 0x556d928deb8901ad41da8da8b8c6ad91ceb8189a2cbc641ba63afef94f064fbc;

  constructor() {}

  function init(bytes memory data) external override returns (bytes4) {
    require(!_isInitialized(), "FRACT10N: already initialized");
    (address fractionTreasury, address fractionMetadataRenderer, bytes memory initCode) = abi.decode(
      data,
      (address, address, bytes)
    );
    assembly {
      sstore(_adminSlot, fractionTreasury)
      sstore(_fractionMetadataRendererSlot, fractionMetadataRenderer)
    }
    (bool success, bytes memory returnData) = fractionMetadataRenderer.delegatecall(
      abi.encodeWithSignature("init(bytes)", initCode)
    );
    bytes4 selector = abi.decode(returnData, (bytes4));
    require(success && selector == Initializable.init.selector, "initialization failed");
    _setInitialized();
    return Initializable.init.selector;
  }

  function getFractionMetadataRenderer() external view returns (address fractionMetadataRenderer) {
    assembly {
      fractionMetadataRenderer := sload(_fractionMetadataRendererSlot)
    }
  }

  function setFractionMetadataRenderer(address fractionMetadataRenderer) external onlyAdmin {
    assembly {
      sstore(_fractionMetadataRendererSlot, fractionMetadataRenderer)
    }
  }

  receive() external payable {}

  fallback() external payable {
    assembly {
      let fractionMetadataRenderer := sload(_fractionMetadataRendererSlot)
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), fractionMetadataRenderer, 0, calldatasize(), 0, 0)
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

