// SPDX-License-Identifier: Unlicense

pragma solidity 0.7.6;

interface IOrbitVault {
    
    function depositEth(
        uint256,
        uint256,
        uint256,
        address
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );

}
