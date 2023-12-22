// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./IERC721.sol";

interface IFlexiPunkTLD is IERC721 {

  function owner() external view returns(address);
  function royaltyFeeReceiver() external view returns(address);
  function royaltyFeeUpdater() external view returns(address);

  function mint(
    string memory _domainName,
    address _domainHolder,
    address _referrer
  ) external payable returns(uint256);

}

