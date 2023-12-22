// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface IBaseComponent {
    error BaseComponent__OnlyDelegateCall();
    error BaseComponent__OnlyFeeManager();

    function getFeeManager() external view returns (address);

    function directCall(address target, bytes calldata data) external returns (bytes memory);
}

