pragma solidity >=0.8.4;
import "./Ownable.sol";
import "./StringUtils.sol";
import "./IPriceOracle.sol";

interface AggregatorInterface {
    function latestAnswer() external view returns (int256);
}

// StablePriceOracle sets a price in USD, based on an oracle.
contract PriceOracle is IPriceOracle, Ownable {
    using StringUtils for *;
    //price in USD per second
    uint256 private constant price1Letter = 100000000000000;
    uint256 private constant price2Letter = 50000000000000;
    uint256 private constant price3Letter = 9506621552043;
    uint256 private constant price4Letter = 1901324310408;
    uint256 private constant price5Letter = 158443692534;

    // Oracle address
    AggregatorInterface public immutable usdOracle;
   
    constructor(
        AggregatorInterface _usdOracle
    ) {
        usdOracle = _usdOracle;
    }

    /**
     * @dev Returns the pricing premium in wei.
     */
    function premium(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (uint256) {
        return attoUSDToWei(_premium(name, expires, duration));
    }

    /**
     * @dev Returns the pricing premium in internal base units.
     */
    function _premium(
        string memory name,
        uint256 expires,
        uint256 duration
    ) internal view virtual returns (uint256) {
        return 0;
    }

    function price(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (IPriceOracle.Price memory) {
        uint256 len = name.strlen();
        uint256 basePrice;
        if (len == 1) {
            basePrice = price1Letter * duration;
        } else if (len == 2) {
            basePrice = price2Letter * duration;
        } else if (len == 3) {
            basePrice = price3Letter * duration;
        } else if (len == 4) {
            basePrice = price4Letter * duration;
        } else {
            basePrice = price5Letter * duration;
        }
        return IPriceOracle.Price({base: attoUSDToWei(basePrice), premium: attoUSDToWei(_premium(name, expires, duration))});
    }


    function attoUSDToWei(uint256 amount) internal view returns (uint256) {
        uint256 ethPrice = uint256(usdOracle.latestAnswer());
        return (amount * 1e8) / ethPrice;
    }

    function weiToAttoUSD(uint256 amount) internal view returns (uint256) {
        uint256 ethPrice = uint256(usdOracle.latestAnswer());
        return (amount * ethPrice) / 1e8;
    }

}

