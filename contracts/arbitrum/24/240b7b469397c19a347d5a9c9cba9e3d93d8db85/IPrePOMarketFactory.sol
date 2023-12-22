// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.7;

import {IPrePOMarket} from "./PrePOMarket.sol";
import {IAddressBeacon} from "./IAddressBeacon.sol";
import {IUintBeacon} from "./IUintBeacon.sol";

interface IPrePOMarketFactory {
  event AddressBeaconChange(address beacon);
  event MarketCreation(
    address market,
    address deployer,
    address longToken,
    address shortToken,
    address addressBeacon,
    address uintBeacon,
    IPrePOMarket.MarketParameters parameters
  );
  event UintBeaconChange(address beacon);

  error AddressBeaconNotSet();
  error LongTokenAddressTooHigh();
  error ShortTokenAddressTooHigh();
  error UintBeaconNotSet();

  function createMarket(
    string calldata tokenNameSuffix,
    string calldata tokenSymbolSuffix,
    bytes32 longTokenSalt,
    bytes32 shortTokenSalt,
    IPrePOMarket.MarketParameters calldata parameters
  ) external;

  function setAddressBeacon(IAddressBeacon addressBeacon) external;

  function setUintBeacon(IUintBeacon uintBeacon) external;

  function getAddressBeacon() external view returns (IAddressBeacon);

  function getUintBeacon() external view returns (IUintBeacon);
}

