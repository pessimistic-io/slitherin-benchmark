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
  * @notice           合约初始化
  * @param name_      代币名称
  * @param symbol_    代币标识
  */
  function initialize(string memory name_,string memory symbol_) external initializer {
    __EzToken_init(name_,symbol_);
  }

  /**
  * @notice          净值=总净值/总供应量
  * @return uint256  bToken的净值
  */
  function netWorth() external view returns(uint256){
    return totalSupply()<1e12?1e6:totalNetWorth()*1e18/totalSupply();
  }

  /**
  * @notice            总净值=金库总净值-aToken的总净值
  * @return uint256    bToken总净值
  */
  function totalNetWorth() public view virtual returns (uint256){
    return treasury.totalNetWorth()-treasury.matchedA()-treasury.pooledA();
  }

}

