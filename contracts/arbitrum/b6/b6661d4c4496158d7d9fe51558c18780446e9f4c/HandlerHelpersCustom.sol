// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERCHandler.sol";

/**
    @title Function used across handler contracts.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract HandlerHelpersCustom is Initializable, PausableUpgradeable, IERCHandler, OwnableUpgradeable {
  address public _bridgeAddress;

  // resourceID => token contract address
  mapping(bytes32 => address) public _resourceIDToTokenContractAddress;

  // token contract address => resourceID
  mapping(address => bytes32) public _tokenContractAddressToResourceID;

  // token contract address => is whitelisted
  mapping(address => bool) public _contractWhitelist;

  // token contract address => is burnable
  mapping(address => bool) public _burnList;

  /**
        @param bridgeAddress Contract address of previously deployed Bridge.
     */
  function __HandlerHelpersCustom_init(address bridgeAddress, address owner) internal onlyInitializing {
    __HandlerHelpersCustom_init_unchained(bridgeAddress, owner);
  }

  function __HandlerHelpersCustom_init_unchained(address bridgeAddress, address owner) internal onlyInitializing {
    __Ownable_init();
    __Pausable_init();

    _bridgeAddress = bridgeAddress;

    // set owner
    _transferOwnership(owner);
  }

  function _onlyBridge() internal view virtual {
    require(_msgSender() == _bridgeAddress, 'sender must be bridge contract');
  }

  /**
        @notice First verifies {_resourceIDToContractAddress}[{resourceID}] and
        {_contractAddressToResourceID}[{contractAddress}] are not already set,
        then sets {_resourceIDToContractAddress} with {contractAddress},
        {_contractAddressToResourceID} with {resourceID},
        and {_contractWhitelist} to true for {contractAddress}.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
  function setResource(bytes32 resourceID, address contractAddress) external virtual override {
    _onlyBridge();

    _setResource(resourceID, contractAddress);
  }

  /**
        @notice First verifies {contractAddress} is whitelisted, then sets {_burnList}[{contractAddress}]
        to true.
        @param contractAddress Address of contract to be used when making or executing deposits.
     */
  function setBurnable(address contractAddress) external virtual override {
    _onlyBridge();

    _setBurnable(contractAddress);
  }

  function withdraw(bytes memory data) external virtual override {}

  function _setResource(bytes32 resourceID, address contractAddress) internal virtual {
    _resourceIDToTokenContractAddress[resourceID] = contractAddress;
    _tokenContractAddressToResourceID[contractAddress] = resourceID;

    _contractWhitelist[contractAddress] = true;
  }

  function _setBurnable(address contractAddress) internal virtual {
    require(_contractWhitelist[contractAddress], 'provided contract is not whitelisted');
    _burnList[contractAddress] = true;
  }

  /**
        @notice Pause or unpause the grant access function.
        @notice Set paused to true or false.
    */
  function togglePause() external virtual onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  // TESTING ONLY
  function setBridge(address bridgeAddress) external virtual onlyOwner whenNotPaused {
    require(bridgeAddress != address(0) && bridgeAddress != _bridgeAddress, 'bad');
    _bridgeAddress = bridgeAddress;
  }
}

