pragma solidity ^0.8.19;

import "./ISiloStrategy.sol";
import "./ISiloLens.sol";
import "./ISiloIncentivesController.sol";

import "./ITokenToUsdcOracle.sol";

contract SiloStrategy is ISiloStrategy {
    ISiloLens siloLens;
    ISiloIncentivesController siloIncentivesController;
    ITokenToUsdcOracle tokenTokUsdcOracle;
    address silo;
    address collateralAsset;
    address siloAsset;

    constructor(address _siloLens, address _siloIncentivesController, address _oracle, address _silo, address _collateralAsset, address _siloAsset) {
        siloLens = ISiloLens(_siloLens);
        siloIncentivesController = ISiloIncentivesController(_siloIncentivesController);
        tokenTokUsdcOracle = ITokenToUsdcOracle(_oracle);
        silo = _silo;
        collateralAsset = _collateralAsset;
        siloAsset = _siloAsset;
    }

    function getBalance(address strategist) external view returns(uint256) {
        uint256 usdcBalance = siloLens.collateralBalanceOfUnderlying(silo, collateralAsset, strategist);

        address[] memory assets = new address[](1);
        assets[0] = siloAsset;

        uint256 rewards = siloIncentivesController.getRewardsBalance(assets, strategist);

        usdcBalance += tokenTokUsdcOracle.usdcAmount(rewards);
        return usdcBalance;
    }
}
