// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IHypervisor {
    function pool() external view returns(address);
    function getTotalAmounts() external view returns(uint tot0,uint tot1);
}

