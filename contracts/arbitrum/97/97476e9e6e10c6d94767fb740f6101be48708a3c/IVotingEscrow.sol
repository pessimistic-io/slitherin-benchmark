// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IVotingEscrow {

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    function token() external view returns (address);
    function team() external view returns (address);
    function epoch() external view returns (uint);
    function point_history(uint loc) external view returns (Point memory);
    function user_point_history(
        uint tokenId, 
        uint loc
    ) external view returns (Point memory);

    function user_point_epoch(uint tokenId) external view returns (uint);

    function ownerOf(uint) external view returns (address);
    function isApprovedOrOwner(address, uint) external view returns (bool);
    function transferFrom(address, address, uint) external;
    function safeTransferFrom(address, address, uint) external;

    function voting(uint tokenId) external;
    function abstain(uint tokenId) external;
    function attach(uint tokenId) external;
    function detach(uint tokenId) external;

    function checkpoint() external;
    function deposit_for(uint tokenId, uint value) external;
    function create_lock_for(uint, uint, address) external returns (uint);

    function balanceOfNFT(uint) external view returns (uint);
    function totalSupply() external view returns (uint);

    // added for MigrationBurn
    function locked(uint) external view returns (LockedBalance memory);
    function balanceOf(address) external view returns (uint);
    function tokenOfOwnerByIndex(address, uint) external view returns (uint);
    function attachments(uint) external view returns (uint);
    function voted(uint256) external view returns (bool);
}

