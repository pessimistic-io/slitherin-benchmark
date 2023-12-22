// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStargateLpStaking {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }
        // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. STGs to distribute per block.
        uint256 lastRewardBlock; // Last block number that STGs distribution occurs.
        uint256 accStargatePerShare; // Accumulated STGs per share, times 1e12. See below.
    }
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function balanceOf(address _owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalLiquidity() external view returns (uint256);

    function poolLength() external view returns (uint256);

    // function getPoolInfo(uint256) external view returns (address);

    
    function userInfo(uint256, address) external view returns (UserInfo calldata);

    function poolInfo(uint256) external view returns(PoolInfo calldata);
}

