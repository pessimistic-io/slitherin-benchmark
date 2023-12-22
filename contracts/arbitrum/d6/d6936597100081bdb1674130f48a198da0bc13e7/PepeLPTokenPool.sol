//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeLPTokenPool } from "./IPepeLPTokenPool.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeLPTokenPool is IPepeLPTokenPool, Ownable2Step {
    using SafeERC20 for IERC20;
    IERC20 public immutable lpToken;

    mapping(address contract_ => bool) public approvedContract;

    event ContractApproved(address indexed contract_, bool indexed approved);
    event ContractRevoked(address indexed contract_, bool indexed approved);
    event ContractOperationFunded(address indexed contract_, uint256 amount);
    event AdminWithdrawal(address indexed admin, uint256 amount);

    constructor(address _lpToken) {
        lpToken = IERC20(_lpToken);
    }

    function approveContract(address contract_) external override onlyOwner {
        require(contract_ != address(0), "zero address");
        require(!approvedContract[contract_], "already approved");
        approvedContract[contract_] = true;
        emit ContractApproved(contract_, true);
    }

    function revokeContract(address contract_) external override onlyOwner {
        require(contract_ != address(0), "zero address");
        require(approvedContract[contract_], "not approved");
        approvedContract[contract_] = false;
        emit ContractRevoked(contract_, false);
    }

    function fundContractOperation(address contract_, uint256 amount) external override {
        require(approvedContract[contract_], "not approved");
        require(lpToken.balanceOf(address(this)) >= amount, "insufficient balance");
        lpToken.transfer(contract_, amount);
        emit ContractOperationFunded(contract_, amount);
    }

    function withdraw(uint256 amount) external override onlyOwner {
        require(lpToken.balanceOf(address(this)) >= amount, "insufficient balance");
        lpToken.transfer(owner(), amount);
        emit AdminWithdrawal(owner(), amount);
    }

    function retrieve(address _token) external override onlyOwner {
        require(_token != address(lpToken), "underlying token");
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "retrival failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

