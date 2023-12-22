// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.6;
pragma abicoder v2;

import "./IStargateReceiver.sol";
import "./IStargateRouter.sol";
import "./IERC20.sol";

import "./StakingRewards.sol";

contract StakingAfter is IStargateReceiver {
    StakingRewards public immutable stakingRewards;
    IERC20 public token;

    event LoopBack(uint256 amountLd);
    event senderInfo(uint16 _chainId, bytes _srcAddress);

    constructor(address _stakingRewardsAddress) {
        stakingRewards = StakingRewards(_stakingRewardsAddress);
    }

    bool paused;

    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256, /*_nonce*/
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external override {
        require(!paused, "Failed sgReceive due to pause");
        token = IERC20(_token);
        address receiverAddress = abi.decode(payload, (address));
        token.approve(address(stakingRewards), amountLD);
        stakingRewards.stakeFor(amountLD, receiverAddress);

        emit LoopBack(amountLD);
        emit senderInfo(_chainId, _srcAddress);
    }

    function pause(bool _paused) external {
        paused = _paused;
    }

    // be able to receive ether
    fallback() external payable {}

    receive() external payable {}
}

