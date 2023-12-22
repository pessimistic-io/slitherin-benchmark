// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {IRewardsController} from "./IRewardsController.sol";
import {IUiIncentiveDataProvider} from "./IUiIncentiveDataProvider.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {IAToken} from "./IAToken.sol";
import {IVariableDebtToken} from "./IVariableDebtToken.sol";
import {IStableDebtToken} from "./IStableDebtToken.sol";
import {UserConfiguration} from "./UserConfiguration.sol";
import {DataTypes} from "./DataTypes.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {Ownable} from "./Ownable.sol";
import {IEACAggregatorProxy} from "./IEACAggregatorProxy.sol";

contract UiIncentiveDataProvider is IUiIncentiveDataProvider, Ownable {
  using UserConfiguration for DataTypes.UserConfigurationMap;

  constructor() public {}

  mapping (address => address) public aggregatorsOfAssets;

  event AggregatorUpdated(address token, address aggregator);

  function updateAggregators(address[] memory assets, address[] memory aggregators) external onlyOwner {    
    for(uint256 i = 0; i < assets.length; i++) {
      aggregatorsOfAssets[assets[i]] = aggregators[i];
      emit AggregatorUpdated(assets[i], aggregators[i]);
    }
  }

  function getFullReservesIncentiveData(ILendingPoolAddressesProvider provider, address user)
    external
    view
    override
    returns (AggregatedReserveIncentiveData[] memory, UserReserveIncentiveData[] memory)
  {
    return (_getReservesIncentivesData(provider), _getUserReservesIncentivesData(provider, user));
  }

  function getReservesIncentivesData(ILendingPoolAddressesProvider provider)
    external
    view
    override
    returns (AggregatedReserveIncentiveData[] memory)
  {
    return _getReservesIncentivesData(provider);
  }

  function _getReservesIncentivesData(ILendingPoolAddressesProvider provider)
    private
    view
    returns (AggregatedReserveIncentiveData[] memory)
  {
    ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
    address[] memory reserves = lendingPool.getReservesList();
    AggregatedReserveIncentiveData[] memory reservesIncentiveData = new AggregatedReserveIncentiveData[](reserves.length);

    for (uint256 i = 0; i < reserves.length; i++) {
      AggregatedReserveIncentiveData memory reserveIncentiveData = reservesIncentiveData[i];
      reserveIncentiveData.underlyingAsset = reserves[i];

      DataTypes.ReserveData memory baseData = lendingPool.getReserveData(reserves[i]);


      // aToken
      IRewardsController aTokenIncentiveController = IRewardsController(
        address(IAToken(baseData.aTokenAddress).getIncentivesController())
      );

      RewardInfo[] memory aRewardsInformation;

      if (address(aTokenIncentiveController) != address(0)) {
        address[] memory aTokenRewardAddresses = aTokenIncentiveController.getRewardsByAsset(
          baseData.aTokenAddress
        );

        aRewardsInformation = new RewardInfo[](aTokenRewardAddresses.length);
        for (uint256 j = 0; j < aTokenRewardAddresses.length; ++j) {
          RewardInfo memory rewardInformation;
          rewardInformation.rewardTokenAddress = aTokenRewardAddresses[j];

          (
            rewardInformation.tokenIncentivesIndex,
            rewardInformation.emissionPerSecond,
            rewardInformation.incentivesLastUpdateTimestamp,
            rewardInformation.emissionEndTimestamp
          ) = aTokenIncentiveController.getRewardsData(
            baseData.aTokenAddress,
            rewardInformation.rewardTokenAddress
          );

          rewardInformation.precision = aTokenIncentiveController.getAssetDecimals(
            baseData.aTokenAddress
          );
          rewardInformation.rewardTokenDecimals = IERC20Detailed(
            rewardInformation.rewardTokenAddress
          ).decimals();
          rewardInformation.rewardTokenSymbol = IERC20Detailed(rewardInformation.rewardTokenAddress)
            .symbol();

          rewardInformation.rewardOracleAddress = aggregatorsOfAssets[rewardInformation.rewardTokenAddress];
          rewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).decimals();
          rewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).latestAnswer();

          aRewardsInformation[j] = rewardInformation;
        }
      }

      reserveIncentiveData.aIncentiveData = IncentiveData(
        baseData.aTokenAddress,
        address(aTokenIncentiveController),
        aRewardsInformation
      );


      // vToken
      IRewardsController vTokenIncentiveController = IRewardsController(
        address(IVariableDebtToken(baseData.variableDebtTokenAddress).getIncentivesController())
      );
      address[] memory vTokenRewardAddresses = vTokenIncentiveController.getRewardsByAsset(
        baseData.variableDebtTokenAddress
      );
      RewardInfo[] memory vRewardsInformation;

      if (address(vTokenIncentiveController) != address(0)) {
        vRewardsInformation = new RewardInfo[](vTokenRewardAddresses.length);
        for (uint256 j = 0; j < vTokenRewardAddresses.length; ++j) {
          RewardInfo memory rewardInformation;
          rewardInformation.rewardTokenAddress = vTokenRewardAddresses[j];

          (
            rewardInformation.tokenIncentivesIndex,
            rewardInformation.emissionPerSecond,
            rewardInformation.incentivesLastUpdateTimestamp,
            rewardInformation.emissionEndTimestamp
          ) = vTokenIncentiveController.getRewardsData(
            baseData.variableDebtTokenAddress,
            rewardInformation.rewardTokenAddress
          );

          rewardInformation.precision = vTokenIncentiveController.getAssetDecimals(
            baseData.variableDebtTokenAddress
          );
          rewardInformation.rewardTokenDecimals = IERC20Detailed(
            rewardInformation.rewardTokenAddress
          ).decimals();
          rewardInformation.rewardTokenSymbol = IERC20Detailed(rewardInformation.rewardTokenAddress)
            .symbol();

          rewardInformation.rewardOracleAddress = aggregatorsOfAssets[rewardInformation.rewardTokenAddress];
          rewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).decimals();
          rewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).latestAnswer();

          vRewardsInformation[j] = rewardInformation;
        }
      }

      reserveIncentiveData.vIncentiveData = IncentiveData(
        baseData.variableDebtTokenAddress,
        address(vTokenIncentiveController),
        vRewardsInformation
      );


      // sToken
      IRewardsController sTokenIncentiveController = IRewardsController(
        address(IStableDebtToken(baseData.stableDebtTokenAddress).getIncentivesController())
      );
      address[] memory sTokenRewardAddresses = sTokenIncentiveController.getRewardsByAsset(
        baseData.stableDebtTokenAddress
      );
      RewardInfo[] memory sRewardsInformation;

      if (address(sTokenIncentiveController) != address(0)) {
        sRewardsInformation = new RewardInfo[](sTokenRewardAddresses.length);
        for (uint256 j = 0; j < sTokenRewardAddresses.length; ++j) {
          RewardInfo memory rewardInformation;
          rewardInformation.rewardTokenAddress = sTokenRewardAddresses[j];

          (
            rewardInformation.tokenIncentivesIndex,
            rewardInformation.emissionPerSecond,
            rewardInformation.incentivesLastUpdateTimestamp,
            rewardInformation.emissionEndTimestamp
          ) = sTokenIncentiveController.getRewardsData(
            baseData.stableDebtTokenAddress,
            rewardInformation.rewardTokenAddress
          );

          rewardInformation.precision = sTokenIncentiveController.getAssetDecimals(
            baseData.stableDebtTokenAddress
          );
          rewardInformation.rewardTokenDecimals = IERC20Detailed(
            rewardInformation.rewardTokenAddress
          ).decimals();
          rewardInformation.rewardTokenSymbol = IERC20Detailed(rewardInformation.rewardTokenAddress)
            .symbol();

          rewardInformation.rewardOracleAddress = aggregatorsOfAssets[rewardInformation.rewardTokenAddress];
          rewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).decimals();
          rewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            rewardInformation.rewardOracleAddress
          ).latestAnswer();

          sRewardsInformation[j] = rewardInformation;
        }
      }

      reserveIncentiveData.sIncentiveData = IncentiveData(
        baseData.stableDebtTokenAddress,
        address(sTokenIncentiveController),
        sRewardsInformation
      );
    }

    return (reservesIncentiveData);
  }

  function getUserReservesIncentivesData(ILendingPoolAddressesProvider provider, address user)
    external
    view
    override
    returns (UserReserveIncentiveData[] memory)
  {
    return _getUserReservesIncentivesData(provider, user);
  }

  function _getUserReservesIncentivesData(ILendingPoolAddressesProvider provider, address user)
    private
    view
    returns (UserReserveIncentiveData[] memory)
  {
    ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
    address[] memory reserves = lendingPool.getReservesList();

    UserReserveIncentiveData[] memory userReservesIncentivesData = new UserReserveIncentiveData[](
      user != address(0) ? reserves.length : 0
    );

    for (uint256 i = 0; i < reserves.length; i++) {
      DataTypes.ReserveData memory baseData = lendingPool.getReserveData(reserves[i]);

      // user reserve data
      userReservesIncentivesData[i].underlyingAsset = reserves[i];


      // aToken
      IRewardsController aTokenIncentiveController = IRewardsController(
        address(IAToken(baseData.aTokenAddress).getIncentivesController())
      );
  
      if (address(aTokenIncentiveController) != address(0)) {
        address[] memory aTokenRewardAddresses = aTokenIncentiveController.getRewardsByAsset(
          baseData.aTokenAddress
        );
        UserRewardInfo[] memory aUserRewardsInformation = new UserRewardInfo[](
          aTokenRewardAddresses.length
        );
        for (uint256 j = 0; j < aTokenRewardAddresses.length; ++j) {
          UserRewardInfo memory userRewardInformation;
          userRewardInformation.rewardTokenAddress = aTokenRewardAddresses[j];

          userRewardInformation.tokenIncentivesUserIndex = aTokenIncentiveController.getUserAssetData(
            user,
            baseData.aTokenAddress,
            userRewardInformation.rewardTokenAddress
          );

          userRewardInformation.userUnclaimedRewards = aTokenIncentiveController
            .getUserUnclaimedRewardsFromStorage(user, userRewardInformation.rewardTokenAddress);
          userRewardInformation.rewardTokenDecimals = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).decimals();
          userRewardInformation.rewardTokenSymbol = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).symbol();

          userRewardInformation.rewardOracleAddress = aggregatorsOfAssets[userRewardInformation.rewardTokenAddress];
          userRewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).decimals();
          userRewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).latestAnswer();

          aUserRewardsInformation[j] = userRewardInformation;
        }

        userReservesIncentivesData[i].aTokenIncentivesUserData = UserIncentiveData(
          baseData.aTokenAddress,
          address(aTokenIncentiveController),
          aUserRewardsInformation
        );
      }


      // vToken
      IRewardsController vTokenIncentiveController = IRewardsController(
        address(IVariableDebtToken(baseData.variableDebtTokenAddress).getIncentivesController())
      );

      if (address(vTokenIncentiveController) != address(0)) {
        address[] memory vTokenRewardAddresses = vTokenIncentiveController.getRewardsByAsset(
          baseData.variableDebtTokenAddress
        );
        UserRewardInfo[] memory vUserRewardsInformation = new UserRewardInfo[](
          vTokenRewardAddresses.length
        );
        for (uint256 j = 0; j < vTokenRewardAddresses.length; ++j) {
          UserRewardInfo memory userRewardInformation;
          userRewardInformation.rewardTokenAddress = vTokenRewardAddresses[j];
          
          userRewardInformation.tokenIncentivesUserIndex = vTokenIncentiveController.getUserAssetData(
            user,
            baseData.variableDebtTokenAddress,
            userRewardInformation.rewardTokenAddress
          );

          userRewardInformation.userUnclaimedRewards = vTokenIncentiveController
            .getUserUnclaimedRewardsFromStorage(user, userRewardInformation.rewardTokenAddress);
          userRewardInformation.rewardTokenDecimals = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).decimals();
          userRewardInformation.rewardTokenSymbol = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).symbol();

          userRewardInformation.rewardOracleAddress = aggregatorsOfAssets[userRewardInformation.rewardTokenAddress];
          userRewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).decimals();
          userRewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).latestAnswer();

          vUserRewardsInformation[j] = userRewardInformation;
        }

        userReservesIncentivesData[i].vTokenIncentivesUserData = UserIncentiveData(
          baseData.variableDebtTokenAddress,
          address(aTokenIncentiveController),
          vUserRewardsInformation
        );
      }

      // sToken
      IRewardsController sTokenIncentiveController = IRewardsController(
        address(IStableDebtToken(baseData.stableDebtTokenAddress).getIncentivesController())
      );
      if (address(sTokenIncentiveController) != address(0)) {
        address[] memory sTokenRewardAddresses = sTokenIncentiveController.getRewardsByAsset(
          baseData.stableDebtTokenAddress
        );
        UserRewardInfo[] memory sUserRewardsInformation = new UserRewardInfo[](
          sTokenRewardAddresses.length
        );
        for (uint256 j = 0; j < sTokenRewardAddresses.length; ++j) {
          UserRewardInfo memory userRewardInformation;
          userRewardInformation.rewardTokenAddress = sTokenRewardAddresses[j];
          
          userRewardInformation.tokenIncentivesUserIndex = sTokenIncentiveController.getUserAssetData(
            user,
            baseData.stableDebtTokenAddress,
            userRewardInformation.rewardTokenAddress
          );

          userRewardInformation.userUnclaimedRewards = sTokenIncentiveController
            .getUserUnclaimedRewardsFromStorage(user, userRewardInformation.rewardTokenAddress);
          userRewardInformation.rewardTokenDecimals = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).decimals();
          userRewardInformation.rewardTokenSymbol = IERC20Detailed(
            userRewardInformation.rewardTokenAddress
          ).symbol();

          userRewardInformation.rewardOracleAddress = aggregatorsOfAssets[userRewardInformation.rewardTokenAddress];
          userRewardInformation.priceFeedDecimals = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).decimals();
          userRewardInformation.rewardPriceFeed = IEACAggregatorProxy(
            userRewardInformation.rewardOracleAddress
          ).latestAnswer();

          sUserRewardsInformation[j] = userRewardInformation;
        }

        userReservesIncentivesData[i].sTokenIncentivesUserData = UserIncentiveData(
          baseData.stableDebtTokenAddress,
          address(aTokenIncentiveController),
          sUserRewardsInformation
        );
      }
    }

    return (userReservesIncentivesData);
  }
}
