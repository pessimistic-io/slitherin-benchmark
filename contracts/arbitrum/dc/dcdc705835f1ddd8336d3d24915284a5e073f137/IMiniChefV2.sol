pragma solidity 0.6.6;

import "./IERC20.sol";

// contract IRewarder {
//     IERC20[] public lpToken;

//     function onSushiReward(
//         uint256 pid,
//         address user,
//         address recipient,
//         uint256 sushiAmount,
//         uint256 newLpAmount
//     ) external {}

//     function pendingTokens(
//         uint256 pid,
//         address user,
//         uint256 sushiAmount
//     ) external view returns (IERC20[] memory, uint256[] memory) {}
// }

contract IMiniChefV2 {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    /// @notice Address of SUSHI contract.
    IERC20 public SUSHI;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;

    // function add(
    //     uint256 allocPoint,
    //     IERC20 _lpToken,
    //     IRewarder _rewarder
    // ) external {}

    // function set(
    //     uint256 _pid,
    //     uint256 _allocPoint,
    //     IRewarder _rewarder,
    //     bool overwrite
    // ) external {}

    function deposit(uint256 pid, uint256 amount, address to) external {}

    function withdraw(uint256 pid, uint256 amount, address to) external {}

    function harvest(uint256 pid, address to) external {}

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external {}

    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {}
}

