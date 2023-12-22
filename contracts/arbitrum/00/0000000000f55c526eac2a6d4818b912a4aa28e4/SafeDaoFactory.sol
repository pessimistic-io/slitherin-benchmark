// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IGnosisSafeProxyFactory} from "./IGnosisSafeProxyFactory.sol";
import {ISafeDaoFactory} from "./ISafeDaoFactory.sol";
import {CREATE3} from "./CREATE3.sol";

contract SafeDaoFactory is ISafeDaoFactory {
    event ProxyCreation(address proxy, address singleton);

    address public immutable SAFE_FACTORY;
    address public immutable SAFE_SINGLETON;

    constructor(address safe, address singleton) {
        require(safe != address(0), "za");
        require(singleton != address(0), "za");
        SAFE_FACTORY = safe;
        SAFE_SINGLETON = singleton;
    }

    function deploy(bytes32 salt, bytes memory initializer) external payable returns (address proxy) {
        bytes memory creationCode = IGnosisSafeProxyFactory(SAFE_FACTORY).proxyCreationCode();
        bytes memory deploymentCode = abi.encodePacked(creationCode, uint256(uint160(SAFE_SINGLETON)));
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        proxy = CREATE3.deploy(salt, deploymentCode, msg.value);
        require(initializer.length > 0, "!setup");
        assembly {
            if eq(call(gas(), proxy, 0, add(initializer, 0x20), mload(initializer), 0, 0), 0) { revert(0, 0) }
        }
        emit ProxyCreation(proxy, SAFE_SINGLETON);
    }

    function getDeployed(address deployer, bytes32 salt) external view override returns (address deployed) {
        salt = keccak256(abi.encodePacked(deployer, salt));
        return CREATE3.getDeployed(salt);
    }
}

