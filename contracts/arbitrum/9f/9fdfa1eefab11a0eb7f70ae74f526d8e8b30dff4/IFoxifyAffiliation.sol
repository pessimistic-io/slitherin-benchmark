// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFoxifyAffiliation {
    enum Level {
        UNKNOWN,
        BRONZE,
        SILVER,
        GOLD
    }

    struct NFTData {
        Level level;
        bytes32 randomValue;
        uint256 timestamp;
    }

    function data(uint256) external view returns (NFTData memory);

    function usersActiveID(address) external view returns (uint256);

    function usersTeam(address) external view returns (uint256);
}

