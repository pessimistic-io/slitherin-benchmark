// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

import "./IOreoBoosterConfig.sol";
import "./IOreoSwapNFT.sol";

contract OreoBoosterConfig is IOreoBoosterConfig, Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  struct OreoBoosterNFTInfo {
    address nftAddress;
    uint256 tokenId;
  }

  struct OreoBoosterEnergyInfo {
    uint256 maxEnergy;
    uint256 currentEnergy;
    uint256 boostBps;
    uint256 updatedAt;
  }

  struct CategoryEnergyInfo {
    uint256 maxEnergy;
    uint256 boostBps;
    uint256 updatedAt;
  }

  struct OreoBoosterNFTParams {
    address nftAddress;
    uint256 nftTokenId;
    uint256 maxEnergy;
    uint256 boostBps;
  }

  struct CategoryNFTParams {
    address nftAddress;
    uint256 nftCategoryId;
    uint256 maxEnergy;
    uint256 boostBps;
  }

  struct OreoBoosterAllowance {
    address nftAddress;
    uint256 nftTokenId;
    bool allowance;
  }

  struct OreoBoosterAllowanceParams {
    address stakingToken;
    OreoBoosterAllowance[] allowance;
  }

  struct CategoryAllowance {
    address nftAddress;
    uint256 nftCategoryId;
    bool allowance;
  }

  struct CategoryAllowanceParams {
    address stakingToken;
    CategoryAllowance[] allowance;
  }

  uint256 public constant VERSION = 0;

  mapping(address => mapping(uint256 => OreoBoosterEnergyInfo)) public oreoboosterEnergyInfo;
  mapping(address => CategoryEnergyInfo) public externalboosterEnergyInfo;
  mapping(address => mapping(uint256 => CategoryEnergyInfo)) public categoryEnergyInfo;

  mapping(address => mapping(address => mapping(uint256 => bool))) public oreoboosterNftAllowanceConfig;
  mapping(address => mapping(address => mapping(uint256 => bool))) public categoryNftAllowanceConfig;

  mapping(address => bool) public override stakeTokenAllowance;

  mapping(address => bool) public override callerAllowance;

  event UpdateCurrentEnergy(
    address indexed nftAddress,
    uint256 indexed nftTokenId,
    uint256 indexed updatedCurrentEnergy
  );
  event SetStakeTokenAllowance(address indexed stakingToken, bool isAllowed);
  event SetOreoBoosterNFTEnergyInfo(
    address indexed nftAddress,
    uint256 indexed nftTokenId,
    uint256 maxEnergy,
    uint256 currentEnergy,
    uint256 boostBps
  );
  event SetExternalBoosterNFTEnergyInfo(address indexed nftAddress, uint256 maxEnergy, uint256 boostBps);
  event SetCallerAllowance(address indexed caller, bool isAllowed);
  event SetOreoBoosterNFTAllowance(
    address indexed stakeToken,
    address indexed nftAddress,
    uint256 indexed nftTokenId,
    bool isAllowed
  );
  event SetCategoryNFTEnergyInfo(
    address indexed nftAddress,
    uint256 indexed nftCategoryId,
    uint256 maxEnergy,
    uint256 boostBps
  );
  event SetCategoryNFTAllowance(
    address indexed stakeToken,
    address indexed nftAddress,
    uint256 indexed nftCategoryId,
    bool isAllowed
  );

  /// @notice only eligible caller can continue the execution
  modifier onlyCaller() {
    require(callerAllowance[msg.sender], "OreoBoosterConfig::onlyCaller::only eligible caller");
    _;
  }

  /// @notice getter function for energy info
  /// @dev check if the oreobooster energy existed,
  /// if not, it should be non-preminted version, so use categoryEnergyInfo to get a current, maxEnergy instead
  function energyInfo(address _nftAddress, uint256 _nftTokenId)
    public
    view
    override
    returns (
      uint256 maxEnergy,
      uint256 currentEnergy,
      uint256 boostBps
    )
  {
    CategoryEnergyInfo memory externalboosterInfo = externalboosterEnergyInfo[_nftAddress];

    // if there is no preset oreobooster energy info, use preset in category info
    // presume that it's not a preminted nft
    if (externalboosterInfo.updatedAt != 0) {
      return (externalboosterInfo.maxEnergy, externalboosterInfo.maxEnergy, externalboosterInfo.boostBps);
    }
    OreoBoosterEnergyInfo memory oreoboosterInfo = oreoboosterEnergyInfo[_nftAddress][_nftTokenId];
    // if there is no preset oreobooster energy info, use preset in category info
    // presume that it's not a preminted nft
    if (oreoboosterInfo.updatedAt == 0) {
      uint256 categoryId = IOreoSwapNFT(_nftAddress).oreoswapNFTToCategory(_nftTokenId);
      CategoryEnergyInfo memory categoryInfo = categoryEnergyInfo[_nftAddress][categoryId];
      return (categoryInfo.maxEnergy, categoryInfo.maxEnergy, categoryInfo.boostBps);
    }
    // if there is an updatedAt, it's a preminted nft
    return (oreoboosterInfo.maxEnergy, oreoboosterInfo.currentEnergy, oreoboosterInfo.boostBps);
  }

  /// @notice function for updating a curreny energy of the specified nft
  /// @dev Only eligible caller can freely update an energy
  /// @param _nftAddress a composite key for nft
  /// @param _nftTokenId a composite key for nft
  /// @param _energyToBeConsumed an energy to be consumed
  function consumeEnergy(
    address _nftAddress,
    uint256 _nftTokenId,
    uint256 _energyToBeConsumed
  ) external override onlyCaller {
    require(_nftAddress != address(0), "OreoBoosterConfig::consumeEnergy::_nftAddress must not be address(0)");
    OreoBoosterEnergyInfo storage energy = oreoboosterEnergyInfo[_nftAddress][_nftTokenId];

    if (energy.updatedAt == 0) {
      uint256 categoryId = IOreoSwapNFT(_nftAddress).oreoswapNFTToCategory(_nftTokenId);
      CategoryEnergyInfo memory categoryEnergy = categoryEnergyInfo[_nftAddress][categoryId];
      require(categoryEnergy.updatedAt != 0, "OreoBoosterConfig::consumeEnergy:: invalid nft to be updated");
      energy.maxEnergy = categoryEnergy.maxEnergy;
      energy.boostBps = categoryEnergy.boostBps;
      energy.currentEnergy = categoryEnergy.maxEnergy;
    }

    energy.currentEnergy = energy.currentEnergy.sub(_energyToBeConsumed);
    energy.updatedAt = block.timestamp;

    emit UpdateCurrentEnergy(_nftAddress, _nftTokenId, energy.currentEnergy);
  }

  /// @notice set external nft energy info
  /// @dev only owner can call this function
  /// @param _param a OreoBoosterNFTParams {nftAddress, nftTokenId, maxEnergy, boostBps}

  function setExternalTokenEnergyInfo(address _externalNft, CategoryEnergyInfo calldata _param) external onlyOwner {
    require(_externalNft != address(0), "OreoBoosterConfig::externalNft::_externalNft must not be address(0)");
    externalboosterEnergyInfo[_externalNft] = CategoryEnergyInfo({
      maxEnergy: _param.maxEnergy,
      boostBps: _param.boostBps,
      updatedAt: block.timestamp
    });

    emit SetExternalBoosterNFTEnergyInfo(_externalNft, _param.maxEnergy, _param.boostBps);
  }

  /// @notice set stake token allowance
  /// @dev only owner can call this function
  /// @param _stakeToken a specified token
  /// @param _isAllowed a flag indicating the allowance of a specified token
  function setStakeTokenAllowance(address _stakeToken, bool _isAllowed) external onlyOwner {
    require(_stakeToken != address(0), "OreoBoosterConfig::setStakeTokenAllowance::_stakeToken must not be address(0)");
    stakeTokenAllowance[_stakeToken] = _isAllowed;

    emit SetStakeTokenAllowance(_stakeToken, _isAllowed);
  }

  /// @notice set caller allowance - only eligible caller can call a function
  /// @dev only eligible callers can call this function
  /// @param _caller a specified caller
  /// @param _isAllowed a flag indicating the allowance of a specified token
  function setCallerAllowance(address _caller, bool _isAllowed) external onlyOwner {
    require(_caller != address(0), "OreoBoosterConfig::setCallerAllowance::_caller must not be address(0)");
    callerAllowance[_caller] = _isAllowed;

    emit SetCallerAllowance(_caller, _isAllowed);
  }

  /// @notice A function for setting oreobooster NFT energy info as a batch
  /// @param _params a list of OreoBoosterNFTParams [{nftAddress, nftTokenId, maxEnergy, boostBps}]
  function setBatchOreoBoosterNFTEnergyInfo(OreoBoosterNFTParams[] calldata _params) external onlyOwner {
    for (uint256 i = 0; i < _params.length; ++i) {
      _setOreoBoosterNFTEnergyInfo(_params[i]);
    }
  }

  /// @notice A function for setting oreobooster NFT energy info
  /// @param _param a OreoBoosterNFTParams {nftAddress, nftTokenId, maxEnergy, boostBps}
  function setOreoBoosterNFTEnergyInfo(OreoBoosterNFTParams calldata _param) external onlyOwner {
    _setOreoBoosterNFTEnergyInfo(_param);
  }

  /// @dev An internal function for setting oreobooster NFT energy info
  /// @param _param a OreoBoosterNFTParams {nftAddress, nftTokenId, maxEnergy, boostBps}
  function _setOreoBoosterNFTEnergyInfo(OreoBoosterNFTParams calldata _param) internal {
    oreoboosterEnergyInfo[_param.nftAddress][_param.nftTokenId] = OreoBoosterEnergyInfo({
      maxEnergy: _param.maxEnergy,
      currentEnergy: _param.maxEnergy,
      boostBps: _param.boostBps,
      updatedAt: block.timestamp
    });

    emit SetOreoBoosterNFTEnergyInfo(
      _param.nftAddress,
      _param.nftTokenId,
      _param.maxEnergy,
      _param.maxEnergy,
      _param.boostBps
    );
  }

  /// @notice A function for setting category NFT energy info as a batch, used for nft with non-preminted
  /// @param _params a list of CategoryNFTParams [{nftAddress, nftTokenId, maxEnergy, boostBps}]
  function setBatchCategoryNFTEnergyInfo(CategoryNFTParams[] calldata _params) external onlyOwner {
    for (uint256 i = 0; i < _params.length; ++i) {
      _setCategoryNFTEnergyInfo(_params[i]);
    }
  }

  /// @notice A function for setting category NFT energy info, used for nft with non-preminted
  /// @param _param a CategoryNFTParams {nftAddress, nftTokenId, maxEnergy, boostBps}
  function setCategoryNFTEnergyInfo(CategoryNFTParams calldata _param) external onlyOwner {
    _setCategoryNFTEnergyInfo(_param);
  }

  /// @dev An internal function for setting category NFT energy info, used for nft with non-preminted
  /// @param _param a CategoryNFTParams {nftAddress, nftCategoryId, maxEnergy, boostBps}
  function _setCategoryNFTEnergyInfo(CategoryNFTParams calldata _param) internal {
    categoryEnergyInfo[_param.nftAddress][_param.nftCategoryId] = CategoryEnergyInfo({
      maxEnergy: _param.maxEnergy,
      boostBps: _param.boostBps,
      updatedAt: block.timestamp
    });

    emit SetCategoryNFTEnergyInfo(_param.nftAddress, _param.nftCategoryId, _param.maxEnergy, _param.boostBps);
  }

  /// @dev A function setting if a particular stake token should allow a specified nft category to be boosted (used with non-preminted nft)
  /// @param _param a CategoryAllowanceParams {stakingToken, [{nftAddress, nftCategoryId, allowance;}]}
  function setStakingTokenCategoryAllowance(CategoryAllowanceParams calldata _param) external onlyOwner {
    for (uint256 i = 0; i < _param.allowance.length; ++i) {
      require(
        stakeTokenAllowance[_param.stakingToken],
        "OreoBoosterConfig::setStakingTokenCategoryAllowance:: bad staking token"
      );
      categoryNftAllowanceConfig[_param.stakingToken][_param.allowance[i].nftAddress][
        _param.allowance[i].nftCategoryId
      ] = _param.allowance[i].allowance;

      emit SetCategoryNFTAllowance(
        _param.stakingToken,
        _param.allowance[i].nftAddress,
        _param.allowance[i].nftCategoryId,
        _param.allowance[i].allowance
      );
    }
  }

  /// @dev A function setting if a particular stake token should allow a specified nft to be boosted
  /// @param _param a OreoBoosterAllowanceParams {stakingToken, [{nftAddress, nftTokenId,allowance;}]}
  function setStakingTokenOreoBoosterAllowance(OreoBoosterAllowanceParams calldata _param) external onlyOwner {
    for (uint256 i = 0; i < _param.allowance.length; ++i) {
      require(
        stakeTokenAllowance[_param.stakingToken],
        "OreoBoosterConfig::setStakingTokenOreoBoosterAllowance:: bad staking token"
      );
      oreoboosterNftAllowanceConfig[_param.stakingToken][_param.allowance[i].nftAddress][
        _param.allowance[i].nftTokenId
      ] = _param.allowance[i].allowance;

      emit SetOreoBoosterNFTAllowance(
        _param.stakingToken,
        _param.allowance[i].nftAddress,
        _param.allowance[i].nftTokenId,
        _param.allowance[i].allowance
      );
    }
  }

  /// @notice use for checking whether or not this nft supports an input stakeToken
  /// @dev if not support when checking with token, need to try checking with category level (categoryNftAllowanceConfig) as well since there should not be oreoboosterNftAllowanceConfig in non-preminted nft
  function oreoboosterNftAllowance(
    address _stakeToken,
    address _nftAddress,
    uint256 _nftTokenId
  ) external view override returns (bool) {
    if (!oreoboosterNftAllowanceConfig[_stakeToken][_nftAddress][_nftTokenId]) {
      CategoryEnergyInfo memory externalboosterInfo = externalboosterEnergyInfo[_nftAddress];

      if (externalboosterInfo.updatedAt != 0) {
        return categoryNftAllowanceConfig[_stakeToken][_nftAddress][0];
      }

      uint256 categoryId = IOreoSwapNFT(_nftAddress).oreoswapNFTToCategory(_nftTokenId);
      return categoryNftAllowanceConfig[_stakeToken][_nftAddress][categoryId];
    }
    return true;
  }
}

