//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IAtlasMine.sol";

interface IBattleflyFounderVault {
    struct FounderStake {
        uint256 amount;
        uint256 stakeTimestamp;
        address owner;
        uint256[] founderNFTIDs;
        uint256 lastClaimedDay;
    }

    function topupTodayEmission(uint256 amount) external;

    function topupMagicToStaker(uint256 amount, IAtlasMine.Lock lock) external;

    function depositToStaker(uint256 amount, IAtlasMine.Lock lock) external;

    function stakesOf(address owner) external view returns (FounderStake[] memory);

    function isOwner(address owner, uint256 tokenId) external view returns (bool);

    function balanceOf(address owner) external view returns (uint256 balance);

    function getName() external view returns (string memory);
}

