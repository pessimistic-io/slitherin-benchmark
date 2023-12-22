// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
    function borrow(uint256[] memory _tokenIds, uint256 _amount) external;

    function makePayment(uint256 _amount, address _userAddress) external;

    function withdrawCollateral(uint256[] memory _tokenIds) external;

    function liquidate(address _userAddress) external;

    function redeemERC20(address _user, uint256 _amount) external;

    function pauseLoans() external;

    function unpauseLoans() external;

    function withdrawEth(address _to, uint256 _amount) external;

    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) external;

    function withdrawERC721(
        address _to,
        uint256 _tokenId,
        address _tokenAddress
    ) external;

    function setTreasuryAddress(address _treasuryAddress) external;
}

