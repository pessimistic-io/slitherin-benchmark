// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC1155 } from "./IERC1155.sol";

import { LibSweep, PaymentTokenNotGiven } from "./LibSweep.sol";

import { SettingsBitFlag } from "./SettingsBitFlag.sol";
import { ITroveMarketplace } from "./ITroveMarketplace.sol";
import { IShiftSweeper } from "./IShiftSweeper.sol";
import { BuyError } from "./BuyError.sol";
import { MultiTokenBuyOrder, BuyOrder } from "./BuyOrder.sol";

import { WithOwnership } from "./LibOwnership.sol";

contract BaseSweepFacet is WithOwnership {
  using SafeERC20 for IERC20;

  function sweepFee() public view returns (uint256) {
    return LibSweep.DS().sweepFee;
  }

  function feeBasisPoints() public pure returns (uint256) {
    return LibSweep.FEE_BASIS_POINTS;
  }

  function calculateFee(uint256 _amount) external view returns (uint256) {
    return LibSweep._calculateFee(_amount);
  }

  function calculateAmountAmountWithoutFees(uint256 _amountWithFee)
    external
    view
    returns (uint256)
  {
    return LibSweep._calculateAmountWithoutFees(_amountWithFee);
  }

  function setFee(uint256 _fee) external onlyOwner {
    LibSweep.DS().sweepFee = _fee;
  }

  function getFee() external view returns (uint256) {
    return LibSweep.DS().sweepFee;
  }

  function _approveERC20TokenToContract(
    IERC20 _token,
    address _contract,
    uint256 _amount
  ) internal {
    _token.safeApprove(address(_contract), uint256(_amount));
  }

  function approveERC20TokenToContract(
    IERC20 _token,
    address _contract,
    uint256 _amount
  ) external onlyOwner {
    _approveERC20TokenToContract(_token, _contract, _amount);
  }

  // rescue functions
  function transferETHTo(address payable _to, uint256 _amount)
    external
    onlyOwner
  {
    _to.transfer(_amount);
  }

  function transferERC20TokenTo(
    IERC20 _token,
    address _address,
    uint256 _amount
  ) external onlyOwner {
    _token.safeTransfer(address(_address), uint256(_amount));
  }

  function transferERC721To(
    IERC721 _token,
    address _to,
    uint256 _tokenId
  ) external onlyOwner {
    _token.safeTransferFrom(address(this), _to, _tokenId);
  }

  function transferERC1155To(
    IERC1155 _token,
    address _to,
    uint256[] calldata _tokenIds,
    uint256[] calldata _amounts,
    bytes calldata _data
  ) external onlyOwner {
    _token.safeBatchTransferFrom(
      address(this),
      _to,
      _tokenIds,
      _amounts,
      _data
    );
  }
}

