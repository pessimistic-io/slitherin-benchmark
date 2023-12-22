// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./Context.sol";

import "./IMasterChef.sol";
import "./IOreoSwapNFT.sol";
import "./IOreoBooster.sol";
import "./IOreoBoosterConfig.sol";

contract NFTScanner is Context {
  using SafeMath for uint256;

  struct BoosterNFT {
    address nftAddress;
    uint256 nftCategoryId;
    uint256 nftTokenId;
    uint256 maxEnergy;
    uint256 currentEnergy;
    uint256 boostBps;
    string tokenURI;
  }

  struct BoosterTokenInfo {
    address nftAddress;
    uint256 nftCategoryId;
    uint256 nftTokenId;
    bool isOwner;
    bool isApproved;
    bool[] isAllowance;
    bool[] isStakingIn;
    string tokenURI;
  }

  IMasterChef public masterChef;
  IOreoSwapNFT public oreoSwapNFT;
  IOreoBooster public booster;
  IOreoBoosterConfig public boosterConfig;

  constructor(
    IMasterChef _masterChef,
    IOreoSwapNFT _oreoSwapNFT,
    IOreoBooster _booster,
    IOreoBoosterConfig _boosterConfig
  ) public {
    masterChef = _masterChef;
    oreoSwapNFT = _oreoSwapNFT;
    booster = _booster;
    boosterConfig = _boosterConfig;
  }

  function getBoosterInfo(address _user) external view returns (BoosterNFT[] memory) {
    uint256 balance = oreoSwapNFT.balanceOf(_user);
    BoosterNFT[] memory boosterNFTInfo = new BoosterNFT[](balance);

    for (uint256 i = 0; i < balance; i++) {
      uint256 _nftTokenId = oreoSwapNFT.tokenOfOwnerByIndex(_user, i);
      uint256 _nftCategoryId = oreoSwapNFT.oreoswapNFTToCategory(_nftTokenId);
      string memory _tokenURI = oreoSwapNFT.tokenURI(_nftTokenId);
      (uint256 _maxEnergy, uint256 _currentEnergy, uint256 _boostBps) = boosterConfig.energyInfo(
        address(oreoSwapNFT),
        _nftTokenId
      );
      boosterNFTInfo[i] = BoosterNFT({
        nftAddress: address(oreoSwapNFT),
        nftCategoryId: _nftCategoryId,
        nftTokenId: _nftTokenId,
        tokenURI: _tokenURI,
        maxEnergy: _maxEnergy,
        currentEnergy: _currentEnergy,
        boostBps: _boostBps
      });
    }

    return boosterNFTInfo;
  }

  function getExternalBoosterInfo(address _user, address _collection) external view returns (BoosterNFT[] memory) {
    IOreoSwapNFT externalNFT = IOreoSwapNFT(_collection);
    uint256 balance = externalNFT.balanceOf(_user);
    BoosterNFT[] memory boosterNFTInfo = new BoosterNFT[](balance);

    for (uint256 i = 0; i < balance; i++) {
      uint256 _nftTokenId = externalNFT.tokenOfOwnerByIndex(_user, i);
      string memory _tokenURI = externalNFT.tokenURI(_nftTokenId);
      (uint256 _maxEnergy, uint256 _currentEnergy, uint256 _boostBps) = boosterConfig.energyInfo(
        address(externalNFT),
        _nftTokenId
      );
      boosterNFTInfo[i] = BoosterNFT({
        nftAddress: address(externalNFT),
        nftCategoryId: 0,
        nftTokenId: _nftTokenId,
        tokenURI: _tokenURI,
        maxEnergy: _maxEnergy,
        currentEnergy: _currentEnergy,
        boostBps: _boostBps
      });
    }

    return boosterNFTInfo;
  }

  function getBoosterStakingInfo(address[] memory _stakeTokens, address _user)
    external
    view
    returns (BoosterNFT[] memory)
  {
    BoosterNFT[] memory boosterNFTStakingInfo = new BoosterNFT[](_stakeTokens.length);

    for (uint256 i = 0; i < _stakeTokens.length; i++) {
      (address _nftAddress, uint256 _nftTokenId) = booster.userStakingNFT(_stakeTokens[i], _user);

      uint256 _nftCategoryId;
      string memory _tokenURI;
      uint256 _maxEnergy;
      uint256 _currentEnergy;
      uint256 _boostBps;

      if (_nftAddress != address(0)) {
        if (_nftAddress == address(oreoSwapNFT)) {
          _nftCategoryId = oreoSwapNFT.oreoswapNFTToCategory(_nftTokenId);
          _tokenURI = oreoSwapNFT.tokenURI(_nftTokenId);
          (_maxEnergy, _currentEnergy, _boostBps) = boosterConfig.energyInfo(address(oreoSwapNFT), _nftTokenId);
        } else {
          IOreoSwapNFT externalNFT = IOreoSwapNFT(_nftAddress);
          _tokenURI = externalNFT.tokenURI(_nftTokenId);
          (_maxEnergy, _currentEnergy, _boostBps) = boosterConfig.energyInfo(address(externalNFT), _nftTokenId);
        }
        boosterNFTStakingInfo[i] = BoosterNFT({
          nftAddress: _nftAddress,
          nftCategoryId: _nftCategoryId,
          nftTokenId: _nftTokenId,
          tokenURI: _tokenURI,
          maxEnergy: _maxEnergy,
          currentEnergy: _currentEnergy,
          boostBps: _boostBps
        });
      }
    }
    return boosterNFTStakingInfo;
  }

  function getBoosterTokenInfo(
    address[] memory _stakeTokens,
    address _nftAddress,
    uint256 _nftCategoryId,
    uint256 _nftTokenId,
    address _user
  ) external view returns (BoosterTokenInfo memory) {
    address _owner = oreoSwapNFT.ownerOf(_nftTokenId);
    address _approvedAddress = oreoSwapNFT.getApproved(_nftTokenId);
    string memory _tokenURI = oreoSwapNFT.tokenURI(_nftTokenId);
    bool[] memory _isAllowance = new bool[](_stakeTokens.length);
    bool[] memory _isStakingIn = new bool[](_stakeTokens.length);

    for (uint256 i = 0; i < _stakeTokens.length; i++) {
      _isAllowance[i] = boosterConfig.oreoboosterNftAllowance(_stakeTokens[i], _nftAddress, _nftTokenId);
      (address _stakingNFTAddress, uint256 _stakingNFTTokenId) = booster.userStakingNFT(_stakeTokens[i], _user);
      _isStakingIn[i] =
        _owner == address(booster) &&
        _nftAddress == _stakingNFTAddress &&
        _nftTokenId == _stakingNFTTokenId;
    }

    return
      BoosterTokenInfo({
        nftAddress: _nftAddress,
        nftCategoryId: _nftCategoryId,
        nftTokenId: _nftTokenId,
        tokenURI: _tokenURI,
        isOwner: _owner == _user,
        isApproved: _approvedAddress == address(booster),
        isAllowance: _isAllowance,
        isStakingIn: _isStakingIn
      });
  }
}

