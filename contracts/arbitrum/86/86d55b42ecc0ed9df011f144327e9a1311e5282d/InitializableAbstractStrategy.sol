// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

abstract contract InitializableAbstractStrategy is
  ReentrancyGuardUpgradeable,
  OwnableUpgradeable
{
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  event PTokenAdded(address indexed _asset, address _pToken);
  event PTokenRemoved(address indexed _asset, address _pToken);
  event Deposit(address indexed _asset, address _pToken, uint256 _amount);
  event Withdrawal(address indexed _asset, address _pToken, uint256 _amount);
  event RewardTokenCollected(
    address recipient,
    address rewardToken,
    uint256 amount
  );
  event RewardTokenAddressesUpdated(
    address[] _oldAddresses,
    address[] _newAddresses
  );
  event HarvesterAddressesUpdated(
    address _oldHarvesterAddress,
    address _newHarvesterAddress
  );

  // Core address for the given platform
  address public platformAddress;

  address public vaultAddress;

  // asset => pToken (Platform Specific Token Address)
  mapping(address => address) public assetToPToken;

  // Full list of all assets supported here
  address[] internal assetsMapped;

  //TODO DELETE
  // Deprecated: Reward token address
  // slither-disable-next-line constable-states
  address public _deprecated_rewardTokenAddress;

  //TODO DELETE
  // Deprecated: now resides in Harvester's rewardTokenConfigs
  // slither-disable-next-line constable-states
  uint256 public _deprecated_rewardLiquidationThreshold;

  // Address of the one address allowed to collect reward tokens
  address public harvesterAddress;

  // Reward token addresses
  address[] public rewardTokenAddresses;

  //TODO DELETE
  // Reserved for future expansion
  int256[98] private _reserved;

  /// @notice UniswapV2 Router address
  address public router;

  /// @notice usdc address
  address public primaryStableAddress;

  uint256 constant MAX_UINT =
    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  function _initialize(
    address _primaryStableAddress,
    address _platformAddress,
    address _vaultAddress,
    address _router,
    address[] calldata _rewardTokenAddresses,
    address[] memory _assets,
    address[] memory _pTokens
  ) internal {
    __ReentrancyGuard_init();
    __Ownable_init();

    primaryStableAddress = _primaryStableAddress;
    platformAddress = _platformAddress;
    vaultAddress = _vaultAddress;
    rewardTokenAddresses = _rewardTokenAddresses;
    router = _router;

    uint256 assetCount = _assets.length;
    require(assetCount == _pTokens.length, "Invalid input arrays");
    for (uint256 i = 0; i < assetCount; i++) {
      _setPTokenAddress(_assets[i], _pTokens[i]);
    }
  }

  /**
   * @dev Collect accumulated reward token and send to Vault.
   */
  function collectRewardTokens() external virtual onlyHarvester nonReentrant {
    _collectRewardTokens();
  }

  function _collectRewardTokens() internal {
    for (uint256 i = 0; i < rewardTokenAddresses.length; i++) {
      IERC20 rewardToken = IERC20(rewardTokenAddresses[i]);
      uint256 balance = rewardToken.balanceOf(address(this));
      emit RewardTokenCollected(
        harvesterAddress,
        rewardTokenAddresses[i],
        balance
      );
      rewardToken.safeTransfer(harvesterAddress, balance);
    }
  }

  /**
   * @dev Verifies that the caller is the Vault.
   */
  modifier onlyVault() {
    require(msg.sender == vaultAddress, "Caller is not the Vault");
    _;
  }

  /**
   * @dev Verifies that the caller is the Harvester.
   */
  modifier onlyHarvester() {
    require(msg.sender == harvesterAddress, "Caller is not the Harvester");
    _;
  }

  /**
   * @dev Throws if called by any address other than the Vault.
   */
  modifier onlyVaultOrOwner() {
    require(
      msg.sender == vaultAddress || msg.sender == owner(),
      "Caller is not the Vault or Owner"
    );
    _;
  }

  /**
   * @dev Set the reward token addresses.
   * @param _rewardTokenAddresses Address array of the reward token
   */
  function setRewardTokenAddresses(
    address[] calldata _rewardTokenAddresses
  ) external onlyOwner {
    for (uint256 i = 0; i < _rewardTokenAddresses.length; i++) {
      require(
        _rewardTokenAddresses[i] != address(0),
        "Can not set an empty address as a reward token"
      );
    }

    emit RewardTokenAddressesUpdated(
      rewardTokenAddresses,
      _rewardTokenAddresses
    );
    rewardTokenAddresses = _rewardTokenAddresses;
  }

  /**
   * @dev Set the router address.
   * @param _router Address of the router
   */
  function setRouter(address _router) external onlyOwner {
    require(_router != address(0), "router address shouldn't be empty.");
    router = _router;
  }

  /**
   * @dev Set the primary stablecoin address.
   * @param _primaryStable Address of the stablecoin
   */
  function setPrimaryStable(address _primaryStable) external onlyOwner {
    require(_primaryStable != address(0), "PrimaryStable should not be empty.");
    primaryStableAddress = _primaryStable;
  }

  /**
   * @dev Get the reward token addresses.
   * @return address[] the reward token addresses.
   */
  function getRewardTokenAddresses() external view returns (address[] memory) {
    return rewardTokenAddresses;
  }

  /**
   * @dev Provide support for asset by passing its pToken address.
   *      This method can only be called by the system Owner
   * @param _asset    Address for the asset
   * @param _pToken   Address for the corresponding platform token
   */
  function setPTokenAddress(
    address _asset,
    address _pToken
  ) external onlyOwner {
    _setPTokenAddress(_asset, _pToken);
  }

  /**
   * @dev Remove a supported asset by passing its index.
   *      This method can only be called by the system Owner
   * @param _assetIndex Index of the asset to be removed
   */
  function removePToken(uint256 _assetIndex) external onlyOwner {
    require(_assetIndex < assetsMapped.length, "Invalid index");
    address asset = assetsMapped[_assetIndex];
    address pToken = assetToPToken[asset];

    if (_assetIndex < assetsMapped.length - 1) {
      assetsMapped[_assetIndex] = assetsMapped[assetsMapped.length - 1];
    }
    assetsMapped.pop();
    assetToPToken[asset] = address(0);

    emit PTokenRemoved(asset, pToken);
  }

  /**
   * @dev Provide support for asset by passing its pToken address.
   *      Add to internal mappings and execute the platform specific,
   * abstract method `_abstractSetPToken`
   * @param _asset    Address for the asset
   * @param _pToken   Address for the corresponding platform token
   */
  function _setPTokenAddress(address _asset, address _pToken) internal {
    require(assetToPToken[_asset] == address(0), "pToken already set");
    require(_asset != address(0) && _pToken != address(0), "Invalid addresses");

    assetToPToken[_asset] = _pToken;
    assetsMapped.push(_asset);

    emit PTokenAdded(_asset, _pToken);

    _abstractSetPToken(_asset, _pToken);
  }

  /**
  * @dev Return pToken address by asset parameter
   * abstract method "_getPToken"
   * @param _asset    Address for the asset
   */
  function _getPToken(address _asset) internal virtual view returns (address) {
    require(assetToPToken[_asset] != address(0), "pToken does not exist");
    return assetToPToken[_asset];
    }

  /**
   * @dev Transfer token to owner. Intended for recovering tokens stuck in
   *      strategy contracts, i.e. mistaken sends.
   * @param _asset Address for the asset
   * @param _amount Amount of the asset to transfer
   */
  function transferToken(address _asset, uint256 _amount) public onlyOwner {
    IERC20(_asset).safeTransfer(owner(), _amount);
  }

  /**
   * @dev Set the reward token addresses.
   * @param _harvesterAddress Address of the harvester
   */
  function setHarvesterAddress(address _harvesterAddress) external onlyOwner {
    harvesterAddress = _harvesterAddress;
    emit HarvesterAddressesUpdated(harvesterAddress, _harvesterAddress);
  }

  /***************************************
                 Abstract
    ****************************************/

  function _abstractSetPToken(address _asset, address _pToken) internal virtual;

  function safeApproveAllTokens() external virtual;

  /**
   * @dev Deposit an amount of asset into the platform
   * @param _asset               Address for the asset
   * @param _amount              Units of asset to deposit
   */
  function deposit(address _asset, uint256 _amount) external virtual;

  /**
   * @dev Deposit balance of all supported assets into the platform
   */
  function depositAll() external virtual;

  /**
   * @dev Withdraw an amount of asset from the platform.
   * @param _recipient         Address to which the asset should be sent
   * @param _asset             Address of the asset
   * @param _amount            Units of asset to withdraw
   */
  function withdraw(
    address _recipient,
    address _asset,
    uint256 _amount
  ) external virtual;

  /**
   * @dev Withdraw all assets from strategy sending assets to Vault.
   */
  function withdrawAll() external virtual;

  /**
   * @dev Get the total asset value held in the platform.
   *      This includes any interest that was generated since depositing.
   * @return balance    Total value of the asset in the platform
   */
  function checkBalance() external view virtual returns (uint256 balance);

  /**
   * @dev Check if an asset is supported.
   * @param _asset    Address of the asset
   * @return bool     Whether asset is supported
   */
  function supportsAsset(address _asset) external view virtual returns (bool);
}

