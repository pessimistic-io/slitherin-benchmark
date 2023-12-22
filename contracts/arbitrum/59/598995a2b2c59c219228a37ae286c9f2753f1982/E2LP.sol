// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EzToken.sol";
//import "hardhat/console.sol";

contract E2LPV1 is Initializable, EzTokenV1{

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
  * @notice          Net Token Value = Total Net Token Value / Total Token Supply
  * @return uint256  Net Value of bToken
  */
  function netWorth() external view returns(uint256){
    return totalSupply()<1e16?1e6:totalNetWorth()*1e18/totalSupply();
  }

  /**
  * @notice            Total Net Token Value = Total Net Token Value of the Vault - Total Net Token Value of aToken
  * @return uint256    Total Net Value of bToken
  */
  function totalNetWorth() public view virtual returns (uint256){
    return vault.totalNetWorth()-vault.matchedA()-vault.pooledA();
  }

}

