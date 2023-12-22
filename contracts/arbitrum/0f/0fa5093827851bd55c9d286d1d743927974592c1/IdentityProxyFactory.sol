// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./Proxy.sol";

contract IdentityProxyFactory is Ownable {
    event ProxyCreated(address indexed proxy);

    function getProxyAddress(address identityImpl, bytes32 salt)
        external
        view
        returns (address)
    {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                salt,
                                keccak256(
                                    abi.encodePacked(
                                        type(Proxy).creationCode,
                                        uint256(uint160(identityImpl))
                                    )
                                )
                            )
                        )
                    )
                )
            );
    }

    function createProxy(
        address identityImpl,
        bytes32 salt,
        bytes calldata initData
    ) external onlyOwner returns (address) {
        address proxy = address(new Proxy{salt: salt}(identityImpl));

        if (initData.length > 0) {
            (bool success, ) = proxy.call(initData);
            if (!success) {
                assembly {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }

        emit ProxyCreated(proxy);

        return proxy;
    }
}

