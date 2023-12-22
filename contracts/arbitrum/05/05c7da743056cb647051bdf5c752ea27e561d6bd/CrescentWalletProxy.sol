// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ERC1967Proxy.sol";
import "./ERC1967Upgrade.sol";
import "./Address.sol";
import "./CrescentWalletController.sol";
import "./EntryPointController.sol";

contract CrescentWalletProxy is Proxy, ERC1967Upgrade {

    // This is the keccak-256 hash of "eip4337.proxy.auto_update" subtracted by 1
    bytes32 private constant _AUTO_UPDATE_SLOT = 0xa5a17d1ea6249d0fb1885c3256371b6d5f681c9e9d78ab6541528b3876ccbf4c;

    // This is the keccak-256 hash of "eip4337.proxy.address_controller" subtracted by 1
    bytes32 private constant _ADDRESS_CONTROLLER_SLOT = 0x2374cd50a5aadd10053041ecb594cc361d7af780edf0e72f6583c2ea6919be93;

    // This is the keccak-256 hash of "eip4337.proxy.entry_point_controller" subtracted by 1
    bytes32 private constant _ENTRY_POINT_CONTROLLER_SLOT = 0x04c8313cdbfbab2d7e1fdf25a50bef115b1c0d20d2fa5622bd19332fd17ab474;

    constructor(address entryPointController, address walletController, address dkimVerifier, bytes32 hmua) {
        StorageSlot.getBooleanSlot(_AUTO_UPDATE_SLOT).value = false;

        setEntryPointController(entryPointController);

        setController(walletController);

        address implementation = getControlledImplementation();

        _upgradeTo(implementation);

        Address.functionDelegateCall(implementation, abi.encodeWithSignature("initialize(address,address,bytes32)", entryPointController, dkimVerifier, hmua));
    }

    receive() override external payable virtual {}

    function upgradeDelegate(address newDelegateAddress) public {
        require(msg.sender == getEntryPoint());
        _upgradeTo(newDelegateAddress);
    }

    function setAutoUpdateImplementation(bool value) public {
        require(msg.sender == getEntryPoint());
        StorageSlot.getBooleanSlot(_AUTO_UPDATE_SLOT).value = value;
    }

    function getAutoUpdateImplementation() public view returns(bool) {
        return StorageSlot.getBooleanSlot(_AUTO_UPDATE_SLOT).value;
    }

    function setController(address controller) private {
        StorageSlot.getAddressSlot(_ADDRESS_CONTROLLER_SLOT).value = controller;
    }

    function getControlledImplementation() private view returns (address) {
        address controller = StorageSlot.getAddressSlot(_ADDRESS_CONTROLLER_SLOT).value;
        return CrescentWalletController(controller).getImplementation();
    }

    function getImplementation() public view returns (address) {
        return _implementation();
    }

    /**
    * @dev Returns the current implementation address.
    */
    function _implementation() internal view virtual override returns (address impl) {
        if (getAutoUpdateImplementation()) {
            impl = getControlledImplementation();
        } else {
            impl = ERC1967Upgrade._getImplementation();
        }
    }

    function setEntryPointController(address controller) private {
        StorageSlot.getAddressSlot(_ENTRY_POINT_CONTROLLER_SLOT).value = controller;
    }

    function getEntryPoint() public view returns (address) {
        address controller = StorageSlot.getAddressSlot(_ENTRY_POINT_CONTROLLER_SLOT).value;
        return EntryPointController(controller).getEntryPoint();
    }
}

