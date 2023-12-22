// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./TransparentUpgradeableProxy.sol";

library ProxyFactory {
    event ProxyCreated(address proxy);

    function createTransparentProxy(address logic, address proxyAdmin, bytes memory payload, bytes32 salt) external returns (address proxy) {
        proxy = deployTransparent(logic, proxyAdmin, payload, salt);
        emit ProxyCreated(proxy);
    }

    function deployTransparent(address _logic, address _admin, bytes memory _data, bytes32 _salt) private returns (address) {
        bytes memory creationByteCode = getCreationBytecode(_logic, _admin, _data);
        return _deployTransparentProxy(creationByteCode, _salt);
    }

    function getCreationBytecode(address _logic, address _admin, bytes memory _data) private pure returns (bytes memory) {
        bytes memory bytecode = type(TransparentUpgradeableProxy).creationCode;
        return abi.encodePacked(bytecode, abi.encode(_logic, _admin, _data));
    }

    function _deployTransparentProxy(bytes memory _creationByteCode, bytes32 _salt) private returns (address payable _proxy) {
        assembly {
            _proxy := create2(0, add(_creationByteCode, 0x20), mload(_creationByteCode), _salt)
            if iszero(extcodesize(_proxy)) {
                revert(0, 0)
            }
        }
    }
}

