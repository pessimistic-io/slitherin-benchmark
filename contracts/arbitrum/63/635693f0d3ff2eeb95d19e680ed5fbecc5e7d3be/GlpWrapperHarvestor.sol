// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./BoringOwnable.sol";
import "./Address.sol";
import "./IGmxGlpRewardHandler.sol";
import "./IMimCauldronDistributor.sol";
import "./IGmxRewardRouterV2.sol";
import "./IGmxRewardTracker.sol";

contract GlpWrapperHarvestor is BoringOwnable {
    using Address for address;
    event OperatorChanged(address indexed, bool);
    event DistributorChanged(IMimCauldronDistributor indexed, IMimCauldronDistributor indexed);
    error NotAllowedOperator();
    error ReturnRewardBalance(uint256 balance);

    IGmxGlpRewardHandler public immutable wrapper;
    IERC20 public immutable rewardToken;
    IERC20 public immutable outputToken;
    IGmxRewardRouterV2 public immutable rewardRouterV2;

    IMimCauldronDistributor public distributor;
    mapping(address => bool) public operators;
    uint64 public lastExecution;

    modifier onlyOperators() {
        if (msg.sender != owner && !operators[msg.sender]) {
            revert NotAllowedOperator();
        }
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _outputToken,
        IGmxRewardRouterV2 _rewardRouterV2,
        IGmxGlpRewardHandler _wrapper,
        IMimCauldronDistributor _distributor
    ) {
        operators[msg.sender] = true;

        rewardToken = _rewardToken;
        outputToken = _outputToken;
        rewardRouterV2 = _rewardRouterV2;
        wrapper = _wrapper;
        distributor = _distributor;
    }

    function claimable() external view returns (uint256) {
        return
            IGmxRewardTracker(rewardRouterV2.feeGmxTracker()).claimable(address(wrapper)) +
            IGmxRewardTracker(rewardRouterV2.feeGlpTracker()).claimable(address(wrapper));
    }

    function totalRewardsBalanceAfterClaiming() external view returns (uint256) {
        return
            rewardToken.balanceOf(address(wrapper)) +
            IGmxRewardTracker(rewardRouterV2.feeGmxTracker()).claimable(address(wrapper)) +
            IGmxRewardTracker(rewardRouterV2.feeGlpTracker()).claimable(address(wrapper));
    }

    function run(uint256 amountOutMin, bytes calldata data) external onlyOperators {
        wrapper.harvest();
        wrapper.swapRewards(amountOutMin, rewardToken, outputToken, address(distributor), data);
        distributor.distribute();
        lastExecution = uint64(block.timestamp);
    }

    function setDistributor(IMimCauldronDistributor _distributor) external onlyOwner {
        emit DistributorChanged(distributor, _distributor);
        distributor = _distributor;
    }

    function setOperator(address operator, bool status) external onlyOwner {
        operators[operator] = status;
        emit OperatorChanged(operator, status);
    }
}

