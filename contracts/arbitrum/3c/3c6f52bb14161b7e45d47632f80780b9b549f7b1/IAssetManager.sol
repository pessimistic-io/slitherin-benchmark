// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Metadata.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @author DeFragDAO
interface IAssetManager {
    function collateralToken() external view returns (IERC20Metadata);

    function usdc() external view returns (IERC20Metadata);

    function balanceSheet() external view returns (IBalanceSheet);

    function treasuryAddress() external view returns (address);

    function totalProtocolFeesPaid() external view returns (uint256);

    function borrow(uint256 _depositAmount, uint256 _borrowAmount) external;

    function borrowForUser(
        uint256 _depositAmount,
        uint256 _borrowAmount,
        address _userAddress
    ) external;

    function makePayment(uint256 _amount, address _userAddress) external;

    function withdrawCollateral(uint256 _amount) external;

    function liquidate(address _userAddress) external returns (uint256);

    function moveCollateral(address _userAddress, uint256 _amount) external;

    function removeCollateralForUser(
        address _userAddress,
        uint256 _amount
    ) external;

    function redeemERC20(address _user, uint256 _amount) external;

    function pauseLoans() external;

    function unpauseLoans() external;

    function withdrawEth(address _to, uint256 _amount) external;

    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) external;

    function setTreasuryAddress(address _treasuryAddress) external;
}

