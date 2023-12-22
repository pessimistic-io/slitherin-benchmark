// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {FractionTreasuryInterface} from "./FractionTreasuryInterface.sol";
import {InitializableInterface, Initializable} from "./Initializable.sol";

contract FractionTreasury is FractionTreasuryInterface, Initializable {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.admin')) - 1)
   */
  bytes32 constant _adminSlot = 0xce00b027a69a53c861af45595a8cf45803b5ac2b4ac1de9fc600df4275db0c38;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.erc20')) - 1)
   */
  bytes32 constant _erc20Slot = 0x6ebf95e47cb231cfff4bea9a1ad1373e80b132b62e1e8c3d7140a0eb735a4fbe;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.erc721')) - 1)
   */
  bytes32 constant _erc721Slot = 0x3451dc475ec85e804d92f70e72b9e7035d2af464474c5d81f7ca2a5d1580b1fc;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.fractionToken')) - 1)
   */
  bytes32 constant _fractionTokenSlot = 0xd89fe62d9f9e11e45c3495d74cbaa5b78ebf5a895eb3dbf13d5339bc00db6c48;

  modifier onlyAdmin() {
    assembly {
      let _admin := sload(_adminSlot)
      switch eq(_admin, caller())
      case 0 {
        // get free memory pointer
        let ptr := mload(0x40)
        // bump memory up to reserve 32 bytes
        mstore(0x40, add(ptr, 0x20))
        // set byte string to "FRACT10N: admin only function"
        mstore(ptr, 0x465241435431304e3a2061646d696e206f6e6c792066756e6374696f6e000000)
        // tell revert that string starts at ptr, tell revert that string length is 29 bytes
        revert(ptr, 0x1d)
      }
    }
    _;
  }

  constructor() {}

  function init(bytes memory data) external override returns (bytes4) {
    require(!_isInitialized(), "FRACT10N: already initialized");
    (address erc20address, address erc721address, address fractionToken) = abi.decode(
      data,
      (address, address, address)
    );
    assembly {
      sstore(_erc20Slot, erc20address)
      sstore(_erc721Slot, erc721address)
      sstore(_fractionTokenSlot, fractionToken)
    }
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  function getSourceERC20() external view returns (address sourceERC20) {
    assembly {
      sourceERC20 := sload(_erc20Slot)
    }
  }

  function setSourceERC20(address sourceERC20) external onlyAdmin {
    assembly {
      sstore(_erc20Slot, sourceERC20)
    }
  }

  function getSourceERC721() external view returns (address sourceERC721) {
    assembly {
      sourceERC721 := sload(_erc721Slot)
    }
  }

  function setSourceERC721(address sourceERC721) external onlyAdmin {
    assembly {
      sstore(_erc721Slot, sourceERC721)
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
}

