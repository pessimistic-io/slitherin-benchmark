// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./console.sol";

import "./AbstractYieldingPool.sol";
import "./AddressesArbitrum.sol";
import "./IReader.sol";
import "./IRewardRouter.sol";
import "./IRewardTracker.sol";
import "./IRouter.sol";
import "./IGlpManager.sol";

contract GmxPool is AbstractYieldingPool {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  struct PushOptions {
    uint256 minUsdg;
    uint256 minGlp;
  }
  struct PullOptions {
    uint256 minOut;
  }
  struct ClaimRewardsOptions {
    bool shouldClaimGmx;
    bool shouldStakeGmx;
    bool shouldClaimEsGmx;
    bool shouldStakeEsGmx;
    bool shouldStakeMultiplierPoints;
    bool shouldClaimWeth;
    bool shouldConvertWethToEth;
  }

  //  Core Variables
  address private gmxRewardRouterV1Address;
  address private gmxRewardRouterV2Address;
  address private glpManagerAddress;
  address private gmxRouterAddress;
  address private gmxReaderAddress;

  IRewardRouter private rewardRouterV1;
  IRewardRouter private rewardRouterV2;
  EnumerableSet.AddressSet private tokenAddresses;

  //  ============================================================
  //  Initialisation
  //  ============================================================
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
      _disableInitializers();
  }

  function initialize(
    address _gmxRewardRouterV1Address,
    address _gmxRewardRouterV2Address,
    address[] memory _tokens,
    address _glpManagerAddress,
    address _gmxRouterAddress,
    address _gmxReaderAddress,
    address newOwner
  ) public initializer {
    __Ownable_init();
    __Pausable_init();
    initialisePool(_gmxRewardRouterV1Address, _gmxRewardRouterV2Address, _glpManagerAddress, _gmxRouterAddress, _gmxReaderAddress);
    addTokenAddresses(_tokens);
    transferOwnership(newOwner);
  }

  // ==============================================================================================
  /// Query Functions
  // ==============================================================================================
  /// @notice Returns a set of ADDRESSES of the erc20 tokens that are managed by the vault
  function getPoolTokens() override external view returns (address[] memory) {
    return tokenAddresses.values();
  }

  /// @notice Returns true if the token is managed 
  function isPoolToken(address token) override external view returns (bool) {
    return tokenAddresses.contains(token);
  }

  /// @notice Returns the tokens managed and amounts of each token managed
  function getPoolTokensValue() override external view returns (address[] memory, uint256[] memory) {
    address[] memory addresses = tokenAddresses.values();
    uint256[] memory tokenValues = new uint256[](addresses.length);

    for (uint index = 0; index < addresses.length; index++) {
      tokenValues[index] = IERC20Upgradeable(addresses[index]).balanceOf(address(this));
    }

    return (
      addresses,
      tokenValues
    );
  }

  function withdrawAll() external returns (address[] memory tokens, uint256[] memory actualTokenAmounts) {

  }

  // ==============================================================================================
  /// Contract Management Functions
  // ==============================================================================================
  function initialisePool(address _gmxRewardRouterV1Address, address _gmxRewardRouterV2Address, address _glpManagerAddress, address _gmxRouterAddress, address _gmxReaderAddress) private {
    gmxRewardRouterV1Address = _gmxRewardRouterV1Address;
    gmxRewardRouterV2Address = _gmxRewardRouterV2Address;
    glpManagerAddress = _glpManagerAddress;
    gmxRouterAddress = _gmxRouterAddress;
    gmxReaderAddress = _gmxReaderAddress;
    rewardRouterV1 = IRewardRouter(gmxRewardRouterV1Address);
    rewardRouterV2 = IRewardRouter(gmxRewardRouterV2Address);
  }

  /// @notice Clears the token addresses
  /// @dev note that this will not clear the underlying tokens
  function clearTokenAddress() external onlyOwner whenNotPaused {
    for (uint index = 0; index < tokenAddresses.length(); index++) {
      tokenAddresses.remove(tokenAddresses.at(index));
    }
  }

  /// @notice Clears the token addresses
  /// @dev note that this will not clear the underlying tokens
  function addTokenAddresses(address[] memory _tokens) private {
    /// Add gmx specific tokens
    tokenAddresses.add(Addresses.GLP_ADDRESS);
    tokenAddresses.add(Addresses.GMX_ADDRESS);
    tokenAddresses.add(Addresses.ESGMX_ADDRESS);
    for (uint index = 0; index < _tokens.length; index++) {
      tokenAddresses.add(_tokens[index]);
    }
  }

  // ==============================================================================================
  /// Protocol Transactional Functions
  // ==============================================================================================
  /// @notice Pushes tokens in the pool balance to the underlying protocol.
  /// @custom:todo add slippage protection to minUsdg
  function push(
    address assetAddress,
    uint256 amount,
    bytes memory options
  ) override external returns (uint256 actualTokenAmount) {
    PushOptions memory opts = _parsePushOptions(options);
    
    // Approve pool to access amount from this contract 
    SafeERC20Upgradeable.safeIncreaseAllowance(IERC20Upgradeable(assetAddress), glpManagerAddress, amount);

    uint256 glpAmount = rewardRouterV2.mintAndStakeGlp(assetAddress, amount, opts.minUsdg, opts.minGlp);

    emit Push(Addresses.GLP_ADDRESS, glpAmount);

    return glpAmount;
  }

  /// @notice withdraw the existing GLP and claims the rewards
  /// @param assetAddress the address of the token to be withdrawn
  /// @param amount amount in the asset token's denomination to be withdrawn
  /// @param options pull options
  /// @return actualTokenAmounts
  function pull(
      address assetAddress,
      uint256 amount,
      bytes memory options
  ) override external returns (uint256 actualTokenAmounts) {
    return _pull(assetAddress, amount, options);
  }

  /// @notice withdraw the existing GLP and claims the rewards
  /// @param assetAddress the address of the token to be withdrawn
  /// @param amount amount in the asset token's denomination to be withdrawn
  /// @param options pull options
  /// @return actualTokenAmounts
  function pullAndTransfer(
      address assetAddress,
      uint256 amount,
      bytes memory options,
      address recipient
  ) override external returns (uint256 actualTokenAmounts) {
    uint256 outputAmount = _pull(assetAddress, amount, options);

    //  Transfer to recipient
    IERC20Upgradeable(assetAddress).safeIncreaseAllowance(recipient, outputAmount);
    IERC20Upgradeable(assetAddress).transfer(recipient, outputAmount);

    return outputAmount;
  }

  /// @notice withdraw the existing GLP and claims the rewards
  /// @param assetAddress the address of the token to be withdrawn
  /// @param amount amount in the asset token's denomination to be withdrawn
  /// @param options pull options
  /// @return actualTokenAmounts
  function _pull(
      address assetAddress,
      uint256 amount,
      bytes memory options
  ) internal returns (uint256 actualTokenAmounts) {
    uint256 stakedGlpAmount = IRewardTracker(IRewardRouter(Addresses.GMX_REWARD_ROUTER_V2).stakedGlpTracker()).stakedAmounts(address(this));
    if (amount == 0 || stakedGlpAmount == 0) return 0;
    if (amount == type(uint256).max) {
      amount = stakedGlpAmount;
    }

    PullOptions memory opts = _parsePullOptions(options);
    uint256 amountGlpToWithdraw = _calculateAmountOfGlp(assetAddress, amount).mul(102).div(100); // Account for 2% slippage

    return rewardRouterV2.unstakeAndRedeemGlp(
          assetAddress,
          stakedGlpAmount < amountGlpToWithdraw ? stakedGlpAmount : amountGlpToWithdraw,
          opts.minOut,
          address(this)
        );
  }

  /// @notice Handle the GLP rewards according to the strategy. Claim esGMX + multiplier points and stake.
  /// @notice Claim WETH and swap to USDC paid as profit to the vault
  /// @return profit the amount of USDC received in exchange for the WETH claimed
  function claimRewards(
    bytes memory options
  ) override public returns (uint256) {
    ClaimRewardsOptions memory opts = _parseClaimRewardsOptions(options);

    //  Claims the rewards
    rewardRouterV1.handleRewards(
      opts.shouldClaimGmx,
      opts.shouldStakeGmx,
      opts.shouldClaimEsGmx,
      opts.shouldStakeEsGmx,
      opts.shouldStakeMultiplierPoints,
      opts.shouldClaimWeth,
      opts.shouldConvertWethToEth
    );

    /// @notice Converts WETH to USDC
    /// @custom:todo to account for slippage we will need an oracle to get WETH-USDC price
    /// @custom:todo this should be implemented in future phases
    /// @dev currently there is no slippage taken into context
    SafeERC20Upgradeable.safeIncreaseAllowance(IERC20Upgradeable(Addresses.WETH_ADDRESS), gmxRouterAddress, IERC20Upgradeable(Addresses.WETH_ADDRESS).balanceOf(address(this)));

    swap(Addresses.WETH_ADDRESS, Addresses.USDC_ADDRESS, IERC20Upgradeable(Addresses.WETH_ADDRESS).balanceOf(address(this)), address(this));

    //  Gets the usdc amount
    return IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this));
  }

  /// @notice compound the yield in the yield pool
  function compound() override public {
    rewardRouterV1.compound();
  }

  function swap(address inAddress, address outAddress, uint256 inAmount, address recipientAddress) public onlyOwner {
    address[] memory inOutAddresses = new address[](2);
    inOutAddresses[0] = inAddress;
    inOutAddresses[1] = outAddress;

    IRouter(gmxRouterAddress).swap( 
      inOutAddresses,
      inAmount, // amount of weth in
      0, // minimum usdc out
      recipientAddress
    );
  }

  // ==============================================================================================
  /// GMX Specific Functions
  // ==============================================================================================
  /// @notice parses the byte options into an PushOption struct
  function _parsePushOptions(bytes memory options) internal pure returns (PushOptions memory) {
    if (options.length == 0) return PushOptions({minUsdg: 0, minGlp: 0});

    require(options.length == 32 * 2, "Failed");
    return abi.decode(options, (PushOptions));
  }

  /// @notice parses the byte options into an PullOption struct
  function _parsePullOptions(bytes memory options) internal pure returns (PullOptions memory) {
    if (options.length == 0) return PullOptions({minOut: 0});

    require(options.length == 32 * 1, "Failed");
    return abi.decode(options, (PullOptions));
  }

  /// @notice parses the byte options into an ClaimRewardsOption struct
  function _parseClaimRewardsOptions(bytes memory options) internal pure returns (ClaimRewardsOptions memory) {
    require(options.length == 32 * 7, "Failed");
    return abi.decode(options, (ClaimRewardsOptions));
  }

  /// @custom:todo remove in production
  function calculateAmountOfGlp(address tokenIn, uint256 tokenInAmount) external view returns (uint256 amountOfGlp) {
    return _calculateAmountOfGlp(tokenIn, tokenInAmount);
  }

  /// @notice calculate the swap
  /// @return amountOfGlp the amount of token out in Glp
  function _calculateAmountOfGlp(address tokenIn, uint256 tokenInAmount) internal view returns (uint256 amountOfGlp) {
    (uint256 assetInUsdc,) = IReader(Addresses.GMX_READER).getAmountOut(IVault(Addresses.GMX_VAULT), tokenIn, Addresses.USDC_ADDRESS, tokenInAmount);

    // asset in usdc should be multiplied by glp + usdc token decimals
    return assetInUsdc.mul(10 ** (30 + 12)).div(IGlpManager(glpManagerAddress).getPrice(true));
  }
}
