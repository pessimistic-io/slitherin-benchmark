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

interface ITradingExtension {
    function getVerifiedPrice(
        uint _asset,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,
        bool _isTrade,
        uint _withSpreadIsLong
    ) external returns(uint256 _price);
    function getRef(
        address _trader
    ) external pure returns(address);
    function _setReferral(
        bytes32 _referral,
        address _trader
    ) external;
    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view;
    function isPaused() external view returns(bool);
    function minPos(address) external view returns(uint);
    function modifyLongOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) external;
    function modifyShortOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) external;
    function paused() external returns(bool);
    function getSpread(uint _asset) external returns(uint);
    function _limitClose(
        uint _id,
        bool _tp,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    ) external returns(uint _limitPrice, address _tigAsset);
    function _checkGas() external view;
    function _closePosition(
        uint _id,
        uint _price,
        uint _percent
    ) external returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout);
}

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

    error LimitNotSet(); //7
    error NotLiquidatable();
    error TradingPaused();
    error NotNativeSupport();
    error BadDeposit();
    error BadWithdraw();
    error ValueNotEqualToMargin();
    error BadLeverage();
    error NotMargin();
    error NotAllowedPair();
    error BelowMinPositionSize();
    error BadClosePercent();
    error NoPrice();
    error LiqThreshold();

    uint constant private DIVISION_CONSTANT = 1e10; // 100%
    address constant private eth = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    uint private constant liqPercent = 9e9; // 90%

    struct Fees {
        uint daoFees;
        uint burnFees;
        uint referralFees;
        uint botFees;
    }
    Fees public openFees = Fees(
        0,
        0,
        0,
        0
    );
    Fees public closeFees = Fees(
        0,
        0,
        0,
        0
    );
    uint public limitOrderPriceRange = 1e8; // 1%

    uint public maxWinPercent;
    uint public vaultFundingPercent;

    IPairsContract private pairsContract;
    IPosition private position;
    IGovNFT private gov;
    ITradingExtension private tradingExtension;

    struct Delay {
        uint delay; // Block number where delay ends
        bool actionType; // True for open, False for close
    }
    mapping(uint => Delay) public blockDelayPassed; // id => Delay
    uint public blockDelay;
    mapping(uint => uint) public limitDelay; // id => block.timestamp

    constructor(
        address _position,
        address _gov,
        address _pairsContract
    )
    {
        position = IPosition(_position);
        gov = IGovNFT(_gov);
        pairsContract = IPairsContract(_pairsContract);
    }

    function setTradingExtension(
        address _ext
    ) external onlyOwner() {
        tradingExtension = ITradingExtension(_ext);
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
        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        tradingExtension._setReferral(_tradeInfo.referral, _msgSender());
        uint256 _fee = _handleOpenFees(_tradeInfo.asset, _tradeInfo.margin*_tradeInfo.leverage/1e18, _msgSender(), _tigAsset);
        uint256 _positionSize = (_tradeInfo.margin - _fee) * _tradeInfo.leverage / 1e18;
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData);
        uint _withSpreadIsLong = _tradeInfo.direction ? 1 : 2;
        uint256 _price = tradingExtension.getVerifiedPrice(_tradeInfo.asset, _priceData, _signature, true, _withSpreadIsLong);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        unchecked {
            if (_tradeInfo.direction) {
                tradingExtension.modifyLongOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
            }
        }
        updateFunding(_tradeInfo.asset, _tigAsset);
        position.mint(
            IPosition.MintTrade(
                _msgSender(),
                _tradeInfo.margin - _fee,
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
        if (_trade.orderType != 0) revert("4"); //IsLimit        
        uint256 _price = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, true, 0);

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
        tradingExtension.validateTrade(_trade.asset, _trade.tigAsset, _trade.margin + _addMargin, _trade.leverage);
        if (_trade.orderType != 0) revert("4"); //IsLimit
        uint _fee = _handleOpenFees(_trade.asset, _addMargin*_trade.leverage/1e18, _msgSender(), _trade.tigAsset);
        _handleDeposit(
            _trade.tigAsset,
            _marginAsset,
            _addMargin - _fee,
            _stableVault,
            _permitData
        );
        position.setAccInterest(_id);
        unchecked {
            uint _positionSize = (_addMargin - _fee) * _trade.leverage / 1e18;
            if (_trade.direction) {
                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, true, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, true, _positionSize);     
            }
            updateFunding(_trade.asset, _trade.tigAsset);
            _addMargin -= _fee;
            uint _newMargin = _trade.margin + _addMargin;
            uint _newPrice;
            {
                uint256 _price = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, true, _trade.direction ? 1 : 2);
                _newPrice = _trade.price*_trade.margin/_newMargin + _price*_addMargin/_newMargin;
            }

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
        ERC20PermitData calldata _permitData
    )
        external payable
    {
        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        if (_orderType == 0) revert("5");
        if (_price == 0) revert NoPrice();
        tradingExtension._setReferral(_tradeInfo.referral, _msgSender());
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        uint256 _id = position.getCount();
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
        limitDelay[_id] = block.timestamp + 10;
        emit PositionOpened(_tradeInfo, _orderType, _price, _id, _msgSender());
    }

    function cancelLimitOrder(
        uint256 _id
    )
        external
    {
        _checkOwner(_id);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType == 0) revert("5");
        IStable(_trade.tigAsset).mintFor(_msgSender(), _trade.margin);
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
        if (_trade.orderType != 0) revert("4"); //IsLimit
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData);
        unchecked {
            uint256 _newMargin = _trade.margin + _addMargin;
            uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
            if (_newLeverage < asset.minLeverage) revert("!lev");
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
        if (_trade.orderType != 0) revert("4"); //IsLimit
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        uint256 _newMargin = _trade.margin - _removeMargin;
        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
        if (_newLeverage > asset.maxLeverage) revert("!lev");
        uint _assetPrice = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, true, 0);
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
        if (_trade.orderType != 0) revert("4"); //IsLimit
        if (_type) {
            position.modifyTp(_id, _limitPrice);
        } else {
            uint256 _price = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, true, 0);
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
            tradingExtension._checkGas();
            if (tradingExtension.paused()) revert TradingPaused();
            require(block.timestamp >= limitDelay[_id]);
            IPosition.Trade memory trade = position.trades(_id);
            IPairsContract.Asset memory asset = pairsContract.idToAsset(trade.asset);
            uint256 _refFee = (trade.margin*trade.leverage/1e18)*openFees.referralFees*asset.feeMultiplier/DIVISION_CONSTANT/DIVISION_CONSTANT;
            IStable(trade.tigAsset).mintFor(
                trade.trader,
                _refFee
            );
            uint _fee = _handleOpenFees(trade.asset, trade.margin*trade.leverage/1e18, trade.trader, trade.tigAsset);
            uint256 _price = tradingExtension.getVerifiedPrice(trade.asset, _priceData, _signature, false, 0);
            if (trade.orderType == 0) revert("5");
            if (_price > trade.price+trade.price*limitOrderPriceRange/DIVISION_CONSTANT || _price < trade.price-trade.price*limitOrderPriceRange/DIVISION_CONSTANT) revert("6"); //LimitNotMet
            _price = tradingExtension.getVerifiedPrice(trade.asset, _priceData, _signature, false, trade.direction ? 1 : 2);
            if (trade.direction && trade.orderType == 1) {
                if (trade.price < _price) revert("6"); //LimitNotMet
            } else if (!trade.direction && trade.orderType == 1) {
                if (trade.price > _price) revert("6"); //LimitNotMet      
            } else if (!trade.direction && trade.orderType == 2) {
                if (trade.price < _price) revert("6"); //LimitNotMet
                trade.price = _price;
            } else {
                if (trade.price > _price) revert("6"); //LimitNotMet
                trade.price = _price;
            }
            if (trade.direction) {
                tradingExtension.modifyLongOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            } else {
                tradingExtension.modifyShortOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            }
            updateFunding(trade.asset, trade.tigAsset);
            position.executeLimitOrder(_id, trade.price, trade.margin - _fee);
            emit LimitOrderExecuted(trade.asset, trade.direction, trade.price, trade.leverage, trade.margin - _fee, _id, trade.trader, _msgSender());
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
            tradingExtension._checkGas();
            IPosition.Trade memory _trade = position.trades(_id);
            if (_trade.orderType != 0) revert("4"); //IsLimit

            uint256 _price = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, false, 0);
            (uint256 _positionSizeAfterPrice, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
            uint256 _positionSize = _trade.margin*_trade.leverage/1e18;
            if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert NotLiquidatable();
            if (_trade.direction) {
                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, false, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, false, _positionSize);
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
        (uint _limitPrice, address _tigAsset) = tradingExtension._limitClose(_id, _tp, _priceData, _signature);
        _closePosition(_id, DIVISION_CONSTANT, _limitPrice, address(0), _tigAsset);
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
        (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) = tradingExtension._closePosition(_id, _price, _percent);
        position.setAccInterest(_id);
        updateFunding(_trade.asset, _trade.tigAsset);
        if (_percent < DIVISION_CONSTANT) {
            if ((_trade.margin*_trade.leverage*(DIVISION_CONSTANT-_percent)/DIVISION_CONSTANT)/1e18 < tradingExtension.minPos(_trade.tigAsset)) revert("!size");
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
        if (_tigAsset != _marginAsset) {
            if (msg.value > 0) {
                if (_marginAsset != eth) revert BadDeposit();
            } else {
                if (_permitData.usePermit) {
                    ERC20Permit(_marginAsset).permit(_msgSender(), address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);
                }
            }
            uint256 _balBefore = tigAsset.balanceOf(address(this));
            if (_marginAsset != eth){
                uint _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());
                IERC20(_marginAsset).transferFrom(_msgSender(), address(this), _margin/_marginDecMultiplier);
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
            tigAsset.burnFrom(_msgSender(), _margin);
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
     * @dev handle fees distribution and margin size after fees for opening
     * @param _asset asset id
     * @param _positionSize position size
     * @param _trader trader address
     * @param _tigAsset tigAsset address
     */
    function _handleOpenFees(
        uint _asset,
        uint _positionSize,
        address _trader,
        address _tigAsset
    )
        internal
        returns (uint _feePaid)
    {
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
        Fees memory _fees = openFees;
        unchecked {
            _fees.daoFees = _fees.daoFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.burnFees = _fees.burnFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.referralFees = _fees.referralFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.botFees = _fees.botFees * asset.feeMultiplier / DIVISION_CONSTANT;
        }
        address _referrer = tradingExtension.getRef(_trader); //referrals.getReferral(referrals.getReferred(_trader));
        if (_referrer != address(0)) {
            unchecked {
                IStable(_tigAsset).mintFor(
                    _referrer,
                    _positionSize
                    * _fees.referralFees // get referral fee%
                    / DIVISION_CONSTANT // divide by 100%
                );
            }
            _fees.daoFees = _fees.daoFees - _fees.referralFees*2;
        }
        if (_trader != _msgSender()) {
            unchecked {
                IStable(_tigAsset).mintFor(
                    _msgSender(),
                    _positionSize
                    * _fees.botFees // get bot fee%
                    / DIVISION_CONSTANT // divide by 100%
                );
            }
            _fees.daoFees = _fees.daoFees - _fees.botFees;
        } else {
            _fees.botFees = 0;
        }
        unchecked {
            uint _daoFeesPaid = _positionSize * _fees.daoFees / DIVISION_CONSTANT;
            _feePaid =
                _positionSize
                * (_fees.burnFees + _fees.botFees) // get total fee%
                / DIVISION_CONSTANT // divide by 100%
                + _daoFeesPaid;
            emit FeesDistributed(
                _tigAsset,
                _daoFeesPaid,
                _positionSize * _fees.burnFees / DIVISION_CONSTANT,
                _referrer != address(0) ? _positionSize * _fees.referralFees / DIVISION_CONSTANT : 0,
                _positionSize * _fees.botFees / DIVISION_CONSTANT,
                _referrer
            );
            IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
        }
        gov.distribute(_tigAsset, IStable(_tigAsset).balanceOf(address(this)));
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
        Fees memory _fees = closeFees;
        uint _daoFeesPaid;
        uint _burnFeesPaid;
        uint _referralFeesPaid;
        unchecked {
            _daoFeesPaid = (_positionSize*_fees.daoFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _burnFeesPaid = (_positionSize*_fees.burnFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
        }
        uint _botFeesPaid;
        address _referrer = tradingExtension.getRef(_trader);//referrals.getReferral(referrals.getReferred(_trader));
        if (_referrer != address(0)) {
            unchecked {
                _referralFeesPaid = (_positionSize*_fees.referralFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            }
            IStable(_tigAsset).mintFor(
                _referrer,
                _referralFeesPaid
            );
             _daoFeesPaid = _daoFeesPaid-_referralFeesPaid*2;
        }
        if (_trader != _msgSender()) {
            unchecked {
                _botFeesPaid = (_positionSize*_fees.botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
                IStable(_tigAsset).mintFor(
                    _msgSender(),
                    _botFeesPaid
                );
            }
            _daoFeesPaid = _daoFeesPaid - _botFeesPaid;
        }
        emit FeesDistributed(_tigAsset, _daoFeesPaid, _burnFeesPaid, _referralFeesPaid, _botFeesPaid, _referrer);
        payout_ = _payout - _daoFeesPaid - _burnFeesPaid - _botFeesPaid;
        IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
        IStable(_tigAsset).approve(address(gov), type(uint).max);
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

    function _checkSl(uint _sl, bool _direction, uint _price) internal pure {
        if (_direction) {
            if (_sl > _price) revert("3"); //BadStopLoss
        } else {
            if (_sl < _price && _sl != 0) revert("3"); //BadStopLoss
        }
    }

    function _checkOwner(uint _id) internal view {
        if (position.ownerOf(_id) != _msgSender()) revert("2"); //NotPositionOwner   
    }

    function _checkDelay(uint _id, bool _type) internal {
        unchecked {
            Delay memory _delay = blockDelayPassed[_id];
            if (_delay.actionType == _type) {
                blockDelayPassed[_id].delay = block.number + blockDelay;
            } else {
                if (block.number < _delay.delay) revert("0"); //Wait
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
    function setFees(bool _open, uint _daoFees, uint _burnFees, uint _referralFees, uint _botFees, uint _percent) external onlyOwner {
        unchecked {
            require(_daoFees >= _botFees+_referralFees*2);
            if (_open) {
                openFees.daoFees = _daoFees;
                openFees.burnFees = _burnFees;
                openFees.referralFees = _referralFees;
                openFees.botFees = _botFees;
            } else {
                closeFees.daoFees = _daoFees;
                closeFees.burnFees = _burnFees;
                closeFees.referralFees = _referralFees;
                closeFees.botFees = _botFees;                
            }
            require(_percent <= DIVISION_CONSTANT);
            vaultFundingPercent = _percent;
        }
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

    event FeesDistributed(
        address _tigAsset,
        uint _daoFees,
        uint _burnFees,
        uint _refFees,
        uint _botFees,
        address _referrer
    );

    receive() external payable {}
}

