// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import "./IERC20.sol";

interface IKarsha is IERC20 {
  function mint(address _to, uint256 _amount) external;

  function burn(address _from, uint256 _amount) external;

  function index() external view returns (uint256);
  
  function balanceOfPANA(address _address) external view returns (uint256);

  function balanceFrom(uint256 _amount) external view returns (uint256);

  function balanceTo(uint256 _amount) external view returns (uint256);

  function transfer(address _to,uint256 _amount) external override returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool);
}

