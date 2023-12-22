// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IFirstTypeNestedStrategies.sol";
import "./Ownable.sol";

contract SelectNestedRoute is Ownable {
    using SafeERC20 for IERC20;

    address immutable firstTypeNestedStrategies;
    address private nodes;

    modifier onlyAllowed() {
        require(msg.sender == owner() || msg.sender == nodes, 'You must be the owner.');
        _;
    }

    constructor(address firstTypeNestedStrategies_) {
        firstTypeNestedStrategies = firstTypeNestedStrategies_;
    }

    function setNodes(address nodes_) public onlyOwner {
        nodes = nodes_;
    }

    /**
     * @param provider_ Value: 0 - Yearn and Reaper nested strategies
    */
    function deposit(address user_, address token_, address vaultAddress_, uint256 amount_, uint8 provider_) external onlyAllowed returns (uint256 sharesAmount) {
        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);
        if (provider_ == 0) {
            _approve(token_, address(firstTypeNestedStrategies), amount_);
            sharesAmount = IFirstTypeNestedStrategies(firstTypeNestedStrategies).deposit(user_, token_, vaultAddress_, amount_, msg.sender);
        }
    }

    /**
     * @param provider_ Value: 0 - Yearn and Reaper nested strategies
    */
    function withdraw(address user_, address tokenOut_, address vaultAddress_, uint256 sharesAmount_, uint8 provider_) external onlyAllowed returns (uint256 amountTokenDesired) {
        IERC20(vaultAddress_).safeTransferFrom(msg.sender, address(this), sharesAmount_);
        if (provider_ == 0) {
            _approve(vaultAddress_, address(firstTypeNestedStrategies), sharesAmount_);
            amountTokenDesired = IFirstTypeNestedStrategies(firstTypeNestedStrategies).withdraw(user_, tokenOut_, vaultAddress_, sharesAmount_, msg.sender);
        }
    }

    /**
     * @notice Approve of a token
     * @param token_ Address of the token wanted to be approved
     * @param spender_ Address that is wanted to be approved to spend the token
     * @param amount_ Amount of the token that is wanted to be approved.
     */
    function _approve(address token_, address spender_, uint256 amount_) internal {
        IERC20(token_).safeApprove(spender_, 0);
        IERC20(token_).safeApprove(spender_, amount_);
    }
}
