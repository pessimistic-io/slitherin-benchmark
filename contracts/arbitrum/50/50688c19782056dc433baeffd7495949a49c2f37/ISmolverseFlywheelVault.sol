// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;
import "./IAtlasMine.sol";

interface ISmolverseFlywheelVault {
    struct UserStake {
        uint64 lockAt;
        uint256 amount;
        address owner;
        IAtlasMine.Lock lock;
    }

    struct SmolverseToken {
        bool enabled;
        address token;
        uint256 allowance;
    }

    function stake(address[] memory tokenAddresses, uint256[] memory tokenIds) external;

    function unstake(address[] memory tokenAddresses, uint256[] memory tokenIds) external;

    function deposit(uint128, IAtlasMine.Lock) external returns (uint256);

    function withdraw(uint256[] memory _depositIds) external returns (uint256);

    function withdrawAll() external returns (uint256);

    function requestWithdrawal(uint256[] memory _depositIds) external;

    function claim(uint256) external returns (uint256);

    function claimAll() external returns (uint256);

    function getAllowedLocks() external view returns (IAtlasMine.Lock[] memory);

    function getClaimableEmission(uint256) external view returns (uint256);

    function canRequestWithdrawal(uint256 _depositId) external view returns (bool requestable);

    function canWithdraw(uint256 _depositId) external view returns (bool withdrawable);

    function initialUnlock(uint256 _depositId) external view returns (uint64 epoch);

    function retentionUnlock(uint256 _depositId) external view returns (uint64 epoch);

    function getCurrentEpoch() external view returns (uint64 epoch);

    function remainingStakeableAmount(address user) external view returns (uint256 remaining);

    function getStakedAmount(address user) external view returns (uint256 amount);

    function getDepositIdsOfUser(address user) external view returns (uint256[] memory depositIds);

    function getName() external pure returns (string memory);

    function getStakedTokens(address user)
        external
        view
        returns (address[] memory tokenAddresses, uint256[] memory tokenIds);
}

