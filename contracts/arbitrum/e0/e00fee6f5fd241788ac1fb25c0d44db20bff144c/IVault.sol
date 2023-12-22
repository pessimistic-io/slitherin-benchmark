// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IVault {

    function whitelistedTokens(address _token) external view returns (bool);
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);
    function getRedemptionAmount(address _token, uint256 _usdgAmount) external view returns (uint256);
    function mintBurnFeeBasisPoints() external view returns (uint256);
    function taxBasisPoints() external view returns (uint256);
}
