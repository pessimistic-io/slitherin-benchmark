// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ERC20.sol";

contract MatrixTreasuryDogechain is Ownable {
    using SafeERC20 for IERC20;

    address public accountant;

    struct Withdrawal {
      uint amount;
      address token;
      uint time;
      bool reviewed;
    }

    uint counter = 0;

    mapping(uint => Withdrawal) public withdrawals;

    function viewWithdrawal(uint index) public view returns (uint, address, uint, bool) {
      Withdrawal memory receipt = withdrawals[index];
      return(receipt.amount, receipt.token, receipt.time, receipt.reviewed);
    }

    function markReviewed(uint index) public returns (bool) {
      require(msg.sender == accountant, "not authorized");
      withdrawals[index].reviewed = true;
      return true;
    }

    function withdrawTokens(address _token, address _to, uint256 _amount) external onlyOwner {
      withdrawals[counter] = Withdrawal(_amount, _token, block.timestamp, false);
      counter++;
      IERC20(_token).safeTransfer(_to, _amount);
    }

    function withdrawNative(address payable _to, uint256 _amount) external onlyOwner {
      withdrawals[counter] = Withdrawal(_amount, address(0), block.timestamp, false);
      counter++;
      _to.transfer(_amount);
    }

    function setAccountant(address _addr) public onlyOwner returns (bool) {
      accountant = _addr;
      return true;
    }

    receive () external payable {}
}

