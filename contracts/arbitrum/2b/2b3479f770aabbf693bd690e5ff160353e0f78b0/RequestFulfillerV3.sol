// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "./LowLatencyRequestFulfiller.sol";

import "./IRequestFulfillerV3.sol";

import "./IPlatformPositionHandler.sol";
import "./IPlatformPositionRequester.sol";

import "./IVolatilityTokenActionHandler.sol";
import "./IVolatilityTokenRequester.sol";

import "./IMegaThetaVaultActionHandler.sol";
import "./IHedgedThetaVaultActionHandler.sol";
import "./IThetaVaultRequester.sol";

import "./IRequestFulfillerV3Management.sol";

contract RequestFulfillerV3 is LowLatencyRequestFulfiller, IRequestFulfillerV3, IPlatformPositionRequester, IVolatilityTokenRequester, IThetaVaultRequester, IRequestFulfillerV3Management {
    enum RequestType {
        NONE,
        CVI_OPEN,
        CVI_CLOSE,
        UCVI_OPEN,
        UCVI_CLOSE,
        REVERSE_OPEN,
        REVERSE_CLOSE,
        CVI_MINT,
        CVI_BURN,
        UCVI_MINT,
        UCVI_BURN,
        HEDGED_DEPOSIT,
        HEDGED_WITHDRAW,
        MEGA_DEPOSIT,
        MEGA_WITHDRAW
    }

    uint32 private constant MAX_PERCENTAGE = 1000000;

    uint168 public minOpenAmount;
    uint168 public minCloseAmount;

    uint168 public minMintAmount;
    uint168 public minBurnAmount;

    uint256 public minDepositAmount;
    uint256 public minWithdrawAmount;

    IPlatformPositionHandler public platformCVI;
    IPlatformPositionHandler public platformUCVI;
    IPlatformPositionHandler public platformReverse;

    IVolatilityTokenActionHandler public volTokenCVI;
    IVolatilityTokenActionHandler public volTokenUCVI;

    IHedgedThetaVaultActionHandler public hedgedVault;
    IMegaThetaVaultActionHandler public megaVault;

    uint32 public minCVIDiffAllowedPercentage;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, OracleLookupData calldata _oracleLookupData, IVerifierProxy _verifier, uint256 _expirationPeriodSec) external initializer {
        LowLatencyRequestFulfiller.__LowLatencyRequestFulfiller_init(_owner, _oracleLookupData, _verifier, _expirationPeriodSec);

        minOpenAmount = 1e6;
        minCloseAmount = 1e4;

        minMintAmount = 1e6;
        minBurnAmount = 0;

        minDepositAmount = 1e4;
        minWithdrawAmount = 1e16;

        minCVIDiffAllowedPercentage = 10000;
    }

    function openCVIPlatformPosition(bytes32 _referralCode, uint168 _tokenAmount, uint32 _maxCVI, uint32 _maxBuyingPremiumFeePercentage, uint8 _leverage) payable external override { 
        require(address(platformCVI) != address(0), 'CVI platform is unset');
        openPlatformPosition(RequestType.CVI_OPEN, _referralCode, _tokenAmount, _maxCVI, _maxBuyingPremiumFeePercentage, _leverage);
    }

    function closeCVIPlatformPosition(uint168 _positionUnitsAmount, uint32 _minCVI) payable external override {
        require(address(platformCVI) != address(0), 'CVI platform is unset');
        closePlatformPosition(RequestType.CVI_CLOSE, _positionUnitsAmount, _minCVI);
    }

    function openUCVIPlatformPosition(bytes32 _referralCode, uint168 _tokenAmount, uint32 _maxCVI, uint32 _maxBuyingPremiumFeePercentage, uint8 _leverage) payable external override { 
        require(address(platformUCVI) != address(0), 'UCVI platform is unset');
        openPlatformPosition(RequestType.UCVI_OPEN, _referralCode, _tokenAmount, _maxCVI, _maxBuyingPremiumFeePercentage, _leverage);
    }

    function closeUCVIPlatformPosition(uint168 _positionUnitsAmount, uint32 _minCVI) payable external override {
        require(address(platformUCVI) != address(0), 'UCVI platform is unset');
        closePlatformPosition(RequestType.UCVI_CLOSE, _positionUnitsAmount, _minCVI);
    }

    function openReversePlatformPosition(bytes32 _referralCode, uint168 _tokenAmount, uint32 _maxCVI, uint32 _maxBuyingPremiumFeePercentage, uint8 _leverage) payable external override { 
        require(address(platformReverse) != address(0), 'Reverse platform is unset');
        openPlatformPosition(RequestType.REVERSE_OPEN, _referralCode, _tokenAmount, _maxCVI, _maxBuyingPremiumFeePercentage, _leverage);
    }

    function closeReversePlatformPosition(uint168 _positionUnitsAmount, uint32 _minCVI) payable external override {
        require(address(platformReverse) != address(0), 'Reverse platform is unset');
        closePlatformPosition(RequestType.REVERSE_CLOSE, _positionUnitsAmount, _minCVI);
    }
    
    function mintCVIVolatilityToken(uint168 _tokenAmount, uint32 _maxBuyingPremiumFeePercentage) payable external override {
        require(address(volTokenCVI) != address(0), 'CVI Volatility Token is unset');
        mintVolatilityToken(RequestType.CVI_MINT, _tokenAmount, _maxBuyingPremiumFeePercentage);
    }

    function burnCVIVolatilityToken(uint168 _burnAmount) payable external override {
        require(address(volTokenCVI) != address(0), 'CVI Volatility Token is unset');
        burnVolatilityToken(RequestType.CVI_BURN, _burnAmount);
    }

    function mintUCVIVolatilityToken(uint168 _tokenAmount, uint32 _maxBuyingPremiumFeePercentage) payable external override {
        require(address(volTokenUCVI) != address(0), 'UCVI Volatility Token is unset');
        mintVolatilityToken(RequestType.UCVI_MINT, _tokenAmount, _maxBuyingPremiumFeePercentage);
    }

    function burnUCVIVolatilityToken(uint168 _burnAmount) payable external override {
        require(address(volTokenUCVI) != address(0), 'UCVI Volatility Token is unset');
        burnVolatilityToken(RequestType.UCVI_BURN, _burnAmount);
    }

    function depositMegaThetaVault(uint168 _tokenAmount) payable external override {
        require(address(megaVault) != address(0), 'Mega Vault is unset');
        require(_tokenAmount >= minDepositAmount, 'Min Deposit');
        createActionRequest(uint8(RequestType.MEGA_DEPOSIT), abi.encode(_tokenAmount));
    }

    function withdrawMegaThetaVault(uint168 _thetaTokenAmount) payable external override {
        require(address(megaVault) != address(0), 'Mega Vault is unset');
        require(_thetaTokenAmount >= minWithdrawAmount, 'Min Withdraw');
        createActionRequest(uint8(RequestType.MEGA_WITHDRAW), abi.encode(_thetaTokenAmount));
    }

    function depositHedgedThetaVault(uint168 _tokenAmount, bool _shouldStake) payable external override {
        require(address(hedgedVault) != address(0), 'Hedged Vault is unset');
        require(_tokenAmount >= minDepositAmount, 'Min Deposit');
        createActionRequest(uint8(RequestType.HEDGED_DEPOSIT), abi.encode(_tokenAmount,_shouldStake));
    }

    function withdrawHedgedThetaVault(uint168 _hedgeTokenAmount) payable external override {
        require(address(hedgedVault) != address(0), 'Hedged Vault is unset');
        require(_hedgeTokenAmount >= minWithdrawAmount, 'Min Withdraw');
        createActionRequest(uint8(RequestType.HEDGED_WITHDRAW), abi.encode(_hedgeTokenAmount));
    }

    function setMinPlatformAmounts(uint168 _newMinOpenAmount, uint168 _newMinCloseAmount) external override onlyOwner {
        minOpenAmount = _newMinOpenAmount;
        minCloseAmount = _newMinCloseAmount;

        emit MinPlatformAmountsSet(_newMinOpenAmount, _newMinCloseAmount);
    }

    function setMinVolTokenAmounts(uint168 _newMinMintAmount, uint168 _newMinBurnAmount) external override onlyOwner {
        minMintAmount = _newMinMintAmount;
        minBurnAmount = _newMinBurnAmount;

        emit MinVolTokenAmountsSet(_newMinMintAmount, _newMinBurnAmount);
    }

    function setMinThetaVaultAmounts(uint168 _newMinDepositAmount, uint168 _newMinWithdrawAmount) external override onlyOwner {
        minDepositAmount = _newMinDepositAmount;
        minWithdrawAmount = _newMinWithdrawAmount;

        emit MinThetaVaultAmountsSet(_newMinDepositAmount, _newMinWithdrawAmount);
    }

    function setCVIPlatform(IPlatformPositionHandler _newCVIPlatform) external override onlyOwner {
        platformCVI = _newCVIPlatform;

        emit CVIPlatformSet(address(_newCVIPlatform));
    }

    function setUCVIPlatform(IPlatformPositionHandler _newUCVIPlatform) external override onlyOwner {
        platformUCVI = _newUCVIPlatform;

        emit UCVIPlatformSet(address(_newUCVIPlatform));
    }

    function setReversePlatform(IPlatformPositionHandler _newReversePlatform) external override onlyOwner {
        platformReverse = _newReversePlatform;

        emit ReversePlatformSet(address(_newReversePlatform));
    }

    function setCVIVolToken(IVolatilityTokenActionHandler _newCVIVolToken) external override onlyOwner {
        volTokenCVI = _newCVIVolToken;

        emit CVIVolTokenSet(address(_newCVIVolToken));
    }

    function setUCVIVolToken(IVolatilityTokenActionHandler _newUCVIVolToken) external override onlyOwner {
        volTokenUCVI = _newUCVIVolToken;

        emit UCVIVolTokenSet(address(_newUCVIVolToken));
    }

    function setHedgedVault(IHedgedThetaVaultActionHandler _newHedgedVault) external override onlyOwner {
        hedgedVault = _newHedgedVault;

        emit HedgedVaultSet(address(_newHedgedVault));
    }

    function setMegaVault(IMegaThetaVaultActionHandler _newMegaVault) external override onlyOwner {
        megaVault = _newMegaVault;

        emit MegaVaultSet(address(_newMegaVault));
    }

    function setMinCVIDiffAllowedPercentage(uint32 _newMinCVIDiffAllowedPercentage) external override onlyOwner {
        minCVIDiffAllowedPercentage = _newMinCVIDiffAllowedPercentage;

        emit MinCVIDiffAllowedPercentageSet(_newMinCVIDiffAllowedPercentage);   
    }

    function openPlatformPosition(RequestType _requestType, bytes32 _referralCode, uint168 _tokenAmount, uint32 _maxCVI, uint32 _maxBuyingPremiumFeePercentage, uint8 _leverage) internal {
        require(_tokenAmount >= minOpenAmount, 'Min Open');
        createActionRequest(uint8(_requestType), abi.encode(_referralCode, _tokenAmount, _maxCVI, _maxBuyingPremiumFeePercentage, _leverage));
    }

    function closePlatformPosition(RequestType _requestType, uint168 _positionUnitsAmount, uint32 _minCVI) internal {
        require(_positionUnitsAmount >= minCloseAmount, 'Min Close');
        createActionRequest(uint8(_requestType), abi.encode(_positionUnitsAmount, _minCVI));
    }

    function mintVolatilityToken(RequestType _requestType, uint168 _tokenAmount, uint32 _maxBuyingPremiumFeePercentage) internal {
        require(_tokenAmount >= minMintAmount, 'Min Mint');
        createActionRequest(uint8(_requestType), abi.encode(_tokenAmount, _maxBuyingPremiumFeePercentage));
    }

    function burnVolatilityToken(RequestType _requestType, uint168 _burnAmount) internal {
        require(_burnAmount >= minBurnAmount, 'Min Burn');
        createActionRequest(uint8(_requestType), abi.encode(_burnAmount));
    }

    function executeEvent(RequestData memory _requestData, bytes memory _endodedEventData, int256 _cviValue) internal override {
        RequestType requestType = RequestType(_requestData.requestType);
        if (requestType == RequestType.CVI_OPEN) {
            executeOpenPosition(platformCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.CVI_CLOSE) {
            executeClosePosition(platformCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.UCVI_OPEN) {
            executeOpenPosition(platformUCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.UCVI_CLOSE) {
            executeClosePosition(platformUCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.REVERSE_OPEN) {
            executeOpenPosition(platformReverse, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.REVERSE_CLOSE) {
            executeClosePosition(platformReverse, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.CVI_MINT) {
            executeMint(volTokenCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.CVI_BURN) {
            executeBurn(volTokenCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.UCVI_MINT) {
            executeMint(volTokenUCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.UCVI_BURN) {
            executeBurn(volTokenUCVI, _requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.MEGA_DEPOSIT) {
            executeMegaDeposit(_requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.MEGA_WITHDRAW) {
            executeMegaWithdraw(_requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.HEDGED_DEPOSIT) {
            executeHedgedDeposit(_requestData, _endodedEventData, _cviValue);
        } else if (requestType == RequestType.HEDGED_WITHDRAW) {
            executeHedgedWithdraw(_requestData, _endodedEventData, _cviValue);
        } else revert("Invalid request type");
    }

    function executeOpenPosition(IPlatformPositionHandler _platform, RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = _platform.cviOracle().getTruncatedCVIValue(_cviValue);
        uint32 verifyDiffCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(verifyDiffCVIValue);
        (
            bytes32 referralCode,
            uint168 tokenAmount,
            uint32 maxCVI,
            uint32 maxBuyingPremiumFeePercentage,
            uint8 leverage
        ) = abi.decode(_encodedEventData, (bytes32, uint168, uint32, uint32, uint8));

        if (catchErrors) {
            try _platform.openPositionForOwner(_requestData.requester, referralCode, tokenAmount, maxCVI, maxBuyingPremiumFeePercentage, leverage, truncatedCVIValue) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            _platform.openPositionForOwner(_requestData.requester, referralCode, tokenAmount, maxCVI, maxBuyingPremiumFeePercentage, leverage, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeClosePosition(IPlatformPositionHandler _platform, RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = _platform.cviOracle().getTruncatedCVIValue(_cviValue);
        uint32 verifyDiffCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(verifyDiffCVIValue);
        (uint168 positionUnitsAmount, uint32 minCVI) = abi.decode(_encodedEventData, (uint168, uint32));

        if (catchErrors) {
            try _platform.closePositionForOwner(_requestData.requester, positionUnitsAmount, minCVI, truncatedCVIValue) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            _platform.closePositionForOwner(_requestData.requester, positionUnitsAmount, minCVI, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeMint(IVolatilityTokenActionHandler _volToken, RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = _volToken.platform().cviOracle().getTruncatedCVIValue(_cviValue);
        uint32 verifyDiffCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(verifyDiffCVIValue);
        (uint168 tokenAmount, uint32 maxBuyingPremiumFeePercentage) = abi.decode(_encodedEventData, (uint168, uint32));

        if (catchErrors) {
            try _volToken.mintTokensForOwner(_requestData.requester, tokenAmount, maxBuyingPremiumFeePercentage, truncatedCVIValue) {
                executionSuccess(_requestData);
            }  catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            _volToken.mintTokensForOwner(_requestData.requester, tokenAmount, maxBuyingPremiumFeePercentage, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeBurn(IVolatilityTokenActionHandler _volToken, RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = _volToken.platform().cviOracle().getTruncatedCVIValue(_cviValue);
        uint32 verifyDiffCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(verifyDiffCVIValue);
        (uint168 burnAmount) = abi.decode(_encodedEventData, (uint168));

        if (catchErrors) {
            try _volToken.burnTokensForOwner(_requestData.requester, burnAmount, truncatedCVIValue) {
                executionSuccess(_requestData);
            }  catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            _volToken.burnTokensForOwner(_requestData.requester, burnAmount, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeMegaDeposit(RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(truncatedCVIValue);
        (uint168 tokenAmount) = abi.decode(_encodedEventData, (uint168));

        if (catchErrors) {
            try megaVault.depositForOwner(_requestData.requester, tokenAmount, truncatedCVIValue) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            megaVault.depositForOwner(_requestData.requester, tokenAmount, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeMegaWithdraw(RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(truncatedCVIValue);
        (uint168 burnAmount) = abi.decode(_encodedEventData, (uint168));

        if (catchErrors) {
            try megaVault.withdrawForOwner(_requestData.requester, burnAmount, truncatedCVIValue) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            megaVault.withdrawForOwner(_requestData.requester, burnAmount, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function executeHedgedDeposit(RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(truncatedCVIValue);
        (uint168 tokenAmount, bool shouldStake) = abi.decode(_encodedEventData, (uint168, bool));

        if (catchErrors) {
            try hedgedVault.depositForOwner(_requestData.requester, tokenAmount, truncatedCVIValue, shouldStake) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            hedgedVault.depositForOwner(_requestData.requester, tokenAmount, truncatedCVIValue, shouldStake);
            executionSuccess(_requestData);
        }
    }

    function executeHedgedWithdraw(RequestData memory _requestData, bytes memory _encodedEventData, int256 _cviValue) internal {
        uint32 truncatedCVIValue = platformCVI.cviOracle().getTruncatedCVIValue(_cviValue);
        verifyCVIDiff(truncatedCVIValue);
        (uint168 burnAmount) = abi.decode(_encodedEventData, (uint168));

        if (catchErrors) {
            try hedgedVault.withdrawForOwner(_requestData.requester, burnAmount, truncatedCVIValue) {
                executionSuccess(_requestData);
            } catch Error(string memory reason) {
                executionFailure(_requestData, reason, "0x");
            } catch (bytes memory lowLevelData) {
                executionFailure(_requestData, 'Unknown', lowLevelData);
            }
        } else {
            hedgedVault.withdrawForOwner(_requestData.requester, burnAmount, truncatedCVIValue);
            executionSuccess(_requestData);
        }
    }

    function verifyCVIDiff(uint32 _realTimeCVIValue) private view {
        (uint32 cviOracle,,) = platformCVI.cviOracle().getCVILatestRoundData();
        uint256 cviDiff = cviOracle > _realTimeCVIValue ? cviOracle - _realTimeCVIValue : _realTimeCVIValue - cviOracle;
        require(cviDiff * MAX_PERCENTAGE / cviOracle <= minCVIDiffAllowedPercentage, "CVI diff too big");
    }
}

