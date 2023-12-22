// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IERC721.sol";

interface IFactory {
    function totalDeployed() external view returns (uint256 length);
    function deployInfo(uint256 id) external view returns (address token, address nft, address gumbar, bool _allowed);
    function deployGumBall(
        string calldata _name,
        string calldata _symbol,
        string[] calldata _URIs,
        uint256 _supplyBASE,
        uint256 _supplyGBT,
        address _base,
        address _artist,
        uint256 _delay,
        uint256[] memory _fees
    ) external;
}

interface IGBT {
    function fee() external view returns (uint256);
    function artist() external view returns (address);
    function currentPrice() external view returns (uint256);
    function buy(uint256 _amountBASE, uint256 _minGBT, uint256 expireTimestamp) external;
    function buy(uint256 _amountBASE, uint256 _minGBT, uint256 expireTimestamp, address zapSender, address affiliate) external;
    function sell(uint256 _amountGBT, uint256 _minETH, uint256 expireTimestamp) external;
    function sell(uint256 _amountGBT, uint256 _minETH, uint256 expireTimestamp, address zapSender) external;
    function BASE_TOKEN() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function XGBT() external view returns (address);
    function initial_totalSupply() external view returns (uint256);
    function reserveGBT() external view returns (uint256);
    function borrowCredit(address user) external view returns (uint256);
    function debt(address user) external view returns (uint256);
    function reserveVirtualBASE() external view returns (uint256);
    function reserveRealBASE() external view returns (uint256);
    function floorPrice() external view returns (uint256);
    function mustStayGBT(address user) external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
}

interface IGNFT {
    function approve(address to, uint256 tokenId) external;
    function swapForExact(uint256[] memory id) external;
    function swap(uint256 _amount) external;
    function redeem(uint256[] memory _id) external;
    function gumballs() external view returns (uint256[] memory arr);
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function bFee() external view returns (uint256);
}

interface IXGBT {
    function GBTperXGBT() external view returns (uint256);
    function gumballsDeposited(address user) external view returns (uint256, uint256[] memory);
    function balanceOfNFT(address user) external view returns (uint256, uint256[] memory);
    function getRewardForDuration(address _rewardsToken) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function balanceToken(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function earned(address account, address _rewardsToken) external view returns (uint256);
    function rewardTokens(uint256 index) external view returns (address);
    function stakingToken() external view returns (IERC20);
    function stakingNFT() external view returns (IERC721);
    function getReward(address account) external;
}

interface ICollection {
    function findCollectionByAddress(address gbt) external view returns (uint256 index, address token, address nft, address gumbar, bool allowed);
    function allowedCollections() external view returns (uint256[] memory col);
}
