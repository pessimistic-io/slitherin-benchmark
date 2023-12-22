// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Metadata.sol";
import "./ERC20Permit.sol";
import "./ERC20Receiver.sol";
import "./ERC20Safer.sol";
import "./ERC165.sol";
import "./Holographable.sol";

interface IFractionToken is
  ERC165,
  ERC20,
  ERC20Burnable,
  ERC20Metadata,
  ERC20Receiver,
  ERC20Safer,
  ERC20Permit,
  Holographable
{
  function mint(address recipient, uint256 amount) external;

  function burn(address collateralRecipient, uint256 amount) external;

  function afterBurn(address collateralRecipient, uint256 amount) external returns (bool success);

  function onAllowance(address account, address operator, uint256 amount) external view returns (bool success);

  function isApprovedOperator(address operator) external view returns (bool approved);

  function getBurnFeeBp() external view returns (uint256 burnFeeBp);

  function getCollateral() external view returns (address collateral);

  function setApproveOperator(address operator, bool approved) external;

  function setBurnFeeBp(uint256 burnFeeBp) external;

  function setCollateral(address collateralAddress) external;
}

