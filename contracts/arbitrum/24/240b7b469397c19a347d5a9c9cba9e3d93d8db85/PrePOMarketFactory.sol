// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {LongShortToken} from "./LongShortToken.sol";
import {IPrePOMarket, PrePOMarket} from "./PrePOMarket.sol";
import {ILongShortToken} from "./ILongShortToken.sol";
import {IAddressBeacon, IPrePOMarketFactory, IUintBeacon} from "./IPrePOMarketFactory.sol";
import {SafeOwnable} from "./SafeOwnable.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract PrePOMarketFactory is
  IPrePOMarketFactory,
  ReentrancyGuard,
  SafeOwnable
{
  IAddressBeacon private _addressBeacon;
  IUintBeacon private _uintBeacon;

  function createMarket(
    string calldata tokenNameSuffix,
    string calldata tokenSymbolSuffix,
    bytes32 longTokenSalt,
    bytes32 shortTokenSalt,
    IPrePOMarket.MarketParameters calldata parameters
  ) external override nonReentrant {
    if (address(_addressBeacon) == address(0)) revert AddressBeaconNotSet();
    if (address(_uintBeacon) == address(0)) revert UintBeaconNotSet();
    (LongShortToken longToken, LongShortToken shortToken) = _createPairTokens(
      tokenNameSuffix,
      tokenSymbolSuffix,
      longTokenSalt,
      shortTokenSalt
    );
    if (address(longToken) > parameters.collateral)
      revert LongTokenAddressTooHigh();
    if (address(shortToken) > parameters.collateral)
      revert ShortTokenAddressTooHigh();
    bytes32 salt = keccak256(abi.encodePacked(longToken, shortToken));
    PrePOMarket newMarket = new PrePOMarket{salt: salt}(
      msg.sender,
      ILongShortToken(address(longToken)),
      ILongShortToken(address(shortToken)),
      _addressBeacon,
      _uintBeacon,
      parameters
    );
    longToken.transferOwnership(address(newMarket));
    shortToken.transferOwnership(address(newMarket));
    emit MarketCreation(
      address(newMarket),
      msg.sender,
      address(longToken),
      address(shortToken),
      address(_addressBeacon),
      address(_uintBeacon),
      parameters
    );
  }

  function setAddressBeacon(IAddressBeacon addressBeacon)
    external
    override
    onlyOwner
  {
    _addressBeacon = addressBeacon;
    emit AddressBeaconChange(address(addressBeacon));
  }

  function setUintBeacon(IUintBeacon uintBeacon) external override onlyOwner {
    _uintBeacon = uintBeacon;
    emit UintBeaconChange(address(uintBeacon));
  }

  function getAddressBeacon() external view override returns (IAddressBeacon) {
    return _addressBeacon;
  }

  function getUintBeacon() external view override returns (IUintBeacon) {
    return _uintBeacon;
  }

  function _createPairTokens(
    string memory tokenNameSuffix,
    string memory tokenSymbolSuffix,
    bytes32 longTokenSalt,
    bytes32 shortTokenSalt
  )
    internal
    returns (LongShortToken newLongToken, LongShortToken newShortToken)
  {
    string memory longTokenName = string(
      abi.encodePacked("LONG", " ", tokenNameSuffix)
    );
    string memory shortTokenName = string(
      abi.encodePacked("SHORT", " ", tokenNameSuffix)
    );
    string memory longTokenSymbol = string(
      abi.encodePacked("L", "_", tokenSymbolSuffix)
    );
    string memory shortTokenSymbol = string(
      abi.encodePacked("S", "_", tokenSymbolSuffix)
    );
    newLongToken = new LongShortToken{salt: longTokenSalt}(
      longTokenName,
      longTokenSymbol
    );
    newShortToken = new LongShortToken{salt: shortTokenSalt}(
      shortTokenName,
      shortTokenSymbol
    );
    return (newLongToken, newShortToken);
  }
}

