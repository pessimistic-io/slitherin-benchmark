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

contract BasicStakingStrategyV3 is IStakingStrategy, Ownable {
    using SafeERC20 for IERC20;

    mapping(uint256 => address[]) public rewardTokensPerEpoch;

    mapping(uint256 => uint256[]) public rewardAmountsPerEpoch;

    mapping(uint256 => uint256) public lastTimestamp;

    address[] public defaultRewardTokens;

    uint256[] public defaultRewardAmounts;

    uint256 public balance;

    address public immutable ssov;

    event UpdateDefaultRewards(
        address[] defaultRewardTokens,
        uint256[] defaultRewardAmounts
    );

    event EmergencyWithdraw(address sender);

    constructor(
        address _ssov,
        address[] memory _defaultRewardTokens,
        uint256[] memory _defaultRewardAmounts
    ) {
        ssov = _ssov;

        updateDefaultRewards(_defaultRewardTokens, _defaultRewardAmounts);
    }

    function updateDefaultRewards(
        address[] memory _defaultRewardTokens,
        uint256[] memory _defaultRewardAmounts
    ) public onlyOwner {
        require(
            _defaultRewardTokens.length == _defaultRewardAmounts.length,
            "Inputs lengths must be equal"
        );

        defaultRewardTokens = _defaultRewardTokens;
        defaultRewardAmounts = _defaultRewardAmounts;

        emit UpdateDefaultRewards(_defaultRewardTokens, _defaultRewardAmounts);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return defaultRewardTokens;
    }

    function stake(uint256 amount)
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        if (balance == 0) {
            rewardTokensPerEpoch[epoch] = defaultRewardTokens;
            rewardAmountsPerEpoch[epoch] = defaultRewardAmounts;
        }

        (uint256 startTime, uint256 expiry) = _ssov.getEpochTimes(epoch);

        require(block.timestamp < expiry, "Cannot stake after expiry");

        uint256 rewardTokensLength = rewardTokensPerEpoch[epoch].length;

        rewardAmounts = new uint256[](rewardTokensLength);

        for (uint256 i; i < rewardTokensLength; ) {
            rewardAmounts[i] =
                (rewardAmountsPerEpoch[epoch][i] / (expiry - startTime)) *
                (block.timestamp - startTime);

            unchecked {
                ++i;
            }
        }

        balance += amount;

        emit Stake(msg.sender, amount, balance, rewardAmounts);
    }

    function unstake()
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        uint256 rewardTokensLength = rewardTokensPerEpoch[epoch].length;

        rewardAmounts = new uint256[](rewardTokensLength);

        balance = 0;

        for (uint256 i; i < rewardTokensLength; ) {
            rewardAmounts[i] = rewardAmountsPerEpoch[epoch][i];

            IERC20(rewardTokensPerEpoch[epoch][i]).safeTransfer(
                msg.sender,
                rewardAmounts[i]
            );

            unchecked {
                ++i;
            }
        }

        emit Unstake(msg.sender, balance, rewardAmounts);
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

