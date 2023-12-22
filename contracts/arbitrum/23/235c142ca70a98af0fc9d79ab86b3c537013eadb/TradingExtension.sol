// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IPairsContract.sol";
import "./TradingLibrary.sol";
import "./IReferrals.sol";
import "./IPosition.sol";
import "./ITradingExtension.sol";

contract TradingExtension is ITradingExtension, Ownable {

    uint256 constant private DIVISION_CONSTANT = 1e10; // 100%

    address public immutable trading;
    bool public chainlinkEnabled;
    bool public paused;
    uint256 public validSignatureTimer;

    mapping(address => bool) private isNode;
    mapping(address => uint) public minPositionSize;
    mapping(address => bool) public allowedMargin;

    IPairsContract private immutable pairsContract;
    IReferrals private immutable referrals;
    IPosition private immutable position;

    event SetAllowedMargin(address _token, bool _isAllowed);
    event SetNode(address _node, bool _isNode);
    event SetChainlinkEnabled(bool _isEnabled);
    event SetValidSignatureTimer(uint256 _time);

    modifier onlyProtocol {
        require(msg.sender == trading, "!protocol");
        _;
    }

    constructor(
        address _trading,
        address _pairsContract,
        address _ref,
        address _position
    )
    {
        if (_trading == address(0)
        || _pairsContract == address(0)
        || _ref == address(0)
            || _position == address(0)
        ) revert BadConstructor();
        trading = _trading;
        pairsContract = IPairsContract(_pairsContract);
        referrals = IReferrals(_ref);
        position = IPosition(_position);
    }

    /**
    * @notice returns the minimum position size per collateral asset
    * @param _asset address of the asset
    */
    function minPos(
        address _asset
    ) external view returns(uint) {
        return minPositionSize[_asset];
    }

    /**
    * @notice limitClose helper
    * @dev only callable by trading contract
    * @param _id id of the position NFT
    * @param _tp true if takeprofit, else stoploss
    * @param _priceData price data object came from the price oracle
    * @return _limitPrice price of sl or tp returned from positions contract
    * @return _tigAsset address of the position collateral asset
    */
    function _limitClose(
        uint256 _id,
        bool _tp,
        PriceData calldata _priceData
    ) external view returns(uint256 _limitPrice, address _tigAsset) {
        IPosition.Trade memory _trade = position.trades(_id);
        _tigAsset = _trade.tigAsset;

        (uint256 _price,) = getVerifiedPrice(_trade.asset, _priceData, 0);

        if (_trade.orderType != 0) revert IsLimit();

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
    }

    /**
     * @dev Gets the referrer of a trader and the referrer's rebate percentage
     * @param _trader address of the trader
     * @return address of the referrer
     * @return rebate percentage
     */
    function getRef(
        address _trader
    ) external view returns(address, uint) {
        return referrals.getReferred(_trader);
    }

    /**
     * @dev Stores the referral fees earned by a referrer
     * @param _referrer address of the referrer
     * @param _tigAsset address of the collateral asset
     * @param _fees amount of fees earned
     */
    function addRefFees(
        address _referrer,
        address _tigAsset,
        uint _fees
    ) external onlyProtocol {
        referrals.addRefFees(_referrer, _tigAsset, _fees);
    }

    /**
    * @notice verifies the signed price and returns it
    * @param _asset id of position asset
    * @param _priceData price data object came from the price oracle
    * @param _withSpreadIsLong 0, 1, or 2 - to specify if we need the price returned to be after spread
    * @return _price price after verification and with spread if _withSpreadIsLong is 1 or 2
    * @return _spread spread after verification
    */
    function getVerifiedPrice(
        uint256 _asset,
        PriceData calldata _priceData,
        uint8 _withSpreadIsLong
    )
        public view
        returns(uint256 _price, uint256 _spread)
    {
        TradingLibrary.verifyPrice(
            validSignatureTimer,
            _asset,
            chainlinkEnabled,
            pairsContract.idToAsset(_asset).chainlinkFeed,
            _priceData,
            isNode
        );
        _price = _priceData.price;
        _spread = _priceData.spread;

        if(_withSpreadIsLong == 1)
            _price += _price * _spread / DIVISION_CONSTANT;
        else if(_withSpreadIsLong == 2)
            _price -= _price * _spread / DIVISION_CONSTANT;
    }

    function setReferral(
        address _referrer,
        address _trader
    ) external onlyProtocol {
        referrals.setReferred(_trader, _referrer);
    }

    /**
     * @dev validates the inputs of trades
     * @param _asset asset id
     * @param _tigAsset margin asset
     * @param _margin margin
     * @param _leverage leverage
     * @param _orderType market, limit, stop order types
     */
    function validateTrade(uint256 _asset, address _tigAsset, uint256 _margin, uint256 _leverage, uint256 _orderType) external view {
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
        if (!allowedMargin[_tigAsset]) revert("!margin");
        if (paused) revert("paused");
        if (!pairsContract.allowedAsset(_asset)) revert("!allowed");
        if (_leverage < asset.minLeverage || _leverage > asset.maxLeverage) revert("!lev");
        if (_margin*_leverage/1e18 < minPositionSize[_tigAsset]) revert("!size");
        if (_orderType > 2) revert("!orderType");
    }

    /**
     * @dev Sets the time for which a signature is valid
     * @param _time time in seconds
     */
    function setValidSignatureTimer(
        uint256 _time
    )
        external
        onlyOwner
    {
        validSignatureTimer = _time;
    }

    /**
     * @dev Enables or disables the use of chainlink for price validation
     * @param _isEnabled if chainlink is enabled
     */
    function setChainlinkEnabled(bool _isEnabled) external onlyOwner {
        chainlinkEnabled = _isEnabled;
    }

    /**
     * @dev whitelists a node
     * @param _node node address
     * @param _isNode if address is set as a node
     */
    function setNode(address _node, bool _isNode) external onlyOwner {
        isNode[_node] = _isNode;
    }

    /**
     * @dev Allows a tigAsset to be used
     * @param _tigAsset tigAsset
     * @param _isAllowed if token is allowed to be used as margin
     */
    function setAllowedMargin(
        address _tigAsset,
        bool _isAllowed
    )
        external
        onlyOwner
    {
        allowedMargin[_tigAsset] = _isAllowed;
    }

    /**
     * @dev changes the minimum position size
     * @param _tigAsset tigAsset
     * @param _min minimum position size 18 decimals
     */
    function setMinPositionSize(
        address _tigAsset,
        uint256 _min
    )
        external
        onlyOwner
    {
        minPositionSize[_tigAsset] = _min;
    }

    /**
     * @dev Pauses or unpauses opening new positions
     * @param _paused If opening new positions is paused
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}
