// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./EnumerableValues.sol";
import "./IMintable.sol";
import "./IVaultPriceFeed.sol";

interface IServerPriceFeed {
    function getPrice(address _token) external view returns (uint256, uint256);
}

interface PythStructs {
    struct Price {
        int64 price;// Price
        uint64 conf;// Confidence interval around the price
        int32 expo;// Price exponent
        uint publishTime;// Unix timestamp describing when the price was published
    }
}

interface IPyth {
    function queryPriceFeed(bytes32 id) external view returns (PythStructs.Price memory price);
    function priceFeedExists(bytes32 id) external view returns (bool exists);
    function getValidTimePeriod() external view returns(uint validTimePeriod);
    function getPrice(bytes32 id) external view returns (PythStructs.Price memory price);
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);
    function updatePriceFeedsIfNecessary(bytes[] memory updateData,bytes32[] memory priceIds,uint64[] memory publishTimes) payable external;
    function updatePriceFeeds(bytes[]memory updateData) payable external;
}


contract VaultPriceFeed is IVaultPriceFeed, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MIN_PRICE_THRES = 10 ** 20;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_PRICE_VARIANCE_PER_1M = 1000;
    uint256 public constant PRICE_VARIANCE_PRECISION = 10000;

    uint256 public priceSafetyTimeGap = 60;//seconds
    uint256 public stopTradingPriceGap = 0; 

    IPyth public pyth;
    IServerPriceFeed public serverOracle;

    //token config.
    EnumerableSet.AddressSet tokens;
    mapping(address => bytes32) public override tokenPythKEY;
    mapping(address => uint256) public spreadBasisPoints;
    mapping(address => uint256) public override adjustmentBasisPoints;
    mapping(address => bool) public override isAdjustmentAdditive;


    event UpdatePriceFeedsIfNecessary(bytes[] updateData, bytes32[] priceIds,uint64[] publishTimes);
    event UpdatePriceFeeds(bytes[]  updateData);
    //----- owner setting
    function setServerOracle(address _pyth, address _serverOra) external onlyOwner{
        pyth = IPyth(_pyth);
        serverOracle = IServerPriceFeed(_serverOra);
    }
    function setTokenCfgList(address[] memory _tokenList, bytes32[] memory _key) external onlyOwner {
        for(uint8 i = 0; i < _tokenList.length; i++) {
            require(_key[i] !=  bytes32(0) && pyth.priceFeedExists(_key[i]), "key not exist in pyth");
            if (!tokens.contains(_tokenList[i])){
                tokens.add(_tokenList[i]);
            }
            tokenPythKEY[_tokenList[i]] = _key[i];
        }
    }
    function deleteToken(address[] memory _tokenList)external onlyOwner {
        for(uint8 i = 0; i < _tokenList.length; i++) {
            if (tokens.contains(_tokenList[i])){
                tokens.remove(_tokenList[i]);
            }
        }
    }
    function setGap(uint256 _priceSafetyTimeGap, uint256 _stopTradingPriceGap) external onlyOwner {
        priceSafetyTimeGap = _priceSafetyTimeGap;
        stopTradingPriceGap = _stopTradingPriceGap;
    }
    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyOwner {
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
    }
    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyOwner {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }
    //----- end of owner setting


    //----- interface for pyth update 
    function updatePriceFeedsIfNecessary(bytes[] memory updateData, bytes32[] memory priceIds, uint64[] memory publishTimes) payable override external {
        pyth.updatePriceFeedsIfNecessary{value:msg.value}(updateData,priceIds,publishTimes );
        emit UpdatePriceFeedsIfNecessary(updateData, priceIds,publishTimes);
    }
    function updatePriceFeedsIfNecessaryTokens(bytes[] memory updateData, address[] memory _tokens, uint64[] memory publishTimes) payable override external {
        bytes32[] memory priceIds = new bytes32[](_tokens.length);
        for(uint8 i = 0; i < _tokens.length; i++){
            require(isSupportToken(_tokens[i]), "not supported token");
            priceIds[i] = tokenPythKEY[_tokens[i]];
        }
        pyth.updatePriceFeedsIfNecessary{value:msg.value}(updateData,priceIds,publishTimes );
        emit UpdatePriceFeedsIfNecessary(updateData, priceIds, publishTimes);
    }
    function updatePriceFeedsIfNecessaryTokensSt(bytes[] memory updateData, address[] memory _tokens ) payable override external {
        bytes32[] memory priceIds = new bytes32[](_tokens.length);
        uint64[] memory publishTimes = new uint64[](_tokens.length);
        for(uint8 i = 0; i < _tokens.length; i++){
            require(isSupportToken(_tokens[i]), "not supported token");
            priceIds[i] = tokenPythKEY[_tokens[i]];
            publishTimes[i] = uint64(block.timestamp);
        }
        pyth.updatePriceFeedsIfNecessary{value:msg.value}(updateData,priceIds,publishTimes );
        emit UpdatePriceFeedsIfNecessary(updateData, priceIds, publishTimes);
    }
    function updatePriceFeeds(bytes[] memory updateData) payable override external{
        pyth.updatePriceFeeds{value:msg.value}(updateData);
        emit UpdatePriceFeeds(updateData);
    }


    //----- public view 
    function isSupportToken(address _token) public view returns (bool){
        return tokens.contains(_token);
    }
    function priceTime(address _token) external view override returns (uint256){
        (, , uint256 pyUpdatedTime) = getPythPrice(_token);
        return pyUpdatedTime;
    }
    //----- END of public view 


    function _getCombPrice(address _token, bool _maximise, bool _addAdjust) internal view returns (uint256, uint256){
        // uint256 cur_timestamp = block.timestamp;
        (uint256 pricePy, bool statePy, uint256 pyUpdatedTime) = getPythPrice(_token);
        require(statePy, "[Oracle] price failed.");
        if (stopTradingPriceGap > 0){//do verify
            (uint256 pricePr, bool statePr, ) = getPrimaryPrice(_token);
            require(statePr, "[Oracle] p-oracle failed");
            uint256 price_gap = pricePr > pricePy ? pricePr.sub(pricePy) : pricePy.sub(pricePr);
            price_gap = price_gap.mul(PRICE_VARIANCE_PRECISION).div(pricePy);
            require(price_gap < stopTradingPriceGap, "[Oracle] System hault as large price variance.");
        }
        pricePy = _addBasisSpread(_token, pricePy, _maximise, _addAdjust);
        require(pricePy > 0, "[Oracle] ORACLE FAILS");
        return (pricePy, pyUpdatedTime);    
    }

    function _addBasisSpread(address _token, uint256 _price, bool _max, bool _addAdjust)internal view returns (uint256){
        if (_addAdjust && adjustmentBasisPoints[_token] > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                _price = _price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            } else {
                _price = _price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBasisPoints[_token])).div(BASIS_POINTS_DIVISOR);
            }
        }
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

    //public read
    function getPrice(address _token, bool _maximise, bool , bool _adjust) public override view returns (uint256) {
        require(isSupportToken(_token), "Unsupported token");
        (uint256 price, uint256 updatedTime) = _getCombPrice(_token, _maximise, _adjust);
        require(block.timestamp.sub(updatedTime) < priceSafetyTimeGap, "[Oracle] price out of time.");
        require(price > 10, "[Oracle] invalid price");
        return price;
    }
    function getPriceUnsafe(address _token, bool _maximise, bool, bool _adjust) public override view returns (uint256) {
        require(isSupportToken(_token), "Unsupported token");
        (uint256 price, ) = _getCombPrice(_token, _maximise, _adjust);
        require(price > 10, "[Oracle] invalid price");
        return price;
    }
    function priceVariancePer1Million(address ) external pure override returns (uint256){
        return 0;
    }
    function getPriceSpreadImpactFactor(address ) external pure override returns (uint256, uint256){
        return (0,0);
    }
    function getConvertedPyth(address _token) public view returns(uint256, uint256, int256){
        PythStructs.Price memory _pyPrice = pyth.getPriceUnsafe(tokenPythKEY[_token]) ;
        uint256 it_price = uint256(int256(_pyPrice.price));
        uint256 upd_time = uint256(_pyPrice.publishTime);
        int256 _expo= int256(_pyPrice.expo);
        return(it_price,upd_time,_expo);
    }

    function getPythPrice(address _token) public view returns(uint256, bool, uint256){
        uint256 price = 0;
        bool read_state = false;
        if (address(pyth) == address(0)) {
            return (price, read_state, 0);
        }
        if (tokenPythKEY[_token] == bytes32(0)) {
            return (price, read_state, 1);
        }

        uint256 upd_time = 5;
        try pyth.getPriceUnsafe(tokenPythKEY[_token]) returns (PythStructs.Price memory _pyPrice ) {
            uint256 it_price = uint256(int256(_pyPrice.price));
            if (it_price < 1) {
                return (0, read_state, 2);
            }
            upd_time = uint256(_pyPrice.publishTime);
            if (upd_time < 1600000000) {
                return (0, read_state, 3);
            }
            int256 _expo= int256(_pyPrice.expo);
            if (_expo >= 0) {
                return (0, read_state, 4);
            }
            
            price = uint256(it_price).mul(PRICE_PRECISION).div(10 ** uint256(-_expo));
            if (price < MIN_PRICE_THRES) {
                return (0, read_state, 5);
            }
            else{
                read_state = true;
            }
        } catch {
            upd_time = 6;
        }    
        return (price, read_state, upd_time);
    }

    function getPrimaryPrice(address _token) public view override returns (uint256, bool, uint256) {
        require(isSupportToken(_token), "Unsupported token");
        uint256 price;
        uint256 upd_time;
        (price, upd_time) = serverOracle.getPrice(_token);
        if (price < 1) {
            return (0, false, 2);
        }
        uint256 time_interval = uint256(block.timestamp).sub(upd_time);
        if (time_interval > priceSafetyTimeGap) {
            return (0, false, 3);
        }
        return (price, true, upd_time);
    }

    
    function tokenToUsdUnsafe(address _token, uint256 _tokenAmount, bool _max) public view override returns (uint256) {
        require(isSupportToken(_token), "Unsupported token");
        if (_tokenAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal"); 
        uint256 price = getPriceUnsafe(_token, _max, true, true);
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function usdToTokenUnsafe( address _token, uint256 _usdAmount, bool _max ) public view override returns (uint256) {
        require(isSupportToken(_token), "Unsupported token");
        if (_usdAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal");
        uint256 price = getPriceUnsafe(_token, _max, true, true);
        return _usdAmount.mul(10**decimals).div(price);
    }
}

