// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFeeStore {

    function pairFeeAddress(address token) external view returns (address);

    function factoryAddress() external view returns (address);
}

