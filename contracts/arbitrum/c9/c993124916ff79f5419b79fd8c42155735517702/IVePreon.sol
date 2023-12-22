// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVePreon {
    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    function token() external view returns (address);

    function preon() external view returns (address);

    function team() external returns (address);

    function epoch() external view returns (uint256);

    function pointHistory(uint256 loc) external view returns (Point memory);

    function userPointHistory(
        uint256 tokenId,
        uint256 loc
    ) external view returns (Point memory);

    function userPointEpoch(uint256 tokenId) external view returns (uint256);

    function ownerOf(uint256) external view returns (address);

    function isApprovedOrOwner(address, uint256) external view returns (bool);

    function transferFrom(address, address, uint256) external;

    function voting(uint256 tokenId) external;

    function abstain(uint256 tokenId) external;

    function attach(uint256 tokenId) external;

    function detach(uint256 tokenId) external;

    function checkpoint() external;

    function depositFor(uint256 tokenId, uint256 value) external;

    function createLockFor(
        uint256,
        uint256,
        address
    ) external returns (uint256);

    function balanceOfNFT(uint256) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalSupplyAt(uint256 _block) external view returns (uint256);
}

