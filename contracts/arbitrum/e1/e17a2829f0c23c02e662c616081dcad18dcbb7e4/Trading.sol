//TODO add events

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./MetaContext.sol";
import "./ITrading.sol";
import "./IERC20.sol";
import "./IPairsContract.sol";
import "./IReferrals.sol";
import "./IPosition.sol";
import "./IGovNFT.sol";
import "./IStableVault.sol";
import "./INativeStableVault.sol";
import "./TradingLibrary.sol";


interface IStable is IERC20 {
    function burnFrom(address account, uint amount) external;
    function mintFor(address account, uint amount) external;
}

interface ExtendedIERC20 is IERC20 {
    function decimals() external view returns (uint);
}

interface ERC20Permit is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract Trading is MetaContext, ITrading {

    // Errors
    error IsLimit();
    error NotLimit();
    error LimitNotMet();
    error LimitNotSet();
    error NotLiquidatable();
    error TradingPaused();
    error NotNativeSupport();
    error BadDeposit();
    error BadWithdraw();
    error ValueNotEqualToMargin();
    error BadLeverage();
    error BadStopLoss();
    error Wait();
    error GasPriceTooHigh();
    error NotPositionOwner();
    error NotMargin();
    error NotAllowedPair();
    error BelowMinPositionSize();
    error BadClosePercent();
    error BadStopOrder();
    error NoPrice();
    error LiqThreshold();

    mapping(address => bool) private nodeProvided; // Used for TradingLibrary

    uint constant private DIVISION_CONSTANT = 1e10; // 100%
    address constant private eth = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    uint private constant liqPercent = 9e9; // 90%

    uint public daoFees; // 0.1%
    uint public burnFees; // 0%
    uint public referralFees; // 0.01%
    uint public botFees; // 0.02%
    uint public maxGasPrice = 1000000000000; // 1000 gwei
    uint public limitOrderPriceRange = 1e8; // 1%
    mapping(address => uint) public minPositionSize;
    
    uint public maxWinPercent;
    uint public vaultFundingPercent;

    bool public paused;

    bool public chainlinkEnabled;

    mapping(address => bool) public allowedMargin;

    IPairsContract private pairsContract;
    IReferrals private referrals;
    IPosition private position;
    IGovNFT private gov;

    mapping(address => bool) private isNode;
    uint256 public validSignatureTimer;
    uint256 public minNodeCount;

    struct Delay {
        uint delay; // Block number where delay ends
        bool actionType; // True for open, False for close
    }
    mapping(uint => Delay) public blockDelayPassed; // id => Delay
    uint public blockDelay;

    constructor(
        address _position,
        address _gov,
        address _pairsContract,
        address _referrals
    )
    {
        position = IPosition(_position);
        gov = IGovNFT(_gov);
        pairsContract = IPairsContract(_pairsContract);
        referrals = IReferrals(_referrals);
    }



    // ===== END-USER FUNCTIONS =====

    /**
     * @param _tradeInfo Trade info
     * @param _priceData verifiable off-chain data
     * @param _signature node signature
     * @param _permitData data and signature needed for token approval
     */
    function initiateMarketOrder(
        TradeInfo calldata _tradeInfo,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,
        ERC20PermitData calldata _permitData
    )
        external payable
    {
        _checkDelay(position.getCount(), true);
        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
        validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData);
        uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _tradeInfo.asset, chainlinkEnabled, pairsContract.idToAsset(_tradeInfo.asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
        _setReferral(_tradeInfo.referral);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        unchecked {
            if (_tradeInfo.direction) {
                pairsContract.modifyLongOi(_tradeInfo.asset, _tigAsset, true, _tradeInfo.margin*_tradeInfo.leverage/1e18);
            } else {
                pairsContract.modifyShortOi(_tradeInfo.asset, _tigAsset, true, _tradeInfo.margin*_tradeInfo.leverage/1e18);
            }
        }
        updateFunding(_tradeInfo.asset, _tigAsset);
        position.mint(
            IPosition.MintTrade(
                _msgSender(),
                _tradeInfo.margin,
                _tradeInfo.leverage,
                _tradeInfo.asset,
                _tradeInfo.direction,
                _price,
                _tradeInfo.tpPrice,
                _tradeInfo.slPrice,
                0,
                _tigAsset
            )
        );
        unchecked {
            emit PositionOpened(_tradeInfo, 0, _price, position.getCount()-1, _msgSender());
        }   
    }

    /**
     * @dev initiate closing position
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed in BP
     * @param _priceData verifiable off-chain data
     * @param _signature node signature
     * @param _stableVault StableVault address
     * @param _outputToken Token received upon closing trade
     */
    function initiateCloseOrder(
        uint _id,
        uint _percent,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,
        address _stableVault,
        address _outputToken
    )
        external
    {
        _checkDelay(_id, false);
        _checkOwner(_id);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert IsLimit();        
        uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, pairsContract.idToAsset(_trade.asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
        if (_percent > DIVISION_CONSTANT || _percent == 0) revert BadClosePercent();
        _closePosition(_id, _percent, _price, _stableVault, _outputToken); 
    }

    function addToPosition(
        uint _id,
        uint _addMargin,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,
        address _stableVault,
        address _marginAsset,
        ERC20PermitData calldata _permitData
    )
        external
    {
        _checkOwner(_id);
        _checkDelay(_id, true);
        IPosition.Trade memory _trade = position.trades(_id);
        validateTrade(_trade.asset, _trade.tigAsset, _trade.margin + _addMargin, _trade.leverage);
        if (_trade.orderType != 0) revert IsLimit();
        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData);
        position.setAccInterest(_id);
        unchecked {
            if (_trade.direction) {
                pairsContract.modifyLongOi(_trade.asset, _trade.tigAsset, true, _addMargin*_trade.leverage/1e18);
            } else {
                pairsContract.modifyShortOi(_trade.asset, _trade.tigAsset, true, _addMargin*_trade.leverage/1e18);     
            }
            updateFunding(_trade.asset, _trade.tigAsset);
            uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, pairsContract.idToAsset(_trade.asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
            uint _oldMargin = _trade.margin;
            uint _newMargin = _oldMargin + _addMargin;
            uint _newPrice = _trade.price*_oldMargin/_newMargin + _price*_addMargin/_newMargin;

            position.addToPosition(
                _id,
                _newMargin,
                _newPrice
            );
            
            emit AddToPosition(_id, _newMargin, _newPrice, _trade.trader);
        }
    }

    function initiateLimitOrder(
        TradeInfo calldata _tradeInfo,
        uint256 _orderType, // 1 limit, 2 momentum
        uint256 _price,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,  
        ERC20PermitData calldata _permitData
    )
        external payable
    {
        if (_orderType == 2) {
            uint _asset = _tradeInfo.asset;
            uint _assetPrice = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _asset, chainlinkEnabled, pairsContract.idToAsset(_asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
            if (_tradeInfo.direction) {
                if (_price < _assetPrice) revert BadStopOrder();
            } else {
                if (_price > _assetPrice) revert BadStopOrder();
            }
        }
        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
        validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        if (_orderType == 0) revert NotLimit();
        if (_price == 0) revert NoPrice();
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        _setReferral(_tradeInfo.referral);
        position.mint(
            IPosition.MintTrade(
                _msgSender(),
                _tradeInfo.margin,
                _tradeInfo.leverage,
                _tradeInfo.asset,
                _tradeInfo.direction,
                _price,
                _tradeInfo.tpPrice,
                _tradeInfo.slPrice,
                _orderType,
                _tigAsset
            )
        );
        unchecked {
            emit PositionOpened(_tradeInfo, _orderType, _price, position.getCount() - 1, _msgSender());
        }
    }

    function cancelLimitOrder(
        uint256 _id
    )
        external
    {
        _checkOwner(_id);
        IPosition.Trade memory trade = position.trades(_id);
        if (trade.orderType == 0) revert NotLimit();
        IStable(trade.tigAsset).mintFor(_msgSender(), trade.margin);
        position.burn(_id);
        emit LimitCancelled(_id, _msgSender());
    }

    function addMargin(
        uint256 _id,
        address _marginAsset,
        address _stableVault,
        uint256 _addMargin,
        ERC20PermitData calldata _permitData
    )
        external payable
    {
        _checkOwner(_id);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert IsLimit();
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData);
        unchecked {
            uint256 _newMargin = _trade.margin + _addMargin;
            uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
            if (_newLeverage < asset.minLeverage) revert BadLeverage();
            position.modifyMargin(_id, _newMargin, _newLeverage);
            emit MarginModified(_id, _newMargin, _newLeverage, true, _msgSender());            
        }
    }

    function removeMargin(
        uint256 _id,
        address _stableVault,
        address _outputToken,
        uint256 _removeMargin,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    )
        external
    {
        _checkOwner(_id);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert IsLimit();
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        uint256 _newMargin = _trade.margin - _removeMargin;
        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
        if (_newLeverage > asset.maxLeverage) revert BadLeverage();
        uint _assetPrice = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, asset.chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
        (,int256 _payout) = TradingLibrary.pnl(_trade.direction, _assetPrice, _trade.price, _newMargin, _newLeverage, _trade.accInterest);
        unchecked {
            if (_payout <= int256(_newMargin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert LiqThreshold();
        }
        position.modifyMargin(_id, _newMargin, _newLeverage);
        _handleWithdraw(_trade, _stableVault, _outputToken, _removeMargin);
        emit MarginModified(_id, _newMargin, _newLeverage, false, _msgSender());
    }

    function updateTpSl(
        bool _type, // true is TP
        uint _id,
        uint _limitPrice,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    )
        external
    {
        _checkOwner(_id);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert IsLimit();
        if (_type) {
            position.modifyTp(_id, _limitPrice);
        } else {
            uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, pairsContract.idToAsset(_trade.asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
            _checkSl(_limitPrice, _trade.direction, _price);
            position.modifySl(_id, _limitPrice);
        }
        emit UpdateTPSL(_id, _type, _limitPrice, _msgSender());
    }

    function executeLimitOrder(
        uint _id, 
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    ) 
        external
    {
        unchecked {
            _checkDelay(_id, true);
            _checkGas();
            if (paused) revert TradingPaused();
            IPosition.Trade memory trade = position.trades(_id);
            IPairsContract.Asset memory asset = pairsContract.idToAsset(trade.asset);
            uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, trade.asset, chainlinkEnabled, asset.chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
            if (trade.orderType == 0) revert NotLimit();
            if (trade.direction && trade.orderType == 1) {
                if (trade.price < _price) revert LimitNotMet();
            } else if (!trade.direction && trade.orderType == 1) {
                if (trade.price > _price) revert LimitNotMet();      
            } else if (!trade.direction && trade.orderType == 2) {
                if (trade.price < _price) revert LimitNotMet();
            } else {
                if (trade.price > _price) revert LimitNotMet();
            }
            if (_price > trade.price+trade.price*limitOrderPriceRange/DIVISION_CONSTANT || _price < trade.price-trade.price*limitOrderPriceRange/DIVISION_CONSTANT) revert LimitNotMet();
            if (trade.direction) {
                pairsContract.modifyLongOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            } else {
                pairsContract.modifyShortOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            }
            updateFunding(trade.asset, trade.tigAsset);
            IStable(trade.tigAsset).mintFor(
                _msgSender(),
                ((trade.margin*trade.leverage/1e18)*botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT
            );
            position.executeLimitOrder(_id, trade.price, trade.margin);
            emit LimitOrderExecuted(trade.asset, trade.direction, _price, trade.leverage, trade.margin, _id, trade.trader, _msgSender());
        }
    }

    /**
     * @dev liquidate position
     * @param _id id of the position NFT
     * @param _priceData verifiable off-chain data
     * @param _signature node signature
     */
    function liquidatePosition(
        uint _id,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    )
        external
    {
        unchecked {
            _checkGas();
            IPosition.Trade memory _trade = position.trades(_id);
            IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
            uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, asset.chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
            if (_trade.orderType != 0) revert IsLimit();
            (uint256 _positionSizeAfterPrice, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
            uint256 _positionSize = _trade.margin*_trade.leverage/1e18;
            if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert NotLiquidatable();
            if (_trade.direction) {
                pairsContract.modifyLongOi(_trade.asset, _trade.tigAsset, false, _positionSize);
            } else {
                pairsContract.modifyShortOi(_trade.asset, _trade.tigAsset, false, _positionSize);
            }
            updateFunding(_trade.asset, _trade.tigAsset);
            _handleCloseFees(_trade.asset, type(uint).max, _trade.tigAsset, _positionSizeAfterPrice, _trade.trader);
            position.burn(_id);
            emit PositionLiquidated(_id, _trade.trader, _msgSender());
        }
    }

    /**
     * @dev close position at a pre-set price
     * @param _id id of the position NFT
     * @param _tp true if take profit
     * @param _priceData verifiable off-chain data
     * @param _signature node signature
     */
    function limitClose(
        uint _id,
        bool _tp,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    )
        external
    {
        _checkDelay(_id, false);
        _checkGas();
        IPosition.Trade memory _trade = position.trades(_id);
        uint256 _price = TradingLibrary.verifyAndCreatePrice(minNodeCount, validSignatureTimer, _trade.asset, chainlinkEnabled, pairsContract.idToAsset(_trade.asset).chainlinkFeed, _priceData, _signature, nodeProvided, isNode);
        if (_trade.orderType != 0) revert IsLimit();
        uint _limitPrice;
        if (_tp) {
            if (_trade.tpPrice == 0) revert LimitNotSet();
            if (_trade.direction) {
                if (_trade.tpPrice > _price) revert LimitNotMet();
            } else {
                if (_trade.tpPrice < _price) revert LimitNotMet();
            }
            _limitPrice = _trade.tpPrice;
        } else {
            if (_trade.slPrice == 0) revert LimitNotSet();
            if (_trade.direction) {
                if (_trade.slPrice < _price) revert LimitNotMet();
            } else {
                if (_trade.slPrice > _price) revert LimitNotMet();
            }
            _limitPrice = _trade.slPrice;
        }
        _closePosition(_id, DIVISION_CONSTANT, _limitPrice, address(0), _trade.tigAsset);
    }



    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev close the initiated position.
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed in BP
     * @param _price asset price
     * @param _stableVault StableVault address
     * @param _outputToken Token that trader will receive
     */
    function _closePosition(
        uint _id,
        uint _percent,
        uint _price,
        address _stableVault,
        address _outputToken
    )
        internal
    {
        IPosition.Trade memory _trade = position.trades(_id);
        (uint256 _positionSize, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
        unchecked {
            if (_trade.direction) {
                pairsContract.modifyLongOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);
            } else {
                pairsContract.modifyShortOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);     
            }
        }
        position.setAccInterest(_id);
        updateFunding(_trade.asset, _trade.tigAsset);
        if (_percent < DIVISION_CONSTANT) {
            if ((_trade.margin*_trade.leverage*(DIVISION_CONSTANT-_percent)/DIVISION_CONSTANT)/1e18 < minPositionSize[_trade.tigAsset]) revert BelowMinPositionSize();
            position.reducePosition(_id, _percent);
        } else {
            position.burn(_id);
        }
        uint256 _toMint;
        if (_payout > 0) {
            unchecked {
                _toMint = _handleCloseFees(_trade.asset, uint256(_payout)*_percent/DIVISION_CONSTANT, _trade.tigAsset, _positionSize*_percent/DIVISION_CONSTANT, _trade.trader);
                if (maxWinPercent > 0 && _toMint > _trade.margin*maxWinPercent/DIVISION_CONSTANT) {
                    _toMint = _trade.margin*maxWinPercent/DIVISION_CONSTANT;
                }
            }
            _handleWithdraw(_trade, _stableVault, _outputToken, _toMint);
        }
        emit PositionClosed(_id, _price, _percent, _toMint, _trade.trader, _msgSender());
    }

    function _handleDeposit(address _tigAsset, address _marginAsset, uint256 _margin, address _stableVault, ERC20PermitData calldata _permitData) internal {
        IStable tigAsset = IStable(_tigAsset);
        address msgSender = _msgSender();
        if (_tigAsset != _marginAsset) {
            if (msg.value > 0) {
                if (_marginAsset != eth) revert BadDeposit();
            } else {
                if (_permitData.usePermit) {
                    ERC20Permit(_marginAsset).permit(msgSender, address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);
                }
            }
            uint256 _balBefore = tigAsset.balanceOf(address(this));
            if (_marginAsset != eth){
                uint _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());
                IERC20(_marginAsset).transferFrom(msgSender, address(this), _margin/_marginDecMultiplier);
                IERC20(_marginAsset).approve(_stableVault, type(uint).max);
                IStableVault(_stableVault).deposit(_marginAsset, _margin/_marginDecMultiplier);
                if (tigAsset.balanceOf(address(this)) != _balBefore + _margin) revert BadDeposit();
                tigAsset.burnFrom(address(this), tigAsset.balanceOf(address(this)));
            } else {
                if (msg.value != _margin) revert ValueNotEqualToMargin();
                try INativeStableVault(_stableVault).depositNative{value: _margin}() {} catch {
                    revert NotNativeSupport();
                }
                if (tigAsset.balanceOf(address(this)) != _balBefore + _margin) revert BadDeposit();
                tigAsset.burnFrom(address(this), _margin);
            }
        } else {
            tigAsset.burnFrom(msgSender, _margin);
        }        
    }

    function _handleWithdraw(IPosition.Trade memory _trade, address _stableVault, address _outputToken, uint _toMint) internal {
        IStable(_trade.tigAsset).mintFor(address(this), _toMint);
        if (_outputToken == _trade.tigAsset) {
            IERC20(_outputToken).transfer(_trade.trader, _toMint);
        } else {
            if (_outputToken != eth) {
                uint256 _balBefore = IERC20(_outputToken).balanceOf(address(this));
                IStableVault(_stableVault).withdraw(_outputToken, _toMint);
                if (IERC20(_outputToken).balanceOf(address(this)) != _balBefore + _toMint/(10**(18-ExtendedIERC20(_outputToken).decimals()))) revert BadWithdraw();
                IERC20(_outputToken).transfer(_trade.trader, IERC20(_outputToken).balanceOf(address(this)) - _balBefore);          
            } else {
                uint256 _balBefore = address(this).balance;
                try INativeStableVault(_stableVault).withdrawNative(_toMint) {} catch {
                    revert NotNativeSupport();
                }
                if (address(this).balance != _balBefore + _toMint) revert BadWithdraw();
                payable(_msgSender()).transfer(address(this).balance - _balBefore);
            }
        }        
    }

    /**
     * @dev handle fees distribution after closing
     * @param _asset asset id
     * @param _payout payout to trader before fees
     * @param _tigAsset margin asset
     * @param _positionSize position size + pnl
     * @param _trader trader address
     * @return payout_ payout to trader after fees
     */
    function _handleCloseFees(
        uint _asset,
        uint _payout,
        address _tigAsset,
        uint _positionSize,
        address _trader
    )
        internal
        returns (uint payout_)
    {
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
        uint _daoFeesPaid;
        uint _burnFeesPaid;
        uint _referralFeesPaid;
        unchecked {
            _daoFeesPaid = (_positionSize*daoFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _burnFeesPaid = (_positionSize*burnFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _referralFeesPaid = (_positionSize*referralFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
        }
        uint _botFeesPaid;
        address _referrer = referrals.getReferral(referrals.getReferred(_trader));
        if (_referrer != address(0)) {
            IStable(_tigAsset).mintFor(
                _referrer,
                _referralFeesPaid
            );
            unchecked {
                _daoFeesPaid = _daoFeesPaid-_referralFeesPaid;
            }
        }
        if (_trader != _msgSender()) {
            unchecked {
                _botFeesPaid = (_positionSize*botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
                IStable(_tigAsset).mintFor(
                    _msgSender(),
                    _botFeesPaid
                );
                _daoFeesPaid = _daoFeesPaid - _botFeesPaid;
            }
        }
        payout_ = _payout - _daoFeesPaid - _burnFeesPaid - _botFeesPaid;
        IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
        gov.distribute(_tigAsset, _daoFeesPaid);
        return payout_;
    }

    function updateFunding(uint256 _asset, address _tigAsset) internal {
        position.updateFunding(
            _asset,
            _tigAsset,
            pairsContract.idToOi(_asset, _tigAsset).longOi,
            pairsContract.idToOi(_asset, _tigAsset).shortOi,
            pairsContract.idToAsset(_asset).baseFundingRate,
            vaultFundingPercent
        );
    }

    function _setReferral(bytes32 _referral) internal {
        if (_referral != bytes32(0)) {
            if (referrals.getReferral(_referral) != address(0)) {
                if (referrals.getReferred(_msgSender()) == bytes32(0)) {
                    referrals.setReferred(_msgSender(), _referral);
                }
            }
        }
    }

    /**
     * @dev validates the inputs of trades
     * @param _asset asset id
     * @param _tigAsset margin asset
     * @param _margin margin
     * @param _leverage leverage
     */
    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) internal view {
        unchecked {
            IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
            if (!allowedMargin[_tigAsset]) revert NotMargin();
            if (paused) revert TradingPaused();
            if (!pairsContract.allowedAsset(_asset)) revert NotAllowedPair();
            if (_leverage < asset.minLeverage || _leverage > asset.maxLeverage) revert BadLeverage();
            if (_margin*_leverage/1e18 < minPositionSize[_tigAsset]) revert BelowMinPositionSize();
        }
    }

    function _checkSl(uint _sl, bool _direction, uint _price) internal pure {
        if (_direction) {
            if (_sl > _price) revert BadStopLoss();
        } else {
            if (_sl < _price && _sl != 0) revert BadStopLoss();
        }
    }

    function _checkOwner(uint _id) internal view {
        if (position.ownerOf(_id) != _msgSender()) revert NotPositionOwner();    
    }

    function _checkGas() internal view {
        if (tx.gasprice > maxGasPrice) revert GasPriceTooHigh();
    }

    function _checkDelay(uint _id, bool _type) internal {
        unchecked {
            Delay memory _delay = blockDelayPassed[_id];
            if (_delay.actionType == _type) {
                blockDelayPassed[_id].delay = block.number + blockDelay;
            } else {
                if (block.number < _delay.delay) revert Wait();
                blockDelayPassed[_id].delay = block.number + blockDelay;
                blockDelayPassed[_id].actionType = _type;
            }
        }
    }

    // ===== GOVERNANCE-ONLY =====

    /**
     * @notice in blocks not seconds
     */
    function setBlockDelay(
        uint _blockDelay
    )
        external
        onlyOwner
    {
        blockDelay = _blockDelay;
    }

    function setMaxWinPercent(
        uint _maxWinPercent
    )
        external
        onlyOwner
    {
        maxWinPercent = _maxWinPercent;
    }

    function setValidSignatureTimer(
        uint _validSignatureTimer
    )
        external
        onlyOwner
    {
        validSignatureTimer = _validSignatureTimer;
    }

    function setMinNodeCount(
        uint _minNodeCount
    )
        external
        onlyOwner
    {
        minNodeCount = _minNodeCount;
    }

    /**
     * @dev Allows a tigAsset to be used
     * @param _tigAsset tigAsset
     * @param _bool bool
     */
    function setAllowedMargin(
        address _tigAsset,
        bool _bool
    ) 
        external
        onlyOwner
    {
        allowedMargin[_tigAsset] = _bool;
        IStable(_tigAsset).approve(address(gov), type(uint).max);
    }

    /**
     * @dev changes the minimum position size
     * @param _tigAsset tigAsset
     * @param _min minimum position size 18 decimals
     */
    function setMinPositionSize(
        address _tigAsset,
        uint _min
    ) 
        external
        onlyOwner
    {
        minPositionSize[_tigAsset] = _min;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
    }

    function setLimitOrderPriceRange(uint _range) external onlyOwner {
        limitOrderPriceRange = _range;
    }

    /**
     * @dev Sets the fees for the trading protocol
     * @param _daoFees Fees distributed to the DAO
     * @param _burnFees Fees which get burned
     * @param _referralFees Fees given to referrers
     * @param _botFees Fees given to bots that execute limit orders
     */
    function setFees(uint _daoFees, uint _burnFees, uint _referralFees, uint _botFees, uint _percent) external onlyOwner {
        unchecked {
            require(_daoFees >= _botFees+_referralFees);
            daoFees = _daoFees;
            burnFees = _burnFees;
            referralFees = _referralFees;
            botFees = _botFees;
            require(_percent <= DIVISION_CONSTANT);
            vaultFundingPercent = _percent;
        }
    }

    /**
     * @dev whitelists a node
     * @param _node node address
     * @param _bool bool
     */
    function setNode(address _node, bool _bool) external onlyOwner {
        isNode[_node] = _bool;
    }

    function setChainlinkEnabled(bool _bool) external onlyOwner {
        chainlinkEnabled = _bool;
    }

    // ===== EVENTS =====

    event PositionOpened(
        TradeInfo _tradeInfo,
        uint _orderType,
        uint _price,
        uint _id,
        address _trader
    );

    event PositionClosed(
        uint _id,
        uint _closePrice,
        uint _percent,
        uint _payout,
        address _trader,
        address _executor
    );

    event PositionLiquidated(
        uint _id,
        address _trader,
        address _executor
    );

    event LimitOrderExecuted(
        uint _asset,
        bool _direction,
        uint _openPrice,
        uint _lev,
        uint _margin,
        uint _id,
        address _trader,
        address _executor
    );

    event UpdateTPSL(
        uint _id,
        bool _isTp,
        uint _price,
        address _trader
    );

    event LimitCancelled(
        uint _id,
        address _trader
    );

    event MarginModified(
        uint _id,
        uint _newMargin,
        uint _newLeverage,
        bool _isMarginAdded,
        address _trader
    );

    event AddToPosition(
        uint _id,
        uint _newMargin,
        uint _newPrice,
        address _trader
    );

    receive() external payable {}

}

