//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {ISsovV3} from "./ISsovV3.sol";
import {IStakingStrategy} from "./IStakingStrategy.sol";
import {IERC20} from "./IERC20.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";

interface ICrv2PoolGauge is IERC20 {
    function deposit(
        uint256 _value,
        address _addr,
        bool _claim_rewards
    ) external;

    function withdraw(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external;

    function claimable_reward_write(address _addr, address _token)
        external
        returns (uint256);
}

interface ICrvChildGauge {
    function mint(address _gauge) external;
}

interface ISsovV3YieldBooster {
    function receiveRewards(
        address _ssov,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external;
}

/// @title Stakes 2CRV into the USDC/USDT Curve 2pool on Arbitrum
contract CurveStakingStrategyV1 is IStakingStrategy, Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for ICrv2Pool;

    mapping(uint256 => uint256) public rewardsPerEpoch;

    mapping(uint256 => uint256) public lastTimestamp;

    mapping(uint256 => uint256) public crvRewardsEmitted;

    ICrv2PoolGauge public constant CRV_2POOL_GAUGE =
        ICrv2PoolGauge(0xCE5F24B7A95e9cBa7df4B54E911B4A3Dc8CDAf6f);

    ICrvChildGauge public constant CRV_CHILD_GAUGE =
        ICrvChildGauge(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    IERC20 public constant CRV =
        IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);

    IERC20 public constant DPX =
        IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);

    address[] public rewardTokens = new address[](2);

    address public immutable ssov;

    event NewRewards(uint256 epoch, uint256 rewards);
    event EmergencyWithdraw(address sender);

    constructor(address _ssov) {
        ssov = _ssov;

        CRV_2POOL.safeIncreaseAllowance(
            address(CRV_2POOL_GAUGE),
            type(uint256).max
        );

        rewardTokens[0] = address(CRV);
        rewardTokens[1] = address(DPX);
    }

    function updateRewardsPerEpoch(uint256 _rewards, uint256 _epoch)
        external
        onlyOwner
    {
        rewardsPerEpoch[_epoch] = _rewards;
        emit NewRewards(_rewards, _epoch);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function _updateCrvRewards(uint256 epoch) internal returns (uint256) {
        uint256 crvRewards = CRV.balanceOf(address(this));

        CRV_CHILD_GAUGE.mint(address(CRV_2POOL_GAUGE));

        crvRewards = CRV.balanceOf(address(this)) - crvRewards;

        crvRewardsEmitted[epoch] += crvRewards;

        return crvRewardsEmitted[epoch];
    }

    function stake(uint256 amount)
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        (uint256 startTime, uint256 expiry) = _ssov.getEpochTimes(epoch);

        uint256 rewardRate = rewardsPerEpoch[epoch] / (expiry - startTime);

        uint256 rewardsEmitted = rewardRate * (block.timestamp - startTime);

        rewardTokenAmounts = new uint256[](2);

        rewardTokenAmounts[1] = rewardsEmitted;

        // Transfer 2CRV from sender
        CRV_2POOL.safeTransferFrom(msg.sender, address(this), amount);

        rewardTokenAmounts[0] = _updateCrvRewards(epoch);

        // Deposit curve LP to the curve gauge for rewards
        CRV_2POOL_GAUGE.deposit(
            amount,
            address(this),
            false /* _claim_rewards */
        );

        uint256 totalStakedBalance = CRV_2POOL_GAUGE.balanceOf(address(this));

        emit Stake(msg.sender, amount, totalStakedBalance, rewardTokenAmounts);
    }

    function unstake()
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        uint256 balance = CRV_2POOL_GAUGE.balanceOf(address(this));

        // Withdraw curve LP from the curve gauge and claim rewards
        CRV_2POOL_GAUGE.withdraw(
            balance,
            address(this),
            false /* _claim_rewards */
        );

        uint256 rewards = _updateCrvRewards(epoch);

        CRV.safeTransfer(msg.sender, rewards);

        CRV_2POOL.safeTransfer(msg.sender, balance);

        rewardTokenAmounts = new uint256[](2);

        rewardTokenAmounts[0] = rewards;

        rewardTokenAmounts[1] = rewardsPerEpoch[epoch];

        IERC20(rewardTokens[1]).safeTransfer(
            msg.sender,
            rewardsPerEpoch[epoch]
        );

        emit Unstake(msg.sender, balance, rewardTokenAmounts);
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by the owner
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(address[] calldata tokens, bool transferNative)
        external
        onlyOwner
    {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i = 0; i < tokens.length; i++) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        emit EmergencyWithdraw(msg.sender);
    }

    modifier onlySsov(address _sender) {
        require(_sender == ssov, "Sender must be the ssov");
        _;
    }
}

