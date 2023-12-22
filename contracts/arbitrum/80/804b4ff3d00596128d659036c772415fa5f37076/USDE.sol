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
  * @notice           合约初始化
  * @param name_      代币名称
  * @param symbol_    代币标识
  */
  function initialize(string memory name_,string memory symbol_) external initializer {
    __EzToken_init(name_,symbol_);
  }

  /**
  * @notice           总净值=未配对资金+已配对资金
  * @return uint256   aToken的总净值
  */
  function totalNetWorth() public view virtual returns (uint256){
    return treasury.pooledA() + treasury.matchedA();
  }

  /**
  * @notice        获取每份的净值
  * @return uint256   aToken每份的净值
  */
  function shareNetWorth() public view virtual returns (uint256){
    //console.log("EzatERC20.shareNetWorth totalNetWorth=",totalNetWorth());
    //console.log("EzatERC20.shareNetWorth totalShare=",totalShare());
    return totalShare()<1e12?1e6:totalNetWorth()*1e18/totalShare();
  }

  /**
  * @notice        获取净值,恒定为1e6
  * @return uint256   aToken的净值
  */
  function netWorth() external view virtual returns (uint256){
    return 1e6;
  }

  /**
  * @notice        aToken总份数
  * @return uint256   总份数
  */
  function totalShare() public view virtual returns (uint256){
    return super.totalSupply();
  }

  /**
  * @notice         重写totalSupply
  * @return uint256
  */
  function totalSupply() public view override returns (uint256){
    return super.totalSupply() * shareNetWorth() / 1e6;
  }

  /**
  * @notice          重写balanceOf
  * @param account   账户地址
  * @return uint256
  */
  function balanceOf(address account) public view override returns (uint256){
    return shareNetWorth() * super.balanceOf(account) / 1e6;
  }

  /**
  * @notice        重写transfer
  * @param to      目标账户
  * @param amount  数量
  * @return bool
  */
  function transfer(address to, uint256 amount) public override returns (bool){
    return super.transfer(to, amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice         重写allowance
  * @param owner    来源账户
  * @param spender  目标账户
  * @return uint256
  */
  function allowance(address owner, address spender) public view override returns (uint256) {
    return shareNetWorth() * super.allowance(owner,spender) /1e6;
  }

  /**
  * @notice         重写approve
  * @param spender  目标账户
  * @param amount   数量
  * @return bool
  */
  function approve(address spender, uint256 amount) public override returns (bool) {
    return super.approve(spender,amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice         重写transferFrom
  * @param from     来源账户
  * @param to       目标账户
  * @param amount   数量
  * @return bool
  */
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    return super.transferFrom(from,to,amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice             重写increaseAllowance
  * @param spender      目标账户
  * @param addedValue   增加量
  * @return bool
  */
  function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
    return super.increaseAllowance(spender,addedValue * 1e6 / shareNetWorth());
  }

  /**
  * @notice                 重写decreaseAllowance
  * @param spender          目标账户
  * @param subtractedValue  减少量
  * @return bool
  */
  function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
    return super.decreaseAllowance(spender,subtractedValue * 1e6 / shareNetWorth());
  }

  /**
  * @notice            重写mint
  * @param to          目标账户
  * @param amount      数量
  */
  function mint(address to, uint256 amount) public override {
    super.mint(to, amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice            重写burn
  * @param from        来源账户
  * @param amount      数量
  */
  function burn(address from, uint256 amount) public override {
    super.burn(from, amount * 1e6 / shareNetWorth());
  }

}

