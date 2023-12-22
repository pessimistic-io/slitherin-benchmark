// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

//  _    __      __          ______                                      __   _   ____________________
// | |  / /___  / /____     / ____/__________________ _      _____  ____/ /  / | / / ____/_  __/ ____/
// | | / / __ \/ __/ _ \   / __/ / ___/ ___/ ___/ __ \ | /| / / _ \/ __  /  /  |/ / /_    / / / __/
// | |/ / /_/ / /_/  __/  / /___(__  ) /__/ /  / /_/ / |/ |/ /  __/ /_/ /  / /|  / __/   / / / /___
// |___/\____/\__/\___/  /_____/____/\___/_/   \____/|__/|__/\___/\__,_/  /_/ |_/_/     /_/ /_____/

pragma solidity 0.8.7;

interface IxNFTE {
    function checkpoint() external;

    function depositFor(address addr, uint128 value) external;

    function createLock(
        uint128 value,
        uint256 unlockTime,
        bool autoCooldown
    ) external;

    function increaseAmount(uint128 value) external;

    function increaseUnlockTime(uint256 unlockTime) external;

    function initiateCooldown() external;

    function withdraw() external;

    function userPointEpoch(address addr) external view returns (uint256);

    function lockedEnd(address addr) external view returns (uint256);

    function getLastUserSlope(address addr) external view returns (int128);

    function getUserPointHistoryTS(address addr, uint256 idx)
        external
        view
        returns (uint256);

    function balanceOf(address addr, uint256 ts)
        external
        view
        returns (uint256);

    function balanceOf(address addr) external view returns (uint256);

    function balanceOfAt(address, uint256 blockNumber)
        external
        view
        returns (uint256);

    function totalSupply(uint256 ts) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalSupplyAt(uint256 blockNumber) external view returns (uint256);
}

