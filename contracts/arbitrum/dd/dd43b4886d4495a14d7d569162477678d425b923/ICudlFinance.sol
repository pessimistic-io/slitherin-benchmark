//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface ICudlFinance {
    function burnScore(uint256 nftId, uint256 amount) external;

    function addScore(uint256 nftId, uint256 amount) external;

    function addTOD(uint256 nftId, uint256 duration) external;

    function isPetOwner(uint256 petId, address user)
        external
        view
        returns (bool);

    function timeUntilStarving(uint256 _nftId) external view returns (uint256);

    function timePetBorn(uint256 token) external view returns (uint256);

    function nftToId(address nft, uint256 token)
        external
        view
        returns (uint256);

    function getPetInfo(uint256 _nftId)
        external
        view
        returns (
            uint256 _pet,
            bool _isStarving,
            uint256 _score,
            uint256 _level,
            uint256 _expectedReward,
            uint256 _timeUntilStarving,
            uint256 _lastTimeMined,
            uint256 _timepetBorn,
            address _owner,
            address _token,
            uint256 _tokenId,
            bool _isAlive
        );
}

