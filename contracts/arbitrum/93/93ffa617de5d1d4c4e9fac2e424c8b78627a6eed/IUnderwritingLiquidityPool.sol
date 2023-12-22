// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Metadata.sol";

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
interface IUnderwritingLiquidityPool is IERC20Metadata {
    function deposit(uint256 _amount) external;

    function redeem(uint256 _amount) external;

    function exchangeRate() external view returns (uint256);

    function paddedAmount(uint256 _amount) external view returns (uint256);

    function unpaddedAmount(uint256 _amount) external view returns (uint256);

    function mintAmount(uint256 _amount) external view returns (uint256);

    function withdrawAmount(uint256 _amount) external view returns (uint256);

    function pause() external;

    function unpause() external;

    function isExistingDepositor(
        address _userAddress
    ) external view returns (bool);

    function getAllDepositors() external view returns (address[] memory);

    function getDepositedAmount(
        address _userAddress
    ) external view returns (uint256);

    function getMintedAmount(address) external view returns (uint256);

    function getRedeemedAmount(
        address _userAddress
    ) external view returns (uint256);

    function getWithdrawnAmount(
        address _userAddress
    ) external view returns (uint256);

    function getTotalDepositedAmount() external view returns (uint256);

    function getTotalMintedAmount() external view returns (uint256);

    function getTotalRedeemedAmount() external view returns (uint256);

    function getTotalWithdrawnAmount() external view returns (uint256);

    function getPosition(
        address _userAddress
    )
        external
        view
        returns (
            uint256 depositedAmount,
            uint256 mintedAmount,
            uint256 redeemedAmount,
            uint256 withdrawnAmount
        );
}

