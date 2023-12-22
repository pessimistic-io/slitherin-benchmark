//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeProxyLpToken } from "./IPepeProxyLpToken.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeProxyLpToken is IPepeProxyLpToken, ERC20, Ownable2Step {
    using SafeERC20 for IERC20;

    constructor() ERC20("PepeProxyLpToken", "PPLP") {}

    mapping(address contract_ => bool) public approvedContract;

    event ContractApproved(address indexed contract_, bool indexed approved);
    event ContractRevoked(address indexed contract_, bool indexed approved);

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

    function mint(address _to, uint256 _amount) external override onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external override {
        require(approvedContract[msg.sender] || msg.sender == owner(), "not approved");
        _burn(_from, _amount);
    }

    function retrieve(address _token) external override onlyOwner {
        require(_token != address(this), "underlying token");
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "retrival failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

