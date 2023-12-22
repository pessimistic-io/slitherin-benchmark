// SPDX-License-Identifier: AGPL-3.0-or-later
// unstoppablefinance.org
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";

// GLP RewardRouterV2 interface
interface IRewardRouterV2 {
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  function handleRewards(
    bool _shouldClaimGmx,
    bool _shouldStakeGmx,
    bool _shouldClaimEsGmx,
    bool _shouldStakeEsGmx,
    bool _shouldStakeMultiplierPoints,
    bool _shouldClaimWeth,
    bool _shouldConvertWethToEth
  ) external;
}

interface IGlpManager {
  function getAum(bool maximise) external view returns (uint256);
}

interface IExchangeRateOracle { // Chainlink compatible
  function latestRoundData()
    external
    view
    returns (
      uint80, // roundId,
      int256, // answer,
      uint256, // startedAt,
      uint256, // updatedAt,
      uint80 // answeredInRound
    );
}

/*******************************************************************************************
 * 
 * @title Strategy for the Unstoppable GLP Autocompounder
 * 
 * @author unstoppablefinance.org
 * 
 * @notice Receives WETH from the GLP vault and compounds it into more GLP before sending
 *         it back to the vault.
 * 
 *******************************************************************************************/

contract AutocompoundStrategy is Ownable { 
  uint256 public constant PRICE_FEED_FRESHNESS = 24*60*60; // 24h after which price feed is considered stale

  IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IERC20 public constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
  IERC20 public constant SGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE); 
  IERC20 public constant rawGLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);

  IRewardRouterV2 public constant GlpRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
  IGlpManager public constant GLPManager = IGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

  IExchangeRateOracle public constant ethUsdOracle = IExchangeRateOracle(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

  address public vault;
  uint256 public acceptableSlippage = 1; // in %

  uint256 public totalPurchased;

  uint256 public sensibleMinimumWethToCompound = 1_000_000_000_000_000; // 0.001 WETH 

  event AcceptableSlippageUpdated(address updater, uint256 newAcceptableSlippage);
  event GlpPurchased(uint256 amountWethSpent, uint256 amountGlpPurchased);
  event Harvest(uint256 amount);
  event MintLockTimeUpdated(address updater, uint256 newMintLockTime);
  event SensibleMinimumWethToCompoundUpdated(address updater, uint256 newSensibleMinimum);
  event VaultUpdated(address updater, address newVault);

  constructor(address _vault) {
    vault = _vault;
  }

  // @dev sends any GLP balanceOf(address(this)) back to vault if possible
  // and purchases new GLP with all available WETH balance
  function compound() public {
    purchaseGlp();
    sendGlpToVault();
  }

  function purchaseGlp() public {
    uint256 wethBalance = WETH.balanceOf(address(this));
    if(wethBalance < sensibleMinimumWethToCompound) {
      return; // nothing to do
    }

    // approve WETH balance
    WETH.approve(address(GLPManager), wethBalance);

    // calculate acceptable minAmounts and slippage
    uint256 currentEthUsdPrice = getEthUsdExchangeRate();
    uint256 purchaseValue = wethBalance * currentEthUsdPrice / 1e8;  // exchange rate 8 decimals, weth 18, required 18, remove 8
    uint256 minAcceptableUsdValue = purchaseValue * (100-acceptableSlippage) / 100; // 18 decimals

    uint256 currentGlpPrice = GLPManager.getAum(true) / rawGLP.totalSupply() * 1e6; // 30 decimals - 18 = 12, + 6 = 18 decimals
    uint256 minAcceptableGlpAmount = minAcceptableUsdValue / currentGlpPrice * 1e18; // 18 decimals

    // buy GLP
    uint256 amountPurchased = GlpRewardRouterV2.mintAndStakeGlp(
      address(WETH),           // token to buy GLP with
      wethBalance,             // amount of token to use for the purchase
      minAcceptableUsdValue,   // the minimum acceptable USD value of the GLP purchased
      minAcceptableGlpAmount   // the minimum acceptable GLP amount
    );

    totalPurchased += amountPurchased;
    uint256 wethBalanceAfter = WETH.balanceOf(address(this));

    emit GlpPurchased(wethBalance-wethBalanceAfter, amountPurchased);
  }

  // @dev GLP is only transferable 15min+ after last mint
  // since this can be called as part of regular deposit/withdraw txs
  // we don't require/revert but simply return if the 15min haven't passed
  function sendGlpToVault() public {
    uint256 balance = GLP.balanceOf(address(this));
    if(balance == 0) {
      return; // nothing to do
    }
    SGLP.transfer(vault, balance);
  }

  function getEthUsdExchangeRate() public view returns (uint256) {
    (
      /*uint80 roundID*/,
      int price,
      /*uint256 startedAt*/,
      uint256 timestamp,
      /*uint80 answeredInRound*/
    ) = ethUsdOracle.latestRoundData();
    require(price > 0, "invalid price");
    require(timestamp > block.timestamp-PRICE_FEED_FRESHNESS, "price feed stale"); 
    return uint256(price);
  }

  // @dev compounds esGMX & multiplier points and 
  // sends weth to address(this).
  // We need it here since rewards accrue in the time between 
  // purchaseGlp() and sendGlpToVault() 15+ min later
  function harvest() public {
    uint256 balanceBefore = WETH.balanceOf(address(this));

    GlpRewardRouterV2.handleRewards(
      false, // _shouldClaimGmx
      false, // _shoudlStakeGmx
      true, // _shouldClaimEsGmx
      true, // _shouldStakeEsGmx
      true, // _shouldStakeMultiplierPoints
      true, // _shouldClaimWeth
      false // _shouldConvertWethToEth
    );

    uint256 balanceAfter = WETH.balanceOf(address(this));
    uint256 harvestedEthAmount = balanceAfter-balanceBefore;

    emit Harvest(harvestedEthAmount);
  }

  /*****************************
   * 
   *      ADMIN functions
   * 
   *****************************/
  function setVault(address _newVault) public onlyOwner {
    vault = _newVault;
    emit VaultUpdated(msg.sender, vault);
  }

  function setAcceptableSlippage(uint256 _newAcceptableSlippage) public onlyOwner {
    acceptableSlippage = _newAcceptableSlippage;
    emit AcceptableSlippageUpdated(msg.sender, acceptableSlippage);
  }

  function setSensibleMinimumWethToCompound(uint _newValue) public onlyOwner {
    sensibleMinimumWethToCompound = _newValue;
    emit SensibleMinimumWethToCompoundUpdated(msg.sender, sensibleMinimumWethToCompound);
  }


  // emergency recover
  function recover(address _tokenAddress) public onlyOwner {
    IERC20(_tokenAddress).transfer(msg.sender, IERC20(_tokenAddress).balanceOf(address(this)));
  }

  function recoverETH(address payable _to) public onlyOwner payable {
    (bool sent,) = _to.call{ value: address(this).balance }("");
    require(sent, "failed to send ETH");
  }
}
