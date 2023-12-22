// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./Ownable.sol";
import "./IERC20.sol";

// GLP RewardRouterV2 interface
interface IRewardRouterV2 {
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  }

contract AutoCompounding is AccessControl, Ownable { 

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IERC20 public constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
  IERC20 public constant SGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE); 

  IRewardRouterV2 public glpRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
  address public GLPManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
  address public vault;

  uint256 public slippage = 1; // in %

  event GlpPurchased(uint256 amountWethSpent, uint256 amountGlpPurchased);
  event VaultUpdated(address updater, address newVault);

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function compound(uint256 glpPerEtherPrice) public {
    require(msg.sender == vault, "Unauthorized");
    
    uint256 wethBalance = WETH.balanceOf(address(this));
    uint256 glpPurchaseAmount = wethBalance * glpPerEtherPrice/1e8;
    uint256 minAcceptableGlpAmount = glpPurchaseAmount * (100-slippage) / 100;

    WETH.approve(address(GLPManager), wethBalance);

    // buy GLP
    uint256 amountPurchased = glpRewardRouterV2.mintAndStakeGlp(
      address(WETH),           // token to buy GLP with
      wethBalance,             // amount of token to use for the purchase
      0,   // the minimum acceptable USD value of the GLP purchased
      minAcceptableGlpAmount   // the minimum acceptable GLP amount
    );

    uint256 wethBalanceAfter = WETH.balanceOf(address(this));

    emit GlpPurchased(wethBalance-wethBalanceAfter, amountPurchased);
  
    uint256 balance = GLP.balanceOf(address(this));
    if(balance == 0) {
      return; // nothing to do
    }
    SGLP.transfer(vault, balance);
  }

  // ADMIN functions

  function setVault(address _newVault) public onlyRole(ADMIN_ROLE) {
    vault = _newVault;
    emit VaultUpdated(msg.sender, vault);
  }

  function setGlpRewardRouter(address _newAddress) public onlyRole(ADMIN_ROLE) {
    glpRewardRouterV2 = IRewardRouterV2(_newAddress);
  }

  function setGLPManager(address _newAddress) external onlyRole(ADMIN_ROLE) {
    GLPManager = _newAddress;
  }

  function setSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE) {
    slippage = _slippage;
  }

  // emergency fund recovery 
  function recoverERC20(address _tokenAddress) public onlyRole(ADMIN_ROLE) {
    IERC20(_tokenAddress).transfer(msg.sender, IERC20(_tokenAddress).balanceOf(address(this)));
  }

  function recoverEther(address payable _to) public onlyRole(ADMIN_ROLE) payable {
    (bool sent,) = _to.call{ value: address(this).balance }("");
    require(sent, "failed to send ETH");
  }

}

