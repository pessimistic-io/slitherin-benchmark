//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./TransferHelper.sol";

contract Fee is Ownable {
    uint256 public constant FEE_DIVIDER = 10_000;
    uint256 private fee;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    event SetFee(address sender, uint256 fee);
    event Withdraw(address sender, address token, uint256 amount);

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
        emit SetFee(msg.sender, fee);
    }

    function getFee() external view returns (uint256) {
        return fee;
    }

    function calculate(uint256 inputAmount) external view returns (uint256) {
        require(inputAmount > 0, "Amount must be greater than 0");
        return (inputAmount * fee) / FEE_DIVIDER;
    }

    function withdraw(
        address _assetTokenERC20,
        uint256 amount
    ) external onlyOwner {
        TransferHelper.safeTransfer(_assetTokenERC20, msg.sender, amount);
        emit Withdraw(msg.sender, _assetTokenERC20, amount);
    }
}

