// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracle.sol";
import "./IOracleOffChainPyth.sol";
import "./IOracleManagerPyth.sol";
import "./SafeMath.sol";
import "./NameVersion.sol";
import "./Admin.sol";

contract OracleManagerPyth is IOracleManagerPyth, NameVersion, Admin {

    using SafeMath for uint256;
    using SafeMath for int256;

    address public pyth;
    // pythId => oracleAddress
    mapping (bytes32 => address) _oracles;
    // symbolId => pythId
    mapping (bytes32 => bytes32) _pythIds;

    constructor (address pyth_) NameVersion('OracleManagerPyth', '3.0.4') {
        pyth = pyth_;
    }

    function getOracle(bytes32 symbolId) public view returns (address) {
        return _oracles[_pythIds[symbolId]];
    }

    function getOracle(string memory symbol) external view returns (address) {
        return getOracle(keccak256(abi.encodePacked(symbol)));
    }

    function setOracle(address oracleAddress) external _onlyAdmin_ {
        IOracleOffChainPyth oracle = IOracleOffChainPyth(oracleAddress);
        require(oracle.oracleManager() == address(this));
        bytes32 symbolId = oracle.symbolId();
        bytes32 pythId = oracle.pythId();
        _oracles[pythId] = oracleAddress;
        _pythIds[symbolId] = pythId;
        emit NewOracle(symbolId, oracleAddress);
    }

    function delOracle(bytes32 symbolId) public _onlyAdmin_ {
        delete _oracles[_pythIds[symbolId]];
        delete _pythIds[symbolId];
        emit NewOracle(symbolId, address(0));
    }

    function delOracle(string memory symbol) external {
        delOracle(keccak256(abi.encodePacked(symbol)));
    }

    function retrieveETH(address to) external _onlyAdmin_ {
        uint256 amount = address(this).balance;
        if (amount > 0) {
            (bool success, ) = payable(to).call{value: amount}('');
            require(success);
        }
    }

    function value(bytes32 symbolId) public view returns (uint256) {
        address oracle = _oracles[_pythIds[symbolId]];
        require(oracle != address(0), 'OracleManagerPyth.value: no oracle');
        return IOracle(oracle).value();
    }

    function timestamp(bytes32 symbolId) public view returns (uint256) {
        address oracle = _oracles[_pythIds[symbolId]];
        require(oracle != address(0), 'OracleManagerPyth.timestamp: no oracle');
        return IOracle(oracle).timestamp();
    }

    function lastSignatureTimestamp(bytes32 pythId) public view returns (uint256) {
        address oracle = _oracles[pythId];
        require(oracle != address(0), 'OracleManagerPyth.lastSignatureTimestamp: no oracle');
        return IOracleOffChainPyth(oracle).lastSignatureTimestamp();
    }

    function getValue(bytes32 symbolId) public view returns (uint256) {
        address oracle = _oracles[_pythIds[symbolId]];
        require(oracle != address(0), 'OracleManagerPyth.getValue: no oracle');
        return IOracle(oracle).getValue();
    }

    function getValueWithJump(bytes32 symbolId) external returns (uint256 val, int256 jump) {
        address oracle = _oracles[_pythIds[symbolId]];
        require(oracle != address(0), 'OracleManagerPyth.getValueWithHistory: no oracle');
        return IOracle(oracle).getValueWithJump();
    }

    function getUpdateFee(uint256 length) external view returns (uint256) {
        return IPyth(pyth).getUpdateFee(length);
    }

    function updateValues(bytes[] memory vaas, bytes32[] memory ids)
    external payable returns (bool)
    {
        (bool success, bytes memory res) = address(pyth).call{value: msg.value}(
            abi.encodeWithSelector(
                IPyth.parsePriceFeedUpdates.selector, vaas, ids, 0, type(uint64).max
            )
        );
        if (success) {
            IPyth.PriceFeed[] memory priceFeeds = abi.decode(res, (IPyth.PriceFeed[]));
            for (uint256 i = 0; i < priceFeeds.length; i++) {
                uint256 _timestamp = priceFeeds[i].price.publishTime;
                uint256 _price = int256(priceFeeds[i].price.price).itou() * (
                    10 ** (int256(18) + priceFeeds[i].price.expo).itou()
                );

                address oracle = _oracles[priceFeeds[i].id];
                require(oracle != address(0), 'OracleManagerPyth.updateValues: no oracle');
                IOracleOffChainPyth(oracle).updateValue(_timestamp, _price);
            }
            return true;
        } else {
            return false;
        }
    }

}

interface IPyth {

    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }

    function getUpdateFee(
        uint updateDataSize
    ) external view returns (uint feeAmount);

    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PriceFeed[] memory priceFeeds);

}

