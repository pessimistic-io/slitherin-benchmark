// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./IERC721.sol";

interface IVePost is IERC721 {
    enum LockType {
        NONE,
        TOKEN_POST,
        LP_NFT
    }

    struct VePostDetail {
        uint128 amount;
        uint end;
        uint start;
        uint32 boostMultiplier;
        LockType lockType;
        uint256 currentWeight;
        uint256 tokenId;
    }

    function balanceOfNFTAt(
        uint _tokenId,
        uint _t
    ) external view returns (uint);

    function ownerOf(uint _tokenId) external view returns (address);

    function locked(
        uint _tokenId
    )
        external
        view
        returns (int128 amount, uint end, uint start, uint32 boostMultiplier);

    function combinePower(address user) external view returns (uint256);

    function create_lock_nft_lp_for(
        uint256 _uni_lp_token_id,
        uint _lock_duration,
        address _to
    ) external returns (uint);

    function create_lock_for(
        uint _value,
        uint _lock_duration,
        address _to
    ) external returns (uint);

    function averageMultiWeightInTime(
        uint[] memory tokenIds,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256);

    function lockType(uint _tokenId) external view returns (uint);

    function lockWhenStake(uint256 _tokenId) external;

    function isLockVeWhenStake(uint256 _tokenId) external view returns (bool);

    function unLockWhenStake(uint256 _tokenId) external;

    function getTotalWeightOfOwner(
        address owner,
        uint timestamp
    ) external view returns (uint256 totalWeight);

    function getAverageWeightOfOwner(
        address owner,
        uint timestamp
    ) external view returns (uint256 averageWeight);

    function tokensOfOwner(
        address owner
    ) external view returns (uint256[] memory);

    function voting(address user, uint256 proposalId) external;

    function abstain(address user) external;
}

