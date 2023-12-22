// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EzToken.sol";
//import "hardhat/console.sol";

contract USDEV1 is Initializable, EzTokenV1 {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
  * @notice           Contract Initialization
  * @param name_      Token Name
  * @param symbol_    Token Symbol
  */
  function initialize(string memory name_,string memory symbol_) external initializer {
    __EzToken_init(name_,symbol_);
  }

  /**
  * @notice           Total net value = Unmatched funds + Matched funds
  * @return uint256   Total net value of aToken
  */
  function totalNetWorth() public view virtual returns (uint256){
    return vault.pooledA() + vault.matchedA();
  }

  /**
  * @notice        Net Token Value = Total Net Token Value / Total Token Supply
  * @return uint256   The net value per aToken
  */
  function netWorth() external view virtual returns (uint256){
    return totalSupply()<1e12?1e6:totalNetWorth()*1e18/totalSupply();
  }

}

