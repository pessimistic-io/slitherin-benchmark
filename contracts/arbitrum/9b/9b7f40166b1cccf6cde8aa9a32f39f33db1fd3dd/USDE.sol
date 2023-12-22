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
  * @notice        Obtain the net token value per unit
  * @return uint256   The net value per aToken
  */
  function shareNetWorth() public view virtual returns (uint256){
    //console.log("USDE.shareNetWorth totalNetWorth=",totalNetWorth());
    //console.log("USDE.shareNetWorth totalShare=",totalShare());
    return totalShare()<1e12?1e6:totalNetWorth()*1e18/totalShare();
  }

  /**
  * @notice        Obtain the net token value, whcih is constant at 1e6
  * @return uint256   The net value per aToken
  */
  function netWorth() external view virtual returns (uint256){
    return 1e6;
  }

  /**
  * @notice        Total supply of aTokens
  * @return uint256   Total supply
  */
  function totalShare() public view virtual returns (uint256){
    return super.totalSupply();
  }

  /**
  * @notice         Override totalSupply
  * @return uint256
  */
  function totalSupply() public view override returns (uint256){
    return super.totalSupply() * shareNetWorth() / 1e6;
  }

  /**
  * @notice          Override balanceOf
  * @param account   Account address
  * @return uint256
  */
  function balanceOf(address account) public view override returns (uint256){
    return shareNetWorth() * super.balanceOf(account) / 1e6;
  }

  /**
  * @notice        Override transfer
  * @param to      Target account
  * @param amount  Quantity
  * @return bool
  */
  function transfer(address to, uint256 amount) public override returns (bool){
    return super.transfer(to, amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice         Override allowance
  * @param owner    Source account
  * @param spender  Target account
  * @return uint256
  */
  function allowance(address owner, address spender) public view override returns (uint256) {
    return shareNetWorth() * super.allowance(owner,spender) /1e6;
  }

  /**
  * @notice         Override approve
  * @param spender  Target account
  * @param amount   Quantity
  * @return bool
  */
  function approve(address spender, uint256 amount) public override returns (bool) {
    return super.approve(spender,amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice         Override transferFrom
  * @param from     Source account
  * @param to       Target account
  * @param amount   Quantity
  * @return bool
  */
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    return super.transferFrom(from,to,amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice             Override increaseAllowance
  * @param spender      Target account
  * @param addedValue   Increase amount
  * @return bool
  */
  function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
    return super.increaseAllowance(spender,addedValue * 1e6 / shareNetWorth());
  }

  /**
  * @notice                 Override decreaseAllowance
  * @param spender          Target account
  * @param subtractedValue  Decrease amount
  * @return bool
  */
  function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
    return super.decreaseAllowance(spender,subtractedValue * 1e6 / shareNetWorth());
  }

  /**
  * @notice            Override mint
  * @param to          Target account
  * @param amount      Quantity
  */
  function mint(address to, uint256 amount) public override {
    super.mint(to, amount * 1e6 / shareNetWorth());
  }

  /**
  * @notice            Override burn
  * @param from        Target account
  * @param amount      QUantity
  */
  function burn(address from, uint256 amount) public override {
    super.burn(from, amount * 1e6 / shareNetWorth());
  }

}

