//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeEsPegRewardPoolV2 } from "./IPepeEsPegRewardPoolV2.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeEsPegRewardPoolV2 is IPepeEsPegRewardPoolV2, Ownable2Step {
    using SafeERC20 for IERC20;
    IERC20 public immutable pegToken;

    address public stakingContractV1;
    mapping(address contract_ => bool) public approvedContract;

    event ContractApproved(address indexed contract_, bool indexed approved);
    event ContractRevoked(address indexed contract_, bool indexed approved);
    event ContractOperationFunded(address indexed contract_, uint256 amount);
    event AdminWithdrawal(address indexed admin, uint256 amount);
    event EsPegStakingContractUpdated(address indexed stakingContract);

    constructor(address _peg, address _stakingContractV1) {
        pegToken = IERC20(_peg);
        stakingContractV1 = _stakingContractV1;
    }

    ///@notice approve a contract to call fundContractOperation
    ///@param contract_ address of the contract to approve
    function approveContract(address contract_) external override onlyOwner {
        require(contract_ != address(0), "zero address");
        require(!approvedContract[contract_], "already approved");
        approvedContract[contract_] = true;
        emit ContractApproved(contract_, true);
    }

    ///@notice revoke a contract's approval to call fundContractOperation
    ///@param contract_ address of the contract to revoke approval
    function revokeContract(address contract_) external override onlyOwner {
        require(contract_ != address(0), "zero address");
        require(approvedContract[contract_], "not approved");
        approvedContract[contract_] = false;
        emit ContractRevoked(contract_, false);
    }

    ///@notice update the address of the esPeg staking contract.
    function updateStakingContract(address _staking) public override onlyOwner {
        stakingContractV1 = _staking;

        emit EsPegStakingContractUpdated(_staking);
    }

    ///@notice fund a contract operation. Transfers Peg to the contract.
    function fundContractOperation(uint256 amount) external override {
        require(approvedContract[msg.sender], "not approved");
        require(pegToken.balanceOf(address(this)) >= amount, "insufficient balance");
        require(pegToken.transfer(msg.sender, amount), "Transfer Failed");
        emit ContractOperationFunded(msg.sender, amount);
    }

    ///@notice backward compatibility with esPeg staking/vesting contract V1
    function allocatePegStaking(uint256 _amount) external override {
        require(msg.sender == stakingContractV1, "!staking");
        require(pegToken.balanceOf(address(this)) >= _amount, "Not enough Peg");
        require(pegToken.transfer(stakingContractV1, _amount), "Transfer Failed");

        emit ContractOperationFunded(stakingContractV1, _amount);
    }

    ///@notice withdraw Peg from the contract
    function withdraw(uint256 amount) external override onlyOwner {
        require(pegToken.balanceOf(address(this)) >= amount, "insufficient balance");
        require(pegToken.transfer(owner(), amount), "Transfer Failed");
        emit AdminWithdrawal(owner(), amount);
    }

    ///@notice retrieve tokens sent to the contract by mistake
    function retrieve(address _token) external override onlyOwner {
        require(_token != address(pegToken), "underlying token");
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "retrival failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

