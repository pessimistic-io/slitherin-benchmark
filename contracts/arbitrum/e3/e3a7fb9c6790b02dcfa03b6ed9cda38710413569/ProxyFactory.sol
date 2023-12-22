// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { Ownable } from "./Ownable.sol";
import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "./ProxyAdmin.sol";

contract ProxyFactory is Ownable {
    address public proxyAdmin;

    event CreateProxyAdmin(address proxyAdmin, address owner);
    event BuildProxy(address proxy);

    constructor(address _proxyAdmin) public {
        proxyAdmin = _proxyAdmin;
    }

    function createProxyAdmin(address _owner) external onlyOwner returns (address) {
        require(proxyAdmin == address(0), "already_created");
        ProxyAdmin proxyAdm = new ProxyAdmin();
        proxyAdm.transferOwnership(_owner);
        proxyAdmin = address(proxyAdm);
        emit CreateProxyAdmin(proxyAdmin, _owner);
        return proxyAdmin;
    }

    function build(
        address _impl,
        bytes calldata _data
    ) external onlyOwner returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_impl, proxyAdmin, _data);
        emit BuildProxy(address(proxy));
        return address(proxy);
    }
}

