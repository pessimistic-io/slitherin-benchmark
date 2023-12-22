//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IEsPepeToken } from "./IEsPepeToken.sol";
import { IPepeEsPegRewardPool } from "./IPepeEsPegRewardPool.sol";
import { IPepeEsPegStaking } from "./IPepeEsPegStaking.sol";
import { IPepeEsPegLockUp } from "./IPepeEsPegLockUp.sol";

contract PepeEsPegRewardPool is IPepeEsPegRewardPool, Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable pegToken; //reward token
    IPepeEsPegStaking public stakingContract; //espeg staking contract
    IPepeEsPegLockUp public lockLPcontract; // espeg lockup contract for lp;

    event EsPegStakingAllocated(address indexed stakingContract, uint256 amount);
    event EsPegLockingAllocated(address indexed lockLPcontract, uint256 amount);
    event PegWithdrawn(address indexed owner, uint256 amount);
    event EsPegStakingContractUpdated(address indexed stakingContract);
    event EsPegLockingContractUpdated(address indexed lockLPcontract);

    constructor(address pegToken_, address staking_, address lockLp_) {
        pegToken = IERC20(pegToken_);
        stakingContract = IPepeEsPegStaking(staking_);
        lockLPcontract = IPepeEsPegLockUp(lockLp_);
    }

    function allocatePegStaking(uint256 _amount) external override {
        require(msg.sender == address(stakingContract), "!staking");
        require(pegToken.balanceOf(address(this)) >= _amount, "Not enough Peg");
        require(pegToken.transfer(address(stakingContract), _amount), "Transfer Failed");

        emit EsPegStakingAllocated(address(stakingContract), _amount);
    }

    function allocatePegLocking(uint256 _amount) external override {
        require(msg.sender == address(lockLPcontract), "!lockLp");
        require(pegToken.balanceOf(address(this)) >= _amount, "Not enough Peg");
        require(pegToken.transfer(address(lockLPcontract), _amount), "Transfer Failed");

        emit EsPegLockingAllocated(address(lockLPcontract), _amount);
    }

    function withdrawPeg(uint256 amount) external onlyOwner {
        require(amount != 0, "!amount");
        require(pegToken.balanceOf(address(this)) >= amount, "!balance");
        require(pegToken.transfer(owner(), amount), "withdrawal failed");

        emit PegWithdrawn(owner(), amount);
    }

    function updateStakingContract(address _staking) public override onlyOwner {
        require(_staking != address(0), "!Invalid address");
        stakingContract = IPepeEsPegStaking(_staking);

        emit EsPegStakingContractUpdated(_staking);
    }

    function updateLockUpContract(address _lockUp) public override onlyOwner {
        require(_lockUp != address(0), "!Invalid address");
        lockLPcontract = IPepeEsPegLockUp(_lockUp);

        emit EsPegLockingContractUpdated(_lockUp);
    }

    /// @dev retrieve stuck tokens
    function retrieve(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "Retrieval Failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

