// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";

interface IMUSD is IERC20 {
    function mintShares(address _receipient, uint256 _shares, uint256 _amount) external returns (uint256);

    function burnShares(address _account, uint256 _shares, uint256 _amount) external returns (uint256);

    function getSharesByMintedMUSD(uint256 _mUSDAmount) external view returns (uint256);

    function getMintedMUSDByShares(uint256 _sharesAmount) external view returns (uint256);

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);
}
