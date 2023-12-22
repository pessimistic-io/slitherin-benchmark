// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IVotingEscrow {
    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }

    event Deposit(
        address indexed provider,
        uint256 tokenId,
        uint256 value,
        uint256 indexed locktime,
        DepositType deposit_type,
        uint256 ts
    );

    function attachments(uint256 tokenId) external view returns (uint256);
    function token() external view returns (address);

    function team() external returns (address);

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

    function voting(uint tokenId) external;

    function abstain(uint tokenId) external;

    function attach(uint tokenId) external;

    function detach(uint tokenId) external;

    function checkpoint() external;

    function increase_amount(uint256 _tokenId, uint256 _value) external;

    function increase_unlock_time(
        uint256 _tokenId,
        uint256 _lock_duration
    ) external;

    function deposit_for(uint tokenId, uint value) external;

    function create_lock(
        uint256 _value,
        uint256 _lock_duration
    ) external returns (uint256);

    function create_lock_for(uint, uint, address) external returns (uint);

     function withdraw(uint256 _tokenId) external;
    
    function balanceOfNFT(uint) external view returns (uint);

    function balanceOfNFTAt(uint, uint) external view returns (uint);

    function totalSupply() external view returns (uint);

    function locked__end(uint) external view returns (uint);
}

/*
u1 => deposit 1 eth and 1000 usdc
u2 => deposit 1 eth and 1000 usdc [after 5 minutes]
we will 
    1- add liquidity
    1- deposit liquidity in guage
    1- getRewards
    1- create a lock
    1- vote the nft
u3 => deposit 1 eth and 1000 usdc [after 5 minutes]
    1- add liquidity
    1- deposit liquidity in guage
    1- getRewards
    1- increase amount
*/
