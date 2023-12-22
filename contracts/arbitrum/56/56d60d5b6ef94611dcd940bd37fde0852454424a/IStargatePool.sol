// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IStargatePool {
    function router() external view returns (address);
    function token() external view returns (address);
    function poolId() external view returns (uint16);
}
