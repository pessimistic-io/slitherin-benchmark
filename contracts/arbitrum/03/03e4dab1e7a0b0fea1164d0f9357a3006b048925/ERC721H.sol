// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {InitializableInterface, Initializable} from "./Initializable.sol";

import {FractionTreasuryInterface} from "./FractionTreasuryInterface.sol";

abstract contract ERC721H is Initializable {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.holographer')) - 1)
   */
  bytes32 constant _holographerSlot = 0x9d18ffc4ec8de69fbcc9e22571d0625b23c1bcde4b3ded4489551c34c1a78cd4;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.owner')) - 1)
   */
  bytes32 constant _ownerSlot = 0x09f0f4aad16401d8d9fa2f59a36c61cf8593c814849bbc8ef7ed5c0c63e0e28f;
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.treasury')) - 1)
   */
  bytes32 constant _fractionTreasurySlot = 0x1136b6b83da8d61ba4fa1d68b5ef128602c708583193e4c55add5660847fff03;

  modifier onlyHolographer() {
    require(msg.sender == holographer(), "ERC721: holographer only");
    _;
  }

  modifier onlyOwner() {
    require(msgSender() == _getOwner(), "ERC721: owner only function");
    _;
  }

  /**
   * @dev Constructor is left empty and init is used instead
   */
  constructor() {}

  /**
   * @notice Used internally to initialize the contract instead of through a constructor
   * @dev This function is called by the deployer/factory when creating a contract
   * @param initPayload abi encoded payload to use for contract initilaization
   */
  function init(bytes memory initPayload) external virtual override returns (bytes4) {
    return _init(initPayload);
  }

  function _init(bytes memory /* initPayload*/) internal returns (bytes4) {
    require(!_isInitialized(), "ERC721: already initialized");
    address currentOwner;
    assembly {
      sstore(_holographerSlot, caller())
      currentOwner := sload(_ownerSlot)
    }
    require(currentOwner != address(0), "ERC721: owner not set");
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  /**
   * @dev The Holographer passes original msg.sender via calldata. This function extracts it.
   */
  function msgSender() internal view returns (address sender) {
    assembly {
      switch eq(caller(), sload(_holographerSlot))
      case 0 {
        sender := caller()
      }
      default {
        sender := calldataload(sub(calldatasize(), 0x20))
      }
    }
  }

  /**
   * @dev Address of Holograph ERC721 standards enforcer smart contract.
   */
  function holographer() internal view returns (address _holographer) {
    assembly {
      _holographer := sload(_holographerSlot)
    }
  }

  function fractionTreasury() internal view returns (address _fractionTreasury) {
    assembly {
      _fractionTreasury := sload(_fractionTreasurySlot)
    }
  }

  function fractionToken() internal view returns (address _fractionToken) {
    address _fractionTreasury;
    assembly {
      _fractionTreasury := sload(_fractionTreasurySlot)
    }
    _fractionToken = FractionTreasuryInterface(_fractionTreasury).getFractionToken();
  }

  function supportsInterface(bytes4) external pure virtual returns (bool) {
    return false;
  }

  /**
   * @dev Address of initial creator/owner of the collection.
   */
  function owner() external view virtual returns (address) {
    return _getOwner();
  }

  function isOwner() external view returns (bool) {
    return (msgSender() == _getOwner());
  }

  function isOwner(address wallet) external view returns (bool) {
    return wallet == _getOwner();
  }

  function _getOwner() internal view returns (address ownerAddress) {
    assembly {
      ownerAddress := sload(_ownerSlot)
    }
  }

  function _setOwner(address ownerAddress) internal {
    assembly {
      sstore(_ownerSlot, ownerAddress)
    }
  }

  function withdraw() external virtual onlyOwner {
    payable(_getOwner()).transfer(address(this).balance);
  }

  receive() external payable virtual {}

  /**
   * @dev Return true for any un-implemented event hooks
   */
  fallback() external payable virtual {
    assembly {
      switch eq(sload(_holographerSlot), caller())
      case 1 {
        mstore(0x80, 0x0000000000000000000000000000000000000000000000000000000000000001)
        return(0x80, 0x20)
      }
      default {
        revert(0x00, 0x00)
      }
    }
  }
}

