// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./AggregatorV3Interface.sol";
import "./IEDEPriceFeed.sol";
import "./IVaultPriceFeedV3Fast.sol";


interface PythStructs {
    struct Price {
        int64 price;// Price
        uint64 conf;// Confidence interval around the price
        int32 expo;// Price exponent
        uint publishTime;// Unix timestamp describing when the price was published
    }
    // PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        bytes32 id;// The price ID.
        Price price;// Latest available price
        Price emaPrice;// Latest available exponentially-weighted moving average price
    }
}

interface IPyth {
    function queryPriceFeed(bytes32 id) external view returns (PythStructs.Price memory price);
    function priceFeedExists(bytes32 id) external view returns (bool exists);
    function getValidTimePeriod() external view returns(uint validTimePeriod);
    function getPrice(bytes32 id) external view returns (PythStructs.Price memory price);
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);
    function getEmaPrice(bytes32 id) external view returns (PythStructs.Price memory price);
}


interface IPositionRouter {
    function increasePositionRequestKeysStart() external returns (uint256);
    function decreasePositionRequestKeysStart() external returns (uint256);
    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function getRequestQueueLengths()external view returns (uint256, uint256, uint256, uint256);
}

interface ISWPRouter {
    function getEmaPrice(address _token) external view returns (uint256);
    function getDepthFactor(address _token) external view returns (uint256);
}


contract VaultPriceFeedV3Fast is IVaultPriceFeedV3Fast, Ownable {
    using SafeMath for uint256;

    bytes constant prefix = "\x19Ethereum Signed Message:\n32";
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_PRICE_VARIANCE_PER_1M = 1000;

    uint256 public priceSafetyGap = 360 minutes;
    uint256 public priceVariance = 50; //1%
    uint256 public constant PRICE_VARIANCE_PRECISION = 10000;

    IPyth public pyth;
    ISWPRouter public swpRouter;
    IEDEPriceFeed public edeOracle;

    //parameters for sign update
    uint8 public priceMethod = 3;
    mapping(address => bool) public isUpdater;

    //token config.
    mapping(address => uint256) public chainlinkPrecision;
    mapping(address => address) public chainlinkAddress;
    mapping(address => bytes32) public tokenPythKEY;
    mapping(address => uint256) public spreadBasisPoints;

    mapping(address => bool) public override isAdjustmentAdditive;
    mapping(address => uint256) public override adjustmentBasisPoints;
    mapping(address => uint256) public lastAdjustmentTimings;
    mapping(address => uint256) public latestPriceFeedTime;


    
    //pos.r.
    address[] public positionRouters;

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    //contract setting
    function setSWPRouter(address _swpRouter) external onlyOwner{
        swpRouter = ISWPRouter(_swpRouter);
    }
    function setPyth(address _pyth) external onlyOwner{
        pyth = IPyth(_pyth);
    }
    function setPythConfig(address _token, bytes32 _key) external onlyOwner {
        if (_key != bytes32(0)){
            require(pyth.priceFeedExists(_key), "key not exist in pyth");
        }
        tokenPythKEY[_token] = _key;
    }
    function setEDEOracle(address _edeOra) external onlyOwner{
        edeOracle = IEDEPriceFeed(_edeOra);
    }
    function setTokenChainlinkConfig(address _token, address _chainlinkContract, bool) external override onlyOwner {
        uint256 chainLinkDecimal = uint256(AggregatorV3Interface(_chainlinkContract).decimals());
        require(chainLinkDecimal < 20 && chainLinkDecimal > 0, "invalid chainlink decimal");
        chainlinkAddress[_token] = _chainlinkContract;
        chainlinkPrecision[_token] = 10 ** chainLinkDecimal;
    }

    function setTokenCfgList(address[] memory _tokenList, address[] memory _chkList, bytes32[] memory _key) external onlyOwner {
        for(uint8 i = 0; i < _tokenList.length; i++){
            if (_chkList[i] != address(0)){
                uint256 chainLinkDecimal = uint256(AggregatorV3Interface(_chkList[i]).decimals());
                require(chainLinkDecimal < 20 && chainLinkDecimal > 0, "invalid chainlink decimal");
                chainlinkAddress[_tokenList[i]] = _chkList[i];
                chainlinkPrecision[_tokenList[i]] = 10 ** chainLinkDecimal;
            }
            if (_key[i]!= bytes32(0)){
                tokenPythKEY[_tokenList[i]] = _key[i];
            }
        }
    }




    function setPriceMethod(uint8 _setT) external onlyOwner{
        priceMethod = _setT;
    }
    function setPriceVariance(uint256 _priceVariance) external onlyOwner {
        require(_priceVariance < PRICE_VARIANCE_PRECISION.div(2), "invalid variance");
        priceVariance = _priceVariance;
    }
    function setSafePriceTimeGap(uint256 _gap) external onlyOwner {
        priceSafetyGap = _gap;
    }
    
    //settings for updater
    function setUpdater(address _account, bool _isActive) external onlyOwner {
        isUpdater[_account] = _isActive;
    }

    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyOwner {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyOwner {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function _getCombPrice(address _token, bool _maximise) internal view returns (uint256){
        uint256 cur_timestamp = block.timestamp;

        uint256 onchain_price = 0;
        uint256 onchain_updateTime = 0;
        {
            (uint256 priceCl, bool stateCl, uint256 clUpdatedTime) = getChainlinkPrice(_token);
            (uint256 pricePy, bool statePy, uint256 pyUpdatedTime) = getPythPrice(_token);
            if (pyUpdatedTime > clUpdatedTime && statePy && pyUpdatedTime > cur_timestamp.sub(priceSafetyGap)){
                onchain_price = pricePy;
                onchain_updateTime = pyUpdatedTime;
            }
            else if (clUpdatedTime > pyUpdatedTime && stateCl && clUpdatedTime > cur_timestamp.sub(priceSafetyGap)){
                onchain_price = priceCl;
                onchain_updateTime = clUpdatedTime;
            }
        }

        uint256 price = 0;
        uint256 updateTime = 0;
        (uint256 pricePr, bool statePr, uint256 prUpdatedTime) = getPrimaryPriceFast(_token);
            //condition: ede oracle fails
        if (!statePr || prUpdatedTime < cur_timestamp.sub(priceSafetyGap)){
            price = onchain_price;
            updateTime = onchain_updateTime;
        }
        else{
            //condition: ede oracle works
            if (onchain_price < 10){ //onchain fails
                price = pricePr;
                updateTime = prUpdatedTime;
            }
            else{
                uint256 price_minBound = onchain_price.mul(PRICE_VARIANCE_PRECISION - priceVariance).div(PRICE_VARIANCE_PRECISION);
                uint256 price_maxBound = onchain_price.mul(PRICE_VARIANCE_PRECISION + priceVariance).div(PRICE_VARIANCE_PRECISION);
                if ((pricePr <= price_maxBound) && (pricePr >= price_minBound)) {
                    if (priceMethod == 1){
                        if (_maximise)
                            price = pricePr > onchain_price ? pricePr : onchain_price;
                        else
                            price = pricePr > onchain_price ? onchain_price : pricePr;
                    }
                    else if (priceMethod == 3){
                        if (prUpdatedTime > onchain_updateTime){
                            price = pricePr;
                            updateTime = prUpdatedTime;
                        }
                        else{
                            price = onchain_price;
                            updateTime = onchain_updateTime;
                        }                    
                    }
                    else{
                        price = pricePr;
                        updateTime = prUpdatedTime;
                    }
                }
                else {
                    price = onchain_price;
                    updateTime = onchain_updateTime;
                }
            }
        }
       
        _addBasisSpread(_token, price, _maximise);
        require(price > 0, "all pricefeed fails");
        return price;    
    }

    function _addBasisSpread(address _token, uint256 _price, bool _max)internal view returns (uint256){
        if (spreadBasisPoints[_token] > 0){
            if (_max){
                _price = _price.mul(BASIS_POINTS_DIVISOR.add(spreadBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            }
            else{
                _price = _price.mul(BASIS_POINTS_DIVISOR.sub(spreadBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            }         
        }
        return _price;
    }





    function setPriceSpreadFactor(address _token, uint256 _longPSF, uint256 _shortPSF, uint256 _timestamp) external {
        edeOracle.setPriceSpreadFactor(_token, _longPSF, _shortPSF, _timestamp);
    }

    function setPricesWithBits(uint256[] memory _priceBits, uint256 _timestamp) external {
        edeOracle.setPricesWithBits(_priceBits, _timestamp);
    }

    function setPricesWithBitsSingle(address _token, uint256 _priceBits, uint256 _timestamp) external {
        edeOracle.setPricesWithBitsSingle(_token, _priceBits, _timestamp);
    }

    function setPriceSingle(address _token, uint256 _price, uint256 _timestamp) external {
        edeOracle.setPriceSingle(_token, _price, _timestamp);
    }





    //public read
    function getPrice(address _token, bool _maximise, bool, bool) public override view returns (uint256) {
        // uint256 price = useV2Pricing ? getPriceV2(_token, _maximise, _includeAmmPrice) : getPriceV1(_token, _maximise, _includeAmmPrice);
        uint256 price = _getCombPrice(_token, _maximise);
        if (adjustmentBasisPoints[_token] > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            } else {
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            }
        }
        require(price > 0, "invalid price");
        return price;
    }

    function getOrigPrice(address _token) public override view returns (uint256) {
        return getPrice(_token, true, false, false);
    }


    function priceVariancePer1Million(address ) external pure override returns (uint256){
        return 0;
    }
    function getPriceSpreadImpactFactor(address ) external pure override returns (uint256, uint256){
        return (0,0);
    }


    function getChainlinkPrice(address _token) public view returns (uint256, bool, uint256) {
        if (chainlinkAddress[_token] == address(0)) {
            // revert("chainlink address not set");
            return (0, false, 0);
        }
        if (chainlinkPrecision[_token] < 1) {
            // revert("chainlink precision too small");
            return (0, false, 1);
        }
        (/*uint80 roundId*/, int256 answer, /*uint256 startedAt*/, uint256 updatedAt, /*uint80 answeredInRound*/) = AggregatorV3Interface(chainlinkAddress[_token]).latestRoundData();
    
        if (answer < 1) {
            // revert("chainlink price equal to zero");
            return (0, false, 2);
        }
        uint256 time_interval = uint256(block.timestamp).sub(updatedAt);
        if (time_interval > priceSafetyGap) {
            // revert("chainlink safety time gap reached");
            return (0, false, 3);
        }
        uint256 price = uint256(answer).mul(PRICE_PRECISION).div(chainlinkPrecision[_token]);
        return (price, true, updatedAt);
    }

    function getConvertedPyth(address _token) public view returns(uint256, uint256, int256){
        PythStructs.Price memory _pyPrice = pyth.getPriceUnsafe(tokenPythKEY[_token]) ;
        uint256 it_price = uint256(int256(_pyPrice.price));
        uint256 upd_time = uint256(_pyPrice.publishTime);
        int256 _expo= int256(_pyPrice.expo);
        return(it_price,upd_time,_expo );
    }

    function getPythPrice(address _token) public view returns(uint256, bool, uint256){
        if (address(pyth) == address(0)) {
            return (0, false, 0);
        }

        if (tokenPythKEY[_token] == bytes32(0)) {
            return (0, false, 1);
        }

        uint256 price = 0;
        bool read_state = false;
        uint256 upd_time = 5;
        try pyth.getPriceUnsafe(tokenPythKEY[_token]) returns (PythStructs.Price memory _pyPrice ) {
            uint256 it_price = uint256(int256(_pyPrice.price));
            if (it_price < 1) {
                return (0, false, 2);
            }
            // 3040137682421, 825317579, -8,
            upd_time = uint256(_pyPrice.publishTime);
            uint256 time_interval = uint256(block.timestamp).sub(upd_time);
            if (time_interval > priceSafetyGap) {
                return (0, false, 3);
            }
            int256 _expo= int256(_pyPrice.expo);
            if (_expo >= 0) {
                return (0, false, 4);
            }
            price = uint256(it_price).mul(PRICE_PRECISION).div(10 ** uint256(-_expo));
            if (price < 10 || upd_time < 10) {
                read_state = false;
                upd_time = 7;
            }
            read_state = true;
        } catch {
            upd_time = 6;
        }    

        return (price, read_state, upd_time);
    }

    function getPrimaryPrice(address _token) public view override returns (uint256, bool, uint256) {
        return getPrimaryPriceFast(_token);
    }


    //==============================fast price================================
    function getPrimaryPriceFast(address _token) public view returns (uint256,bool, uint256) {
        uint256 price;
        uint256 upd_time;
        (price, upd_time) = edeOracle.getPrice(_token);

        if (price < 1) {
            return (0, false, 2);
        }
        uint256 time_interval = uint256(block.timestamp).sub(upd_time);
        if (time_interval > priceSafetyGap) {
            return (0, false, 3);
        }

        if (tokenPythKEY[_token] == bytes32(0)) {
            return (0, false, 1);
        }

        return (price, true, upd_time);
    }


    //set positionRouter
    function setPositionRouter(address[] memory _positionRouters) public onlyOwner {
        positionRouters = _positionRouters;
    }
    function addPositionRouter(address _positionRouter) public onlyOwner {
        positionRouters.push(_positionRouter);
    }
    function setPricesWithBitsAndExecute(uint256[] memory , uint256 ) external onlyUpdater {
        // _setPricesWithBits(_priceBits, _timestamp);
        for (uint256 i = 0; i < positionRouters.length; i++) {
            IPositionRouter _positionRouter = IPositionRouter(positionRouters[i]);
            uint256 a;
            uint256 b;
            uint256 c;
            uint256 d;
            (a, b, c, d) = _positionRouter.getRequestQueueLengths();
            _positionRouter.executeIncreasePositions(b + 3, payable(msg.sender));
            _positionRouter.executeDecreasePositions(d + 3, payable(msg.sender));
        }
    }

    function setPricesWithBitsAndExecuteIncrease(uint256[] memory , uint256 ) external onlyUpdater {
        // _setPricesWithBits(_priceBits, _timestamp);
        for (uint256 i = 0; i < positionRouters.length; i++) {
            IPositionRouter _positionRouter = IPositionRouter(positionRouters[i]);
            uint256 a;
            uint256 b;
            uint256 c;
            uint256 d;
            (a, b, c, d) = _positionRouter.getRequestQueueLengths();
            _positionRouter.executeIncreasePositions(b + 3, payable(msg.sender));
        }
    }

    function setPricesWithBitsAndExecuteDecrease(uint256[] memory , uint256 ) external onlyUpdater {
        // _setPricesWithBits(_priceBits, _timestamp);
        for (uint256 i = 0; i < positionRouters.length; i++) {
            IPositionRouter _positionRouter = IPositionRouter(positionRouters[i]);
            uint256 a;
            uint256 b;
            uint256 c;
            uint256 d;
            (a, b, c, d) = _positionRouter.getRequestQueueLengths();
            _positionRouter.executeDecreasePositions(d + 3, payable(msg.sender));
        }
    }
}

