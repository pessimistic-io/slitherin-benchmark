// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity >=0.8.0 <0.9.0;

interface IHLP {
  /**
   * ERRORS
   */
  error IHLP_onlyMinter();

  /**
   * States
   */
  function totalSupply() external view returns (uint256 _total);

  /**
   * Functions
   */
  function setMinter(address minter, bool isMinter) external;

  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;

  function approve(address _to, uint256 _amount) external;

  function balanceOf(address _account) external view returns (uint256 _amount);
  function decimals() external view returns (uint8 _decimals);
}
