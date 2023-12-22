// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./IERC20.sol";

interface IMALLOW is IERC20 {
    function lastEmissionTime() external view returns (uint256);

    function claimMasterV2Rewards(uint256 amount) external returns (uint256 effectiveAmount);

    function claimMasterV3Rewards(uint256 amount) external returns (uint256 effectiveAmount);

    function masterV3EmissionRate() external view returns (uint256);

    function masterV2EmissionRate() external view returns (uint256);

    function burn(uint256 amount) external;
}

