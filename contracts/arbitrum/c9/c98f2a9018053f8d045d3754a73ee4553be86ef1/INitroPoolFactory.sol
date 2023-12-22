// SPDX-License-Identifier: MIT
pragma solidity >0.7.0 <0.9.0;

interface INitroPoolFactory {
    function emergencyRecoveryAddress() external view returns (address);

    function feeAddress() external view returns (address);

    function getNitroPoolFee(address nitroPoolAddress, address ownerAddress) external view returns (uint256);

    function publishNitroPool(address nftAddress) external;

    function setNitroPoolOwner(address previousOwner, address newOwner) external;

    function WETH() external view returns (address);
}

