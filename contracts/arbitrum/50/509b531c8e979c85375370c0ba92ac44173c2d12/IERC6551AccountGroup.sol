// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IERC6551AccountGroup {
    function getAccountInitializer(address account) external view returns (address initializer);
    function checkValidAccountUpgrade(address sender, address account, address implementation) external view;
}

