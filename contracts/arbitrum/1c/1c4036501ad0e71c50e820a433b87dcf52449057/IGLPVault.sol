// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

interface IGLPVault {
    function mintBurnFeeBasisPoints() external view returns (uint256);
    function taxBasisPoints() external view returns (uint256);
    function getMinPrice(address _token) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);
}
