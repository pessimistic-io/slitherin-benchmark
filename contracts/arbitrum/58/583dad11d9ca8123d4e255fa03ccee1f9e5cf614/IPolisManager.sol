//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IPolis} from "./IPolis.sol";

interface IPolisManager {
    error OnlyUpgradeRoleAccess();
    error OnlyTokenOwnerAccess();
    error OnlyOneTokenStaked();
    error CannotUnstakeToken();
    error NotStakedToken();
    error OnlyIfStaked();

    event Staked(address indexed wallet, uint256 indexed tokenId);
    event Unstaked(address indexed wallet, uint256 indexed tokenId);

    function polis() external view returns (IPolis);

    function upgradeHash(
        uint256 tokenId,
        uint8 level
    ) external view returns (bytes32);

    function upgradeWithSignature(
        uint256 tokenId,
        uint8 level,
        bytes calldata signature
    ) external;

    function stake(uint256 tokenId) external;

    function unstake(uint256 tokenId) external;

    function stakedByWallet(address wallet) external view returns (uint256);

    function staker(uint256 tokenId) external view returns (address);
}

