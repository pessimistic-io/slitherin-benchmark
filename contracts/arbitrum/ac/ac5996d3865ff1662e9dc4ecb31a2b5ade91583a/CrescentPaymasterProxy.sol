// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ERC1967Proxy.sol";
import "./Address.sol";

contract CrescentPaymasterProxy is ERC1967Proxy {

    constructor(address implementation, address _create2Factory, address _entryPointController, address _walletController, address dkimVerifier) ERC1967Proxy(implementation, bytes("")) {
        _changeAdmin(msg.sender);

        Address.functionDelegateCall(implementation, abi.encodeWithSignature("initialize(address,address,address,address,address)", _create2Factory, _entryPointController, _walletController, dkimVerifier, msg.sender));
    }

    function getImplementation() public view returns (address) {
        return _implementation();
    }

    function upgradeDelegate(address newImplementation) public {
        require(msg.sender == _getAdmin());
        _upgradeTo(newImplementation);
    }
}

