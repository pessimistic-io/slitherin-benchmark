// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: 799a1765b64edc5c158198ef84f785af79e234ae;
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./Math.sol";
import "./IGLPRewarder.sol";
import "./IRewardRouterV2.sol";
import "./IRewardTracker.sol";
import "./ReentrancyGuardKeccak.sol";
import {DiamondStorageLib} from "./DiamondStorageLib.sol";
import "./OnlyOwnerOrInsolvent.sol";
import "./ITokenManager.sol";

import "./Deposit.sol";
import "./Withdrawal.sol";
import "./Order.sol";
import "./IRoleStore.sol";
import "./BasicMulticall.sol";
import "./IERC20Metadata.sol";
import "./IDepositCallbackReceiver.sol";
import "./EventUtils.sol";
import "./IDepositUtils.sol";
import "./IWithdrawalUtils.sol";
import "./IGmxV2Router.sol";
import "./IWithdrawalCallbackReceiver.sol";

//This path is updated during deployment
import "./DeploymentConstants.sol";

abstract contract GmxV2Facet is IDepositCallbackReceiver, IWithdrawalCallbackReceiver, ReentrancyGuardKeccak, OnlyOwnerOrInsolvent {
    using TransferHelper for address;

    // CONSTANTS
    bytes32 constant public CONTROLLER = keccak256(abi.encode("CONTROLLER"));
    bytes32 constant public ORDER_KEEPER = keccak256(abi.encode("ORDER_KEEPER"));
    bytes32 constant public MARKET_KEEPER = keccak256(abi.encode("MARKET_KEEPER"));
    bytes32 constant public FEE_KEEPER = keccak256(abi.encode("FEE_KEEPER"));
    bytes32 constant public FROZEN_ORDER_KEEPER = keccak256(abi.encode("FROZEN_ORDER_KEEPER"));

    // GMX contracts
    function getGMX_V2_ROUTER() internal pure virtual returns (address);

    function getGMX_V2_EXCHANGE_ROUTER() internal pure virtual returns (address);

    function getGMX_V2_DEPOSIT_VAULT() internal pure virtual returns (address);

    function getGMX_V2_WITHDRAWAL_VAULT() internal pure virtual returns (address);

    function getGMX_V2_ROLE_STORE() internal pure virtual returns (address);

    // Mappings
    function marketToLongToken(address market) internal virtual pure returns (address);

    function marketToShortToken(address market) internal virtual pure returns (address);

    function isCallerAuthorized(address _caller) internal view returns (bool){
        IRoleStore roleStore = IRoleStore(getGMX_V2_ROLE_STORE());
        // TODO: Once on prod - verify the roles of authorized signers
        if(
            roleStore.hasRole(_caller, CONTROLLER) ||
            roleStore.hasRole(_caller, ORDER_KEEPER) ||
            roleStore.hasRole(_caller, MARKET_KEEPER) ||
            roleStore.hasRole(_caller, FEE_KEEPER) ||
            roleStore.hasRole(_caller, FROZEN_ORDER_KEEPER)
        ){
            return true;
        }
        return false;
    }


    function _deposit(address gmToken, address depositedToken, uint256 tokenAmount, uint256 minGmAmount, uint256 executionFee) internal nonReentrant noBorrowInTheSameBlock onlyOwner {
//        address longToken = marketToLongToken(gmToken);
//        address shortToken = marketToShortToken(gmToken);
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();

        IERC20(depositedToken).approve(getGMX_V2_ROUTER(), tokenAmount);

        bytes[] memory data = new bytes[](3);

        data[0] = abi.encodeWithSelector(
            IGmxV2Router.sendWnt.selector,
            getGMX_V2_DEPOSIT_VAULT(),
            executionFee
        );
        data[1] = abi.encodeWithSelector(
            IGmxV2Router.sendTokens.selector,
            depositedToken,
            getGMX_V2_DEPOSIT_VAULT(),
            tokenAmount
        );
        data[2] = abi.encodeWithSelector(
            IDepositUtils.createDeposit.selector,
            IDepositUtils.CreateDepositParams({
                receiver: address(this), //receiver
                callbackContract: address(this), //callbackContract
                uiFeeReceiver: address(0), //uiFeeReceiver
                market: gmToken, //market
                initialLongToken: marketToLongToken(gmToken), //initialLongToken
                initialShortToken: marketToShortToken(gmToken), //initialShortToken
                longTokenSwapPath: new address[](0), //longTokenSwapPath
                shortTokenSwapPath: new address[](0), //shortTokenSwapPath
                minMarketTokens: minGmAmount, //minMarketTokens
                shouldUnwrapNativeToken: false, //shouldUnwrapNativeToken
                executionFee: executionFee, //executionFee
                callbackGasLimit: 200000 //callbackGasLimit
            })
        );

        BasicMulticall(getGMX_V2_EXCHANGE_ROUTER()).multicall{ value: msg.value }(data);

        // Simulate solvency check
        {
            bytes32[] memory dataFeedIds = new bytes32[](1);
            dataFeedIds[0] = tokenManager.tokenAddressToSymbol(gmToken);
            uint256 gmTokenUsdPrice = SolvencyMethods.getPrices(dataFeedIds)[0];
            uint256 gmTokensWeightedUsdValue = gmTokenUsdPrice * minGmAmount * tokenManager.debtCoverage(gmToken) / 1e26;
            require((_getThresholdWeightedValue() + gmTokensWeightedUsdValue) > _getDebt(), "The action may cause the account to become insolvent");
        }

        // Freeze account
        DiamondStorageLib.freezeAccount(gmToken);

        // Reset assets exposure
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(gmToken);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(marketToLongToken(gmToken));
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(marketToShortToken(gmToken));
        SolvencyMethods._resetPrimeAccountExposureForChosenAssets(resetExposureAssets);

        // Remove long/short token(s) from owned assets if whole balance(s) was/were used
        if(IERC20Metadata(marketToLongToken(gmToken)).balanceOf(address(this)) == 0){
            DiamondStorageLib.removeOwnedAsset(tokenManager.tokenAddressToSymbol(marketToLongToken(gmToken)));
        }
        if(IERC20Metadata(marketToShortToken(gmToken)).balanceOf(address(this)) == 0){
            DiamondStorageLib.removeOwnedAsset(tokenManager.tokenAddressToSymbol(marketToShortToken(gmToken)));
        }
    }


    function _withdraw(address gmToken, uint256 gmAmount, uint256 minLongTokenAmount, uint256 minShortTokenAmount, uint256 executionFee) internal nonReentrant noBorrowInTheSameBlock onlyOwnerNoStaySolventOrInsolvent {
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        bytes[] memory data = new bytes[](3);

        IERC20(gmToken).approve(getGMX_V2_ROUTER(), gmAmount);

        data[0] = abi.encodeWithSelector(
            IGmxV2Router.sendWnt.selector,
            getGMX_V2_WITHDRAWAL_VAULT(),
            executionFee
        );

        data[1] = abi.encodeWithSelector(
            IGmxV2Router.sendTokens.selector,
            gmToken,
            getGMX_V2_WITHDRAWAL_VAULT(),
            gmAmount
        );

        data[2] = abi.encodeWithSelector(
            IWithdrawalUtils.createWithdrawal.selector,
            IWithdrawalUtils.CreateWithdrawalParams({
                receiver: address(this), //receiver
                callbackContract: address(this), //callbackContract
                uiFeeReceiver: address(0), //uiFeeReceiver
                market: gmToken, //market
                longTokenSwapPath: new address[](0), //longTokenSwapPath
                shortTokenSwapPath: new address[](0), //shortTokenSwapPath
                minLongTokenAmount: minLongTokenAmount,
                minShortTokenAmount: minShortTokenAmount,
                shouldUnwrapNativeToken: false, //shouldUnwrapNativeToken
                executionFee: executionFee, //executionFee
                callbackGasLimit: 200000 //callbackGasLimit
            })
        );

        BasicMulticall(getGMX_V2_EXCHANGE_ROUTER()).multicall{ value: msg.value }(data);

        // Simulate solvency check
        {
            address longToken = marketToLongToken(gmToken);
            address shortToken = marketToShortToken(gmToken);
            bytes32[] memory receivedTokensSymbols = new bytes32[](2);
            uint256[] memory receivedTokensPrices = new uint256[](2);

            receivedTokensSymbols[0] = tokenManager.tokenAddressToSymbol(longToken);
            receivedTokensSymbols[1] = tokenManager.tokenAddressToSymbol(shortToken);
            receivedTokensPrices = getPrices(receivedTokensSymbols);

            uint256 receivedTokensWeightedUsdValue = (
                (receivedTokensPrices[0] * minLongTokenAmount * tokenManager.debtCoverage(longToken)) +
                (receivedTokensPrices[1] * minShortTokenAmount * tokenManager.debtCoverage(shortToken))
            )
            / 1e26;
            require((SolvencyMethods._getThresholdWeightedValue() + receivedTokensWeightedUsdValue) > _getDebt(), "The action may cause the account to become insolvent");
        }

        // Freeze account
        DiamondStorageLib.freezeAccount(gmToken);

        // Reset assets exposure
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(gmToken);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(marketToLongToken(gmToken));
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(marketToShortToken(gmToken));
        SolvencyMethods._resetPrimeAccountExposureForChosenAssets(resetExposureAssets);

        // Remove GM token from owned assets if whole balance was used
        if(IERC20Metadata(gmToken).balanceOf(address(this)) == 0){
            DiamondStorageLib.removeOwnedAsset(tokenManager.tokenAddressToSymbol(gmToken));
        }
    }

    function afterDepositExecution(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external onlyGmxV2Keeper nonReentrant override {
        // Set asset exposure
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(deposit.addresses.market);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(marketToLongToken(deposit.addresses.market));
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(marketToShortToken(deposit.addresses.market));
        SolvencyMethods._setPrimeAccountExposureForChosenAssets(resetExposureAssets);
        
        // Add owned assets
        if(IERC20Metadata(deposit.addresses.market).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(deposit.addresses.market), deposit.addresses.market);
        }

        // Unfreeze account
        DiamondStorageLib.unfreezeAccount(msg.sender);
    }

    function afterDepositCancellation(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external onlyGmxV2Keeper nonReentrant override {
        address longToken = marketToLongToken(deposit.addresses.market);
        address shortToken = marketToShortToken(deposit.addresses.market);
        // Set asset exposure
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(deposit.addresses.market);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(longToken);
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(shortToken);
        SolvencyMethods._setPrimeAccountExposureForChosenAssets(resetExposureAssets);

        // Add owned assets
        if(IERC20Metadata(longToken).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(longToken), longToken);
        }
        if(IERC20Metadata(shortToken).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(shortToken), shortToken);
        }

        DiamondStorageLib.unfreezeAccount(msg.sender);
    }

    function afterWithdrawalExecution(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external onlyGmxV2Keeper nonReentrant override {
        address longToken = marketToLongToken(withdrawal.addresses.market);
        address shortToken = marketToShortToken(withdrawal.addresses.market);
        // Set asset exposure
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(withdrawal.addresses.market);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(longToken);
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(shortToken);
        SolvencyMethods._setPrimeAccountExposureForChosenAssets(resetExposureAssets);

        // Add owned assets
        if(IERC20Metadata(longToken).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(longToken), longToken);
        }
        if(IERC20Metadata(shortToken).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(shortToken), shortToken);
        }

        DiamondStorageLib.unfreezeAccount(msg.sender);
    }

    function afterWithdrawalCancellation(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external onlyGmxV2Keeper nonReentrant override {
        // Set asset exposure
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        bytes32[] memory resetExposureAssets = new bytes32[](3);
        resetExposureAssets[0] = tokenManager.tokenAddressToSymbol(withdrawal.addresses.market);
        resetExposureAssets[1] = tokenManager.tokenAddressToSymbol(marketToLongToken(withdrawal.addresses.market));
        resetExposureAssets[2] = tokenManager.tokenAddressToSymbol(marketToShortToken(withdrawal.addresses.market));
        SolvencyMethods._setPrimeAccountExposureForChosenAssets(resetExposureAssets);

        // Add owned assets
        if(IERC20Metadata(withdrawal.addresses.market).balanceOf(address(this)) > 0){
            DiamondStorageLib.addOwnedAsset(tokenManager.tokenAddressToSymbol(withdrawal.addresses.market), withdrawal.addresses.market);
        }

        DiamondStorageLib.unfreezeAccount(msg.sender);
    }

    // MODIFIERS
    modifier onlyGmxV2Keeper() {
        require(isCallerAuthorized(msg.sender), "Must be a GMX V2 authorized Keeper");
        _;
    }

    modifier onlyOwner() {
        DiamondStorageLib.enforceIsContractOwner();
        _;
    }
}

