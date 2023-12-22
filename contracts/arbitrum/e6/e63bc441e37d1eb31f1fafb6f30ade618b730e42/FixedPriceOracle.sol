pragma solidity ^0.8.7;

contract FixedPriceOracle {
    address public pool = 0x2CB445366FbE025569D6883Aa931E79deF202802;
    address public token0 = 0xe018c227bC84e44c96391d3067FAb5A9A46b7E62;
    address public token1 = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    uint256 public price0Average;
    uint256 public price1Average;
    uint256 public pricesBlockTimestampLast;
    uint256[2] public priceCumulativeLast;
    bool public averagePriceValid = false;

    address internal dao;

    constructor(address _dao) {
        dao = _dao;
        price0Average = 1 ether;
        price1Average = 1 ether;
    }

    function averageDollarPrice() public view returns (uint256, bool) {
        return (price0Average, averagePriceValid);
    }

    function consult(address token) external view returns (uint256 amountOut) {
        if (token == token0) {
            return price0Average;
        } else {
            require(token == token1, "invalid token");
            return price1Average;
        }
    }

    function update() external {}

    function updateParams(uint256 _price0, uint256 _price1, bool _valid) external {
        require(msg.sender == dao);
        price0Average = _price0;
        price1Average = _price1;
        averagePriceValid = _valid;
    }
}