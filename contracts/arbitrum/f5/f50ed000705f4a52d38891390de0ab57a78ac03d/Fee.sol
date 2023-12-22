//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./TransferHelper.sol";
import "./IFee.sol";

contract Fee is IFee, Ownable {
    uint256 private fee;

    // pass parameter with _fee ether
    constructor(uint256 _fee) {
        fee = _fee;
    }

    event SetFee(address sender, uint256 fee);
    event Withdraw(address sender, address token, uint256 amount);

    // pass parameter with _fee ether
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
        emit SetFee(msg.sender, fee);
    }

    function getFee() external view returns (uint256) {
        return fee;
    }

    function withdraw(address _assetTokenERC20, uint256 amount)
        external
        onlyOwner
    {
        TransferHelper.safeTransfer(_assetTokenERC20, msg.sender, amount);
        emit Withdraw(msg.sender, _assetTokenERC20, amount);
    }
}

