// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ERC1967Proxy.sol";
import "./Address.sol";

contract CrescentPaymasterProxy is ERC1967Proxy {

    constructor(address implementation, address _create2Factory, address _entryPointController, address _walletController, address dkimVerifier, address owner, bytes32 _crescentWalletHash) ERC1967Proxy(implementation, bytes("")) {
        _changeAdmin(owner);

        Address.functionDelegateCall(implementation, abi.encodeWithSignature("initialize(address,address,address,address,address,bytes32)", _create2Factory, _entryPointController, _walletController, dkimVerifier, owner, _crescentWalletHash));
    }

    function getImplementation() public view returns (address) {
        return _implementation();
    }

    function upgradeDelegate(address newImplementation) public {
        require(msg.sender == _getAdmin());
        _upgradeTo(newImplementation);
    }
}

