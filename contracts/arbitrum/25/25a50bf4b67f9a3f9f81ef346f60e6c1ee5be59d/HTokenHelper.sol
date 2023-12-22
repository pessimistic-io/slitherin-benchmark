//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./Strings.sol";
import "./IERC20Metadata.sol";
import "./IERC721Metadata.sol";

import "./JsonWriter.sol";

import "./HTokenI.sol";
import "./ControllerI.sol";
import "./PermissionlessOracleI.sol";
import "./HTokenHelperI.sol";
import "./ErrorReporter.sol";

/**
 * @title   A hToken helper as the contract started to get big.
 * @notice  This deals with different frontend functions for easy computation on the frontend
 * @dev     Do not use these functions in any contract as they are only created for the frontend purposes
 * @author  Honey Labs Inc.
 * @custom:coauthor     m4rio
 * @custom:contributor  BowTiedPickle
 */
contract HTokenHelper is HTokenHelperI {
  using Strings for uint256;
  using JsonWriter for JsonWriter.Json;

  /// @notice Version of the contract 1_000_002 corresponds to 1.0.002
  uint256 public constant version = 1_000_002;

  uint256 public constant DENOMINATOR = 10_000;

  /**
   * @notice  Get underlying balance that is available for withdrawal or borrow
   * @return  The quantity of underlying not tied up
   */
  function getAvailableUnderlying(HTokenI _hToken) external view override returns (uint256) {
    return _hToken.getCashPrior() - _hToken.totalReserves();
  }

  /**
   * @notice  Get underlying balance for an account
   * @param   _account the account to check the balance for
   * @return  The quantity of underlying asset owned by this account
   */
  function getAvailableUnderlyingForUser(HTokenI _hToken, address _account) external view override returns (uint256) {
    return (_hToken.balanceOf(_account, 0) * _hToken.exchangeRateStored()) / 1e18;
  }

  /**
   * @notice  returns different assets per a hToken, helper method to reduce frontend calls
   * @param   _hToken the hToken to get the assets for
   * @return  total borrows
   * @return  total reserves
   * @return  total underlying balance
   * @return  active coupons
   */
  function getAssets(
    HTokenI _hToken
  ) external view override returns (uint256, uint256, uint256, HTokenI.Coupon[] memory) {
    uint256 totalBorrow = _hToken.totalBorrows();
    uint256 totalReserves = _hToken.totalReserves();
    uint256 underlyingBalance = _hToken.underlyingToken().balanceOf(address(_hToken));
    HTokenI.Coupon[] memory activeCoupons = getActiveCoupons(_hToken, false);
    return (totalBorrow, totalReserves, underlyingBalance, activeCoupons);
  }

  /**
   * @notice  Get all a user's coupons
   * @param   _hToken The HToken we want to get the user's coupons from
   * @param   _user   The user to search for
   * @return  Array of all coupons belonging to the user
   */
  function getUserCoupons(HTokenI _hToken, address _user) external view returns (HTokenI.Coupon[] memory) {
    unchecked {
      HTokenI.Coupon[] memory userCoupons = new HTokenI.Coupon[](_hToken.userToCoupons(_user));
      uint256 length = _hToken.idCounter();
      uint256 counter;
      for (uint256 i; i < length; ++i) {
        HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(i);
        if (!collateral.active) continue;
        HTokenI.Coupon memory coupon = _hToken.borrowCoupons(collateral.collateralId);

        if (coupon.owner == _user) {
          userCoupons[counter++] = coupon;
        }
      }

      return userCoupons;
    }
  }

  /**
   * @notice  Get the number of coupons deposited aka active
   * @param   _hToken The HToken we want to get the active User Coupons
   * @param   _hasDebt if the coupon has debt or not
   * @return  Array of all active coupons
   */
  function getActiveCoupons(HTokenI _hToken, bool _hasDebt) public view returns (HTokenI.Coupon[] memory) {
    unchecked {
      HTokenI.Coupon[] memory depositedCoupons;
      uint256 length = _hToken.idCounter();
      uint256 deposited;
      for (uint256 i; i < length; ++i) {
        HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(i);
        HTokenI.Coupon memory coupon = _hToken.getSpecificCouponByCollateralId(collateral.collateralId);
        if (collateral.active && ((_hasDebt && coupon.borrowAmount > 0) || !_hasDebt)) {
          ++deposited;
        }
      }
      depositedCoupons = new HTokenI.Coupon[](deposited);
      uint256 j;
      for (uint256 i; i < length; ++i) {
        HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(i);
        HTokenI.Coupon memory coupon = _hToken.getSpecificCouponByCollateralId(collateral.collateralId);

        if (collateral.active && ((_hasDebt && coupon.borrowAmount > 0) || !_hasDebt)) {
          depositedCoupons[j] = coupon;

          // This condition means "if j == deposited then break, else continue the loop with j + 1".
          // This is a gas optimization to avoid potentially unnecessary storage readings
          if (j++ == deposited) {
            break;
          }
        }
      }
      return depositedCoupons;
    }
  }

  /**
   * @notice  Get tokenIds of all a user's coupons
   * @param   _hToken The HToken we want to get the User Coupon Indices
   * @param   _user The user to search for
   * @return  Array of indices of all coupons belonging to the user
   */
  function getUserCouponIndices(HTokenI _hToken, address _user) external view returns (uint256[] memory) {
    unchecked {
      uint256[] memory userCoupons = new uint256[](_hToken.userToCoupons(_user));
      uint256 length = _hToken.idCounter();
      uint256 counter;
      for (uint256 i; i < length; ++i) {
        HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(i);
        if (!collateral.active) continue;
        HTokenI.Coupon memory coupon = _hToken.borrowCoupons(collateral.collateralId);

        if (coupon.owner == _user) {
          userCoupons[counter++] = i;
        }
      }

      return userCoupons;
    }
  }

  /**
   * @notice  returns prices of floor and underlying for a market to reduce frontend calls
   * @param   _hToken the hToken to get the prices for
   * @return  collection floor price in underlying value
   * @return  underlying price in usd
   */
  function getMarketOraclePrices(HTokenI _hToken) external view override returns (uint256, uint256) {
    uint8 decimals = _hToken.decimals();
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    PermissionlessOracleI cachedOracle = ControllerI(controller).oracle(_hToken);

    (uint128 floorPriceInETH, ) = cachedOracle.getFloorPrice(address(_hToken.collateralToken()), decimals);

    uint256 underlyingPriceInUSD = internalUnderlyingPriceInUSD(_hToken);
    uint256 ethPrice = uint256(cachedOracle.getEthPrice(decimals));

    return (
      ((floorPriceInETH * ethPrice) * DENOMINATOR) / underlyingPriceInUSD / 10 ** decimals,
      (underlyingPriceInUSD * DENOMINATOR) / 10 ** decimals
    );
  }

  /**
   * @notice  Returns the borrow fee for a market, it can also return the discounted fee for referred borrow
   * @param   _hToken The market we want to get the borrow fee for
   * @param   _referred Flag that needs to be true in case we want to get the referred borrow fee
   * @return  fee - The borrow fee mantissa denominated in 1e18
   */
  function getMarketBorrowFee(HTokenI _hToken, bool _referred) external view override returns (uint256 fee) {
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    if (!_referred) {
      (fee, ) = ControllerI(controller).getBorrowFeePerMarket(_hToken, "", "");
    } else fee = ControllerI(controller).getReferralBorrowFeePerMarket(_hToken);
  }

  /**
   * @notice  returns the collection price floor in usd
   * @param   _hToken the hToken to get the price for
   * @return  collection floor price in usd
   */
  function getFloorPriceInUSD(HTokenI _hToken) public view override returns (uint256) {
    uint256 floorPrice = internalFloorPriceInUSD(_hToken);
    return (floorPrice * DENOMINATOR) / 1e18;
  }

  /**
   * @notice  returns the collection price floor in underlying value
   * @param   _hToken the hToken to get the price for
   * @return  collection floor price in underlying
   */
  function getFloorPriceInUnderlying(HTokenI _hToken) public view returns (uint256) {
    uint256 floorPrice = internalFloorPriceInUSD(_hToken);
    uint256 underlyingPriceInUSD = internalUnderlyingPriceInUSD(_hToken);
    return (floorPrice * DENOMINATOR) / underlyingPriceInUSD;
  }

  /**
   * @notice  get the underlying price in usd for a hToken
   * @param   _hToken the hToken to get the price for
   * @return  underlying price in usd
   */
  function getUnderlyingPriceInUSD(HTokenI _hToken) public view override returns (uint256) {
    return (internalUnderlyingPriceInUSD(_hToken) * DENOMINATOR) / 10 ** _hToken.decimals();
  }

  /**
   * @notice  get the max borrowable amount for a market
   * @notice  it computes the floor price in usd and take the % of collateral factor that can be max borrowed
   *          then it divides it by the underlying price in usd.
   * @param   _hToken the hToken to get the price for
   * @param   _controller the controller used to get the collateral factor
   * @return  underlying price in underlying
   */
  function getMaxBorrowableAmountInUnderlying(
    HTokenI _hToken,
    ControllerI _controller
  ) external view returns (uint256) {
    uint256 floorPrice = internalFloorPriceInUSD(_hToken);
    uint256 underlyingPriceInUSD = internalUnderlyingPriceInUSD(_hToken);
    (, uint256 LTVfactor, ) = _controller.getMarketData(_hToken);
    // removing mantissa of 1e18
    return ((LTVfactor * floorPrice) * DENOMINATOR) / underlyingPriceInUSD / 1e18;
  }

  /**
   * @notice  get the max borrowable amount for a market
   * @notice  it computes the floor price in usd and take the % of collateral factor that can be max borrowed
   * @param   _hToken the hToken to get the price for
   * @param   _controller the controller used to get the collateral factor
   * @return  underlying price in usd
   */
  function getMaxBorrowableAmountInUSD(HTokenI _hToken, ControllerI _controller) external view returns (uint256) {
    uint256 floorPrice = internalFloorPriceInUSD(_hToken);
    (, , uint256 collateralFactor) = _controller.getMarketData(_hToken);
    return ((collateralFactor * floorPrice) * DENOMINATOR) / 1e18 / 10 ** _hToken.decimals();
  }

  /**
   * @notice  get's all the coupons that have deposited collateral
   * @param   _hToken market to get the collateral from
   * @param   _startTokenId start token id of the collateral collection, as we don't know how big the collection will be we have
   *          to do pagination
   * @param   _endTokenId end of token id we want to get.
   * @return  coupons list of coupons that are active
   */
  function getAllCollateralPerHToken(
    HTokenI _hToken,
    uint256 _startTokenId,
    uint256 _endTokenId
  ) external view returns (HTokenI.Coupon[] memory coupons) {
    unchecked {
      coupons = new HTokenI.Coupon[](_endTokenId - _startTokenId);
      for (uint256 i = _startTokenId; i <= _endTokenId; ++i) {
        HTokenI.Coupon memory coupon = _hToken.borrowCoupons(i);
        if (coupon.active == 2) coupons[i - _startTokenId] = coupon;
      }
    }
  }

  /**
   * @notice  Gets data about a market for frontend display
   * @param   _hToken the market we want the data for
   * @return  interest rate of the market
   * @return  total underlying supplied in a market
   * @return  total underlying available to be borrowed
   */
  function getFrontendMarketData(HTokenI _hToken) external view returns (uint256, uint256, uint256) {
    uint256 hTokenSupply = _hToken.totalSupply();
    uint256 exchangeRate = _hToken.exchangeRateStored();
    return (5_000, (hTokenSupply * exchangeRate) / 1e18, _hToken.getCashPrior() - _hToken.totalReserves());
  }

  /**
   * @notice  Gets data about a coupon for frontend display
   * @param   _hToken   The market we want the coupon for
   * @param   _couponId The coupon id we want to get the data for
   * @return  debt of this coupon
   * @return  allowance - how much liquidity can borrow till hitting LTV
   * @return  nft floor price
   */
  function getFrontendCouponData(HTokenI _hToken, uint256 _couponId) external view returns (uint256, uint256, uint256) {
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    HTokenInternalI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(_couponId);
    HTokenInternalI.Coupon memory coupon = _hToken.borrowCoupons(collateral.collateralId);

    uint256 liquidityTillLTV;
    (, , liquidityTillLTV) = ControllerI(controller).getHypotheticalAccountLiquidity(
      _hToken,
      coupon.owner,
      collateral.collateralId,
      0,
      0
    );
    return (_hToken.getDebtForCoupon(_couponId), liquidityTillLTV, getFloorPriceInUnderlying(_hToken));
  }

  /**
   * @notice  Gets Liquidation data for a market, for frontend purposes
   * @param   _hToken the market we want the data for
   * @return  Liquidation threshold of a market (collateral factor)
   * @return  Total debt of the market
   * @return  TVL is an aproximate value of the NFTs deposited within a market, we only count the NFTs that have debt
   */
  function getFrontendLiquidationData(HTokenI _hToken) external view returns (uint256, uint256, uint256) {
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    uint256 floorPrice = getFloorPriceInUnderlying(_hToken);
    (, , uint256 collateralFactor) = ControllerI(controller).getMarketData(_hToken);
    uint256 length = _hToken.idCounter();
    uint256 debtCoupons;
    for (uint256 i; i < length; ++i) {
      HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(i);
      HTokenI.Coupon memory coupon = _hToken.getSpecificCouponByCollateralId(collateral.collateralId);
      if (collateral.active && coupon.borrowAmount > 0) {
        ++debtCoupons;
      }
    }
    return (collateralFactor, _hToken.totalBorrows(), debtCoupons * floorPrice);
  }

  /**
   * @notice  uri function called from the HToken that returns the uri metadata for a coupon
   * @param   _id id of the hToken
   * @param   _hTokenAddress address of the hToken
   */
  function uri(uint256 _id, address _hTokenAddress) external view override returns (string memory) {
    HTokenI _hToken = HTokenI(_hTokenAddress);

    JsonWriter.Json memory writer;
    writer = writer.writeStartObject();
    if (_id > 0) {
      HTokenI.Collateral memory collateral = _hToken.collateralPerBorrowCouponId(_id);

      if (!collateral.active) revert WrongParams();

      HTokenI.Coupon memory coupon = _hToken.borrowCoupons(collateral.collateralId);

      writer = writer.writeStringProperty("name", string.concat("Honey Coupon ", _id.toString()));
      writer = writer.writeStringProperty("description", string.concat("Honey Coupon for Market ", _hToken.symbol()));
      writer = writer.writeStringProperty("external_url", "https://honey.finance");
      writer = writer.writeStringProperty("image", "https://honey.finance");
      writer = writer.writeStartArray("attributes");

      writer = writer.writeStartObject();
      writer = writer.writeStringProperty("trait_type", "BORROW_AMOUNT");
      writer = writer.writeStringProperty("value", coupon.borrowAmount.toString());
      writer = writer.writeEndObject();

      writer = writer.writeStartObject();
      writer = writer.writeStringProperty("trait_type", "DEBT_SHARES");
      writer = writer.writeStringProperty("value", coupon.debtShares.toString());
      writer = writer.writeEndObject();

      writer = writer.writeStartObject();
      writer = writer.writeStringProperty("trait_type", "COLLATERAL_ID");
      writer = writer.writeStringProperty("value", coupon.collateralId.toString());
      writer = writer.writeEndObject();

      writer = writer.writeStartObject();
      writer = writer.writeStringProperty("trait_type", "COLLATERAL_ADDRESS");
      writer = writer.writeStringProperty("value", toString(abi.encodePacked(address(_hToken.collateralToken()))));
      writer = writer.writeEndObject();
    } else {
      writer = writer.writeStringProperty(
        "name",
        string.concat(HTokenInternalI(_hToken).name(), " ", HTokenInternalI(_hToken).symbol())
      );
      writer = writer.writeStringProperty(
        "description",
        string.concat(
          "Honey Market with underlying ",
          IERC20Metadata(address(_hToken.underlyingToken())).name(),
          " and collateral ",
          IERC721Metadata(address(_hToken.collateralToken())).name()
        )
      );
      writer = writer.writeStringProperty("external_url", "https://honey.finance");
      writer = writer.writeStringProperty("image", "https://honey.finance");
      writer = writer.writeStartArray("attributes");

      writer = writer.writeStartObject();
      writer = writer.writeStringProperty("trait_type", "SUPPLY");
      writer = writer.writeStringProperty("value", _hToken.totalSupply().toString());
      writer = writer.writeEndObject();
    }

    writer = writer.writeEndArray();
    writer = writer.writeEndObject();
    return writer.value;
  }

  function toString(bytes memory data) internal pure returns (string memory) {
    bytes memory alphabet = "0123456789abcdef";

    uint256 len = data.length;

    bytes memory str = new bytes(2 + len * 2);
    str[0] = "0";
    str[1] = "x";

    for (uint256 i; i < len; ) {
      str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
      str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
      unchecked {
        ++i;
      }
    }
    return string(str);
  }

  function internalFloorPriceInUSD(HTokenI _hToken) internal view returns (uint256) {
    uint8 decimals = _hToken.decimals();
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    PermissionlessOracleI cachedOracle = ControllerI(controller).oracle(_hToken);
    (uint128 floorPriceInETH, ) = cachedOracle.getFloorPrice(address(_hToken.collateralToken()), decimals);

    uint256 ethPrice = uint256(cachedOracle.getEthPrice(decimals));

    return (floorPriceInETH * ethPrice) / 10 ** decimals;
  }

  function internalUnderlyingPriceInUSD(HTokenI _hToken) internal view returns (uint256) {
    address controller;
    (, , controller, , , , , ) = _hToken.getAddresses();
    PermissionlessOracleI cachedOracle = ControllerI(controller).oracle(_hToken);

    return uint256(cachedOracle.getUnderlyingPriceInUSD(_hToken.underlyingToken(), _hToken.decimals()));
  }
}

