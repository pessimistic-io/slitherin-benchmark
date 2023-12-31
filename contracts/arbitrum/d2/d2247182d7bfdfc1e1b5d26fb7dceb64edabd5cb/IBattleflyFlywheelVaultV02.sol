// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;
import "./IAtlasMine.sol";

interface IBattleflyFlywheelVaultV02 {
    struct UserStake {
        uint64 lockAt;
        uint256 amount;
        address owner;
        IAtlasMine.Lock lock;
    }

    function deposit(uint128, IAtlasMine.Lock) external returns (uint256);

    function withdraw(uint256[] calldata _depositIds) external returns (uint256);

    function withdrawAll() external returns (uint256);

    function requestWithdrawal(uint256[] calldata _depositIds) external;

    function claim(uint256) external returns (uint256);

    function claimAll() external returns (uint256);

    function getAllowedLocks() external view returns (IAtlasMine.Lock[] memory);

    function getClaimableEmission(uint256) external view returns (uint256);

    function canRequestWithdrawal(uint256 _depositId) external view returns (bool requestable);

    function canWithdraw(uint256 _depositId) external view returns (bool withdrawable);

    function initialUnlock(uint256 _depositId) external view returns (uint64 epoch);

    function retentionUnlock(uint256 _depositId) external view returns (uint64 epoch);

    function getCurrentEpoch() external view returns (uint64 epoch);

    function depositIdsOfUser(address user) external view returns (uint256[] memory depositIds);

    function getName() external view returns (string memory);

    // ================== EVENTS ==================
    event NewUserStake(
        uint256 indexed depositId,
        uint256 amount,
        uint256 unlockAt,
        address indexed owner,
        IAtlasMine.Lock lock
    );
    event UpdateUserStake(
        uint256 indexed depositId,
        uint256 amount,
        uint256 unlockAt,
        address indexed owner,
        IAtlasMine.Lock lock
    );
    event ClaimEmission(uint256 indexed depositId, uint256 emission);
    event WithdrawPosition(uint256 indexed depositId, uint256 amount);
    event RequestWithdrawal(uint256 indexed depositId);

    event AddedUser(address indexed vault);
    event RemovedUser(address indexed vault);
}

