// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface INitroCustomReq {
    function canDepositDescription() external view returns (string calldata);
    function canHarvestDescription() external view returns (string calldata);

    function canDeposit(address user, uint256 tokenId) external view returns (bool);
    function canHarvest(address user) external view returns (bool);
}
