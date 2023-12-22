//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IPairsContract.sol";
import "./TradingLibrary.sol";
import "./IReferrals.sol";
import "./IPosition.sol";

contract TradingExtension is Ownable{
    uint constant private DIVISION_CONSTANT = 1e10; // 100%

    address public trading;
    uint256 public minNodeCount;
    uint256 public validSignatureTimer;
    bool public chainlinkEnabled;

    mapping(address => bool) private nodeProvided; // Used for TradingLibrary
    mapping(address => bool) private isBotNode;
    mapping(address => bool) private isTradeNode;
    mapping(address => uint) public minPositionSize;
    mapping(address => bool) public allowedMargin;
    mapping(uint => uint) public spread;
    bool public paused;

    IPairsContract private pairsContract;
    IReferrals private referrals;
    IPosition private position;

    uint public maxGasPrice = 1000000000000; // 1000 gwei

    constructor(
        address _trading,
        address _pairsContract,
        address _ref,
        address _position
    )
    {
        trading = _trading;
        pairsContract = IPairsContract(_pairsContract);
        referrals = IReferrals(_ref);
        position = IPosition(_position);
    }

    function minPos(
        address _asset
    ) external view returns(uint) {
        return minPositionSize[_asset];
    }

    function _closePosition(
        uint _id,
        uint _price,
        uint _percent
    ) external returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) {
        _trade = position.trades(_id);
        (_positionSize, _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);

        unchecked {
            if (_trade.direction) {
                modifyLongOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);
            } else {
                modifyShortOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);     
            }
        }
    }

    function _limitClose(
        uint _id,
        bool _tp,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature
    ) external returns(uint _limitPrice, address _tigAsset) {
        _checkGas();
        IPosition.Trade memory _trade = position.trades(_id);
        _tigAsset = _trade.tigAsset;

        uint256 _price = getVerifiedPrice(_trade.asset, _priceData, _signature, false, 2);

        if (_trade.orderType != 0) revert("4"); //IsLimit

        if (_tp) {
            if (_trade.tpPrice == 0) revert("7"); //LimitNotSet
            if (_trade.direction) {
                if (_trade.tpPrice > _price) revert("6"); //LimitNotMet
            } else {
                if (_trade.tpPrice < _price) revert("6"); //LimitNotMet
            }
            _limitPrice = _trade.tpPrice;
        } else {
            if (_trade.slPrice == 0) revert("7"); //LimitNotSet
            if (_trade.direction) {
                if (_trade.slPrice < _price) revert("6"); //LimitNotMet
            } else {
                if (_trade.slPrice > _price) revert("6"); //LimitNotMet
            }
            _limitPrice = _trade.slPrice;
        }
    }

    function _checkGas() public view {
        if (tx.gasprice > maxGasPrice) revert("1"); //GasTooHigh
    }

    function modifyShortOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) public onlyProtocol {
        

        pairsContract.modifyShortOi(_asset, _tigAsset, _onOpen, _size);
    }

    function modifyLongOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) public onlyProtocol {
        

        pairsContract.modifyLongOi(_asset, _tigAsset, _onOpen, _size);
    }

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
    }

    function getRef(
        address _trader
    ) external view returns(address) {
        return referrals.getReferral(referrals.getReferred(_trader));
    }

    function getVerifiedPrice(
        uint _asset,
        PriceData[] calldata _priceData,
        bytes[] calldata _signature,
        bool _isTrade,
        uint _withSpreadIsLong
    ) 
        public
        returns(uint256 _price) 
    {
        _price = TradingLibrary.verifyAndCreatePrice(
            minNodeCount,
            validSignatureTimer,
            _asset,
            chainlinkEnabled,
            pairsContract.idToAsset(_asset).chainlinkFeed,
            _priceData,
            _signature,
            nodeProvided, 
            _isTrade ? isTradeNode : isBotNode
        );

        if(_withSpreadIsLong == 1) 
            _price += _price * spread[_asset] / DIVISION_CONSTANT;
        else if(_withSpreadIsLong == 2) 
            _price -= _price * spread[_asset] / DIVISION_CONSTANT;
    }

    function _setReferral(
        bytes32 _referral,
        address _trader
    ) external onlyProtocol {
        
        if (_referral != bytes32(0)) {
            if (referrals.getReferral(_referral) != address(0)) {
                if (referrals.getReferred(_trader) == bytes32(0)) {
                    referrals.setReferred(_trader, _referral);
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
    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view {
        unchecked {
            IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
            if (!allowedMargin[_tigAsset]) revert("!margin");
            if (paused) revert("paused");
            if (!pairsContract.allowedAsset(_asset)) revert("!allowed");
            if (_leverage < asset.minLeverage || _leverage > asset.maxLeverage) revert("!lev");
            if (_margin*_leverage/1e18 < minPositionSize[_tigAsset]) revert("!size");
        }
    }

    function setMinNodeCount(
        uint _minNodeCount
    )
        external
        onlyOwner
    {
        minNodeCount = _minNodeCount;
    }

    function setValidSignatureTimer(
        uint _validSignatureTimer
    )
        external
        onlyOwner
    {
        validSignatureTimer = _validSignatureTimer;
    }

    function setChainlinkEnabled(bool _bool) external onlyOwner {
        chainlinkEnabled = _bool;
    }

    function setSpread(
        uint _asset,
        uint _spread
    )
        external
        onlyOwner
    {
        require(_spread <= DIVISION_CONSTANT, "!spread");
        spread[_asset] = _spread;
    }

    /**
     * @dev whitelists a node
     * @param _node node address
     * @param _bool bool
     */
    function setTradeNode(address _node, bool _bool) external onlyOwner {
        isTradeNode[_node] = _bool;
    }

    /**
     * @dev whitelists a node
     * @param _node node address
     * @param _bool bool
     */
    function setBotNode(address _node, bool _bool) external onlyOwner {
        isBotNode[_node] = _bool;
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

    modifier onlyProtocol { 
        require(msg.sender == trading, "!protocol");
        _;
    }
}
