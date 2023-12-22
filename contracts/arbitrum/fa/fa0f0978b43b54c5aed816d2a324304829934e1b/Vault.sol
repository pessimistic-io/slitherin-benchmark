// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable} from "./Ownable.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

contract Vault is Ownable {
    mapping(bytes4 => address) public routes;

    constructor(address owner) {
        _initializeOwner(owner);
    }

    // Batch register function selectors against target contracts
    function addRoutes(
        bytes4[] memory functionSelectors,
        address[] memory targetContracts
    ) public onlyOwner {
        require(
            functionSelectors.length == targetContracts.length,
            "Array lengths must match"
        );

        for (uint i = 0; i < functionSelectors.length; i++) {
            // Add authorization checks as needed
            routes[functionSelectors[i]] = targetContracts[i];
        }
    }

    // Batch remove routes
    function removeRoutes(bytes4[] memory functionSelectors) public onlyOwner {
        for (uint i = 0; i < functionSelectors.length; i++) {
            // Add authorization checks as needed
            delete routes[functionSelectors[i]];
        }
    }

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) public onlyOwner {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint256 amount) public onlyOwner {
        SafeTransferLib.safeTransferETH(to, amount);
    }

    fallback() external payable {
        bytes4 functionSelector = bytes4(msg.data[:4]);
        address target = routes[functionSelector];
        if (target != address(0) && msg.sender == owner()) {
            (bool success, ) = target.delegatecall(msg.data);
            require(success, "Delegatecall failed");
        }
    }

    receive() external payable {}
}

