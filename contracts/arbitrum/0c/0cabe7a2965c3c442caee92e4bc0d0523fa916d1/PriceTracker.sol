pragma solidity ^0.8.0;
import "./Ownable.sol";
// To track the price ratio between native tokens of different chains
contract PriceTracker is Ownable {

    // dest chain native token price in terms of src chain native token
    // e.g., if src chain is polygon and des chain is eth, the price is polygon price in terms of eth
    /// mapping(src chainId => (dest chainId => price))
    mapping(uint256 => mapping(uint256 => uint256)) public priceMap;
    mapping(address => bool) public keepers;

    event UpdatePrice(uint256 _srcChainId, uint256 _dstChainId, uint256 _prices);
    event SetKeeper(address keeper, bool isActive);

    constructor() public {
    }

    function setPrices(
        uint256[] memory _srcChainIds,
        uint256[] memory _dstChainIds,
        uint256[] memory _prices
    ) external onlyKeeper {
        require(_srcChainIds.length == _prices.length && _dstChainIds.length == _prices.length, "not same length");
        for (uint256 i = 0; i < _srcChainIds.length; i++) {
            require(_prices[i] > 0, "price cannot be 0");
            priceMap[_srcChainIds[i]][_dstChainIds[i]] = _prices[i];
            emit UpdatePrice(_srcChainIds[i], _dstChainIds[i], _prices[i]);
        }
    }

    function setKeeper(address _keeper, bool _isActive) external onlyOwner {
        keepers[_keeper] = _isActive;
        emit SetKeeper(_keeper, _isActive);
    }

    function getPrice(uint256 _srcChainId, uint256 _dstChainId) external view returns(uint256) {
        return priceMap[_srcChainId][_dstChainId];
    }

    modifier onlyKeeper {
        require(
            keepers[msg.sender],
            "Only keeper can call this function."
        );
        _;
    }
}

