// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IStrategERC3525 {
    function initialize(address _vault, address _owner, address _tokenFee, address _treasury, address _relayer) external;

    function redeem(uint256 _tokenId) external;
    function addRewards(uint256 _amount) external;
    function pullToken(uint256 _tokenId) external;
    function ownerOf(uint256 _tokenId) external view returns (address);
}

