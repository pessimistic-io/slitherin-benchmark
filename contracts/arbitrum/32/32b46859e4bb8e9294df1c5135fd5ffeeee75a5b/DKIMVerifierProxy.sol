// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ERC1967Proxy.sol";
import "./Address.sol";

contract DKIMVerifierProxy is ERC1967Proxy {

    constructor(address implementation, address _dkimManager, address _proofVerifier, address _rsaVerify) ERC1967Proxy(implementation, bytes("")) {
        _changeAdmin(msg.sender);

        Address.functionDelegateCall(implementation, abi.encodeWithSignature("initialize(address,address,address)", _dkimManager, _proofVerifier, _rsaVerify));
    }

    function getImplementation() public view returns (address) {
        return _implementation();
    }

    function upgradeDelegate(address newImplementation) public {
        require(msg.sender == _getAdmin());
        _upgradeTo(newImplementation);
    }
}

