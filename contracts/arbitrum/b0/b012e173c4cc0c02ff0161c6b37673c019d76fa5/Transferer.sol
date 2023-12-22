// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";

contract Transferer {
  using SafeERC20 for IERC20;

  function transferERC20TokenFrom(
      address _erc20TokenAddress,
      address _from,
      address _to,
      uint256 _value
  ) internal {
      IERC20(_erc20TokenAddress).safeTransferFrom(_from, _to, _value);
  }

  function transferERC20Token(
      address _erc20TokenAddress,
      address _to,
      uint256 _value
  ) internal {
      IERC20(_erc20TokenAddress).safeTransfer(_to, _value);
  }

  function approveERC20Token(
      address _erc20TokenAddress,
      address _to,
      uint256 _value
  ) internal {
      IERC20(_erc20TokenAddress).safeApprove(_to, _value);
  }

  function transferETH(address _recepient, uint256 _value) internal {
      (bool success, ) = _recepient.call{value: _value}("");
      require(success, "Transfer Failed");
  }

  function transferERC20TokenOrETH(
      address _erc20TokenAddress,
      address _to,
      uint256 _value
  ) internal {
      if (_erc20TokenAddress == address(0)) {
          transferETH(_to, _value);
      } else {
          transferERC20Token(_erc20TokenAddress, _to, _value);
      }
  }

  function getERC20OrETHBalance(address _erc20TokenAddress) internal view returns (uint256) {
    if (_erc20TokenAddress == address(0)) {
      return address(this).balance;
    } else {
      IERC20 outToken = IERC20(_erc20TokenAddress);
      return outToken.balanceOf(address(this));
    }
  }

  function getERC20Allowance(
    address _erc20TokenAddress,
    address owner,
    address spender
  ) internal view returns (uint256) {
    IERC20 outToken = IERC20(_erc20TokenAddress);
    return outToken.allowance(owner, spender);
  }

  function transferERC20TokenFromOrCheckETH(
      address _contractAddress,
      address _from,
      address _to,
      uint256 _value
  ) internal {
      if (_contractAddress == address(0)) {
          require(
              msg.value == _value,
              "msg.value doesn't match needed amount"
          );
      } else {
          transferERC20TokenFrom(_contractAddress, _from, _to, _value);
      }
  }
}
