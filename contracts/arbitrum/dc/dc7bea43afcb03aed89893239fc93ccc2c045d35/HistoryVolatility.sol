// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./IPyth.sol";
import "./PythStructs.sol";

import {Abdk} from "./AbdkUtil.sol";
import {ABDKMath64x64} from "./ABDKMath64x64.sol";

contract HistoryVolatility is
    Ownable
    {
    using ABDKMath64x64 for uint128;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;

    using Abdk for uint256;

    uint public constant DEFAULT_WINDOW_SIZE = 3600; // 60 seconds == 1 min, this must match vol interval
    uint64 public pyth_margin = 3; // time margin for close trade in seconds, must be short enough to prevent 'peeking' into the future
    uint64 public pyth_clock_skew = 30; // time margin for open trade price, higher allowance as we don't use it for settlement only collateral/premium calculation so not submit to timer attack
    mapping(address => bool) private _isOperator;

    modifier onlyOperator() {
        require(_isOperator[_msgSender()], "HV:CALLER_NOT_ALLOWED");
        _;
    }

    int128 public windowSize; // window size in seconds
    IPyth pyth;

    struct Derivative {
        uint64 time; // epoch time for VOL update
        uint64 price; //price * 1000000 (e.g. 1,3547 * 1000 = 1354000) to align with USDC
        int128 americanHV; // for american
        bytes32 pythPriceId; // price id from pyth network
        string symbol; //e.g. EURUSD
        string market; // forex/crypto/energy
        bool inverse; // whether it is x/usd(BTC, EUR etc.) or usd/x(JPY, CAD etc.)
        uint64 priceTime; // time for price update
        int128 digitalHV; // for digital
        int128 turboHV; // for turbo
    }

    struct PriceTime {
        uint64 openTime;
        uint64 closeTime;
    }
    
    Derivative[] public derivatives;


    event AddNewDerivative(string market, string symbol);
    event SetHistoryVolatility(uint256 indexed productId, int128 american, int128 digital, int128 turbo);
    event SetPrice(uint indexed id, uint price);

    constructor(address _pyth) {
        windowSize = uint256(DEFAULT_WINDOW_SIZE).toAbdk(); // seconds?
        pyth = IPyth(_pyth);
    }

    function setWindowSize(uint256 newWindowSize) external onlyOperator {
        windowSize = newWindowSize.toAbdk();
    }

    // ============= OPERATOR ===============

    function isOperator(address _operator) public view returns (bool) {
        return _isOperator[_operator];
    }

    function allowOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "HV:ZERO_ADDRESS");
        _isOperator[_operator] = true;
    }

    function removeOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "HV:ZERO_ADDRESS");
        delete _isOperator[_operator];
    }

    // ================== VOLATILITY ==================

    /// @dev sets historical volatility value
    /// @param _derivativeId asset pair id
    /// @param _americanHV hv for american scaled up to 2^64, must match windowSize interval
    /// @param _digitalHV asset pair id scaled up to 2^64, must match windowSize interval
    /// @param _turboHV asset pair id scaled up to 2^64, must match windowSize interval
    function setHistoryVolatility(
        uint256 _derivativeId,
        int128 _americanHV,
        int128 _digitalHV,
        int128 _turboHV
    ) public  onlyOperator {
        require(
            _derivativeId < derivatives.length,
            "HV:DERIVATIVEID_OUT_OF_BOUNDS"
        );
        derivatives[_derivativeId].americanHV = _americanHV;
        derivatives[_derivativeId].digitalHV = _digitalHV;
        derivatives[_derivativeId].turboHV = _turboHV;
        derivatives[_derivativeId].time = uint64(block.timestamp);
        emit SetHistoryVolatility(_derivativeId, _americanHV, _digitalHV, _turboHV);
    }

    /// @dev sets multiple historical volatility values
    function setMultipleHistoryVolatility(int128[] memory _americanHV,int128[] memory _digitalHV,int128[] memory _turboHV)
        public onlyOperator
    {
        require(
            derivatives.length >= _americanHV.length,
            "HV:ARRAY_TOO_LONG"
        );

        for (uint256 i = 0; i < _americanHV.length; i++) {
            derivatives[i].americanHV = _americanHV[i];
            derivatives[i].digitalHV = _digitalHV[i];
            derivatives[i].turboHV = _turboHV[i];
            derivatives[i].time = uint64(block.timestamp);
            emit SetHistoryVolatility(i, _americanHV[i], _digitalHV[i], _turboHV[i]);
        }
    }

    /// @dev sets multiple historical volatility values
    function setMultiHistoryVolatility(uint256[] calldata derivativeIds, int128[] calldata _americanHV,int128[] calldata _digitalHV,int128[] calldata _turboHV)
        public onlyOperator
    {
        require(
            derivatives.length >= derivativeIds.length,
            "HV:ARRAY_TOO_LONG"
        );
        require(
            derivativeIds.length == _americanHV.length
            && derivativeIds.length == _digitalHV.length
            && derivativeIds.length == _turboHV.length
            ,"HV:ARRAY_TOO_LONG"
        );

        for (uint256 i = 0; i < derivativeIds.length; i++) {
            uint derivativeId = derivativeIds[i];
            require(derivativeId < derivatives.length, "HV:ID_TOO_LARGE");
            derivatives[derivativeId].americanHV = _americanHV[derivativeId];
            derivatives[derivativeId].digitalHV = _digitalHV[derivativeId];
            derivatives[derivativeId].turboHV = _turboHV[derivativeId];
            derivatives[derivativeId].time = uint64(block.timestamp);
            emit SetHistoryVolatility(derivativeId, _americanHV[derivativeId], _digitalHV[derivativeId], _turboHV[derivativeId]);
        }
    }

    /// @dev returns volatility for specified derivative
    function getHistoryVolatility(uint256 _derivativeId)
        public view returns (int128 americanHV, int128 digitalHV, int128 turboHV)
    {
        require(derivatives.length >= _derivativeId, "HV:UNKNOWN_DERIVATIVE_ID");
        return (derivatives[_derivativeId].americanHV,derivatives[_derivativeId].digitalHV,derivatives[_derivativeId].turboHV);
    }

    /// @dev time-scaled volatility value
    function getScaledVolatility(
        uint256 _derivativeId,
        uint256 _maturity,
        uint8 _type
    ) public view returns (int128) {
        // volatility should be scaled to time interval
        return calcScaledVolatility(_type == 0 ? derivatives[_derivativeId].americanHV 
                                    : (_type == 1 ? derivatives[_derivativeId].digitalHV : derivatives[_derivativeId].turboHV), _maturity, windowSize);
        // return _maturity.toAbdk()
        //     .div(windowSize)
        //     .sqrt()
        //     .mul(derivatives[_derivativeId].americanHV);
    }

    /// @dev time-scaled volatility value(intended for external use)
    /// @param _hv hv value * 2^64
    /// @param _maturity duration in seconds
    /// @param _windowSize _hv interval in seconds * 2^64
    function calcScaledVolatility(
        int128 _hv,
        uint256 _maturity,
        int128 _windowSize
    ) public pure returns (int128 _scaledVolatility) {
        // volatility should be scaled to time interval
        //scaled_hv = hv * sqrt(duration/windowSize)
        return _maturity.toAbdk()
            .div(_windowSize)
            .sqrt()
            .mul(_hv);
    }

    // ===================== DERIVATIVES =====================

    modifier correctDerivativeId(uint id) {
        require(id < derivatives.length, "HV:ID_OUT_OF_BOUNDS");
        _;
    }

    // @dev returns number of derivatives
    function getCountDerivative() public view returns (uint)
    {
        return derivatives.length;
    }
    // @dev returns derivative info
    function getDerivative(uint derivativeId, uint8 hvType)
        public
        view
        returns(uint64, uint64, int128, string memory, string memory, bytes32 pythPriceId, bool inverse)
    {
        return (
            derivatives[derivativeId].price,
            derivatives[derivativeId].time,
            hvType == 0 ? derivatives[derivativeId].americanHV : hvType == 1 ? derivatives[derivativeId].digitalHV : derivatives[derivativeId].turboHV,
            derivatives[derivativeId].symbol,
            derivatives[derivativeId].market,
            derivatives[derivativeId].pythPriceId,
            derivatives[derivativeId].inverse
        );
    }
    // @dev returns pyth price id for a given derivative
    function getPythPriceId(uint derivativeId)
        public
        view
        returns(bytes32 pythPriceId)
    {
        return (
            derivatives[derivativeId].pythPriceId
        );
    }
    /// @dev adds derivative market-symbol pair
    function addDerivative(
        string memory _market,
        string memory _symbol,
        bytes32 pythPriceId,
        bool inverse
    )
        public onlyOperator
    {
        derivatives.push(Derivative({
            price: 0,
            time: uint64(block.timestamp),
            americanHV: 0,
            pythPriceId: pythPriceId,
            symbol: _symbol,
            market: _market,
            inverse: inverse,
            priceTime: uint64(block.timestamp),
            digitalHV: 0,
            turboHV: 0
        }));
        emit AddNewDerivative(_market, _symbol);
    }
    /// @dev adds multiple market-symbol pairs
    /// EXAMPLE (metals are considered forex)
    /// [forex, forex, forex, crypto, crypto]
    /// [eurusd, gbpusd, xauusd, btcusd, ethusd] 
    /// [0x, 0x1234...., 0x, 0x, 0x] 
    function addMultipleDerivatives(
        string[] calldata markets,
        string[] calldata symbols,
        bytes32[] calldata pythPriceIds,
        bool[] calldata inverses
    ) 
        public onlyOperator
    {
        require(symbols.length > 0 && symbols.length == markets.length && pythPriceIds.length == markets.length && pythPriceIds.length == inverses.length,"HV:SYM_LENGTHS_MISMATCH");
        for (uint256 i = 0; i < symbols.length; i++) {
            derivatives.push(Derivative({
                price: 0,
                time: uint64(block.timestamp),
                americanHV: 0,
                pythPriceId: pythPriceIds[i], // zero if not available
                symbol: symbols[i],
                market: markets[i],
                inverse: inverses[i],
                priceTime: uint64(block.timestamp),
                digitalHV: 0,
                turboHV: 0
            }));
            emit AddNewDerivative(markets[i], symbols[i]);
        }
    }
    /// @dev returns derivative price
    function getDerivativePrice(uint derivativeId)
        public view correctDerivativeId(derivativeId) returns (uint)
    {
        return derivatives[derivativeId].price;
    }

    function _updateSinglePrice(uint derivativeId, uint price) internal
    {
        derivatives[derivativeId].price = uint64(price);
        derivatives[derivativeId].priceTime = uint64(block.timestamp);
        emit SetPrice(derivativeId, price);
    }

    /// @dev updates derivatives prices
    /// @param newPrices array of new price values
    function updatePrices(uint[] calldata newPrices)
       public
       onlyOperator
    {
        require(derivatives.length == newPrices.length, "HV:LENGTHS_MISMATCH");

        for (uint i = 0; i < derivatives.length; i++) {
            _updateSinglePrice(i, newPrices[i]);

        }
    }
    /// @dev sets new price of derivative
    /// @param derivativeId derivative id
    /// @param newPrice new price value
    function updateSinglePrice(uint derivativeId, uint newPrice)
        external
        onlyOperator
        correctDerivativeId(derivativeId)
    {
        _updateSinglePrice(derivativeId, newPrice);
    }

    /// @dev sets new price of derivative from pyth data
    /// @param priceUpdateData pyth update data
    function updatePythPrice(uint derivativeId, bytes[] calldata priceUpdateData)
        external payable
        returns (uint price, uint time)
    {
        if (address(pyth) != address(0) && priceUpdateData.length > 0) {
            uint pythFee = pyth.getUpdateFee(priceUpdateData);
            require(address(this).balance >= pythFee,"HV:NEED_ETH_FOR_PYTH_FEE");
            pyth.updatePriceFeeds{ value: pythFee }(priceUpdateData);  
            (price, time) = updatePriceFromPyth(derivativeId);
        }
    }

    /// @dev sets new price of derivative from pyth contract
    /// @param derivativeId derivative id
    function updatePriceFromPyth(uint derivativeId)
        public
        correctDerivativeId(derivativeId)
        returns (uint price, uint time)
    {
        Derivative memory derivative = derivatives[derivativeId];
        bytes32 priceId = derivative.pythPriceId;
        if (priceId != bytes32(0)) {
            try pyth.getPrice(priceId) returns (PythStructs.Price memory pythPrice) {
                if (pythPrice.publishTime > derivative.priceTime) {
                    bool negative = pythPrice.expo < 0;
                    uint32 expo = uint32(negative ? 0 - pythPrice.expo : pythPrice.expo);
                    if (negative) {
                        if (expo <= 6) {
                            derivative.price = uint64(uint256(uint64(pythPrice.price)) * (10 ** (6 - expo)));
                        }
                        else {
                            derivative.price = uint64(uint256(uint64(pythPrice.price)) / (10 ** (expo - 6)));
                        }
                    }
                    else {
                        derivative.price = uint64(uint256(uint64(pythPrice.price)) * (10 ** (expo + 6)));
                    }
                    derivative.priceTime = uint64(pythPrice.publishTime);
                    derivatives[derivativeId] = derivative;
                }     
                price = derivative.price;
                time = derivative.priceTime;
                emit SetPrice(derivativeId, price);
            }
            catch {}
        }
    }

    function parsePythPrice(  
        uint256 derivativeId,      
        bytes[] calldata openPriceUpdateData,
        uint256 timeOpen,
        bytes[] calldata closePriceUpdateData,
        uint256 timeClose
    ) 
        external
        payable
        returns(uint64 priceOpen, uint64 priceClose)
    {
        bytes32[] memory y = new bytes32[](1);
        uint64 openPublishTime;
        uint64 closePublishTime;
        y[0] = derivatives[derivativeId].pythPriceId;
        (priceOpen,openPublishTime) = _updatePriceFromPythPrice(
                        pyth.parsePriceFeedUpdates{value: pyth.getUpdateFee(openPriceUpdateData)}
                        (openPriceUpdateData, 
                         y, 
                         0, 
                         type(uint64).max 
                         )[0].price, derivativeId);
        // do not allow peek into the future beyond narrow margin even for init price which is for ref                 
        require(openPublishTime <= timeOpen + pyth_margin*2,"HV:OPEN_PRICE_TOO_NEW");
        // init start allow higher backward margin
        require(openPublishTime + (timeClose == 0 ? pyth_clock_skew : pyth_margin) >= timeOpen,"HV:OPEN_PRICE_TOO_OLD");
        if (timeClose > 0) {
            (priceClose, closePublishTime) = _updatePriceFromPythPrice(
                            pyth.parsePriceFeedUpdates{value: pyth.getUpdateFee(closePriceUpdateData)}
                            (closePriceUpdateData, y, 0,type(uint64).max)[0].price, derivativeId);
            require(closePublishTime <= timeClose + pyth_margin*2,"HV:CLOSE_PRICE_TOO_NEW");
            require(closePublishTime + pyth_margin >= timeClose,"HV:CLOSE_PRICE_TOO_OLD");
        }
    }

    /// @dev update derivative price if newer than recorded
    function _updatePriceFromPythPrice(PythStructs.Price memory pythPrice, uint256 derivativeId) internal returns (uint64 price, uint64 time)
    {
        (price, time) =  getPriceFromPythPrice(pythPrice);
        if (derivatives[derivativeId].priceTime < time) {
            derivatives[derivativeId].price = price;
            derivatives[derivativeId].priceTime = time;
            emit SetPrice(derivativeId, price);
        }
    }

    /// @dev convert pyth price to local(decimal conversion)
    function getPriceFromPythPrice(PythStructs.Price memory pythPrice) public pure returns (uint64 price, uint64 time)
    {
        bool negative = pythPrice.expo < 0;
        uint32 expo = uint32(negative ? 0 - pythPrice.expo : pythPrice.expo);
        if (negative) {
            if (expo <= 6) {
                price = uint64(uint256(uint64(pythPrice.price)) * (10 ** (6 - expo)));
            }
            else {
                price = uint64(uint256(uint64(pythPrice.price)) / (10 ** (expo - 6)));
            }
        }
        else {
            price = uint64(uint256(uint64(pythPrice.price)) * (10 ** (expo + 6)));
        }
        time = uint64(pythPrice.publishTime);
    }

    /// @dev allow top up ETH for pyth payment
    function topUpETH() external payable {}
}

