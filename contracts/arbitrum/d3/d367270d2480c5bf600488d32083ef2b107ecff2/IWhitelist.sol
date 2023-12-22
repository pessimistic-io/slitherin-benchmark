// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

interface IWhitelist {

    function changeTier(address _address, uint256 _tier) external;

    function changeTierBatch(address[] calldata _addresses, uint256[] calldata _tierList) external;

    function getTier(address _address) external view returns (uint256);
}
