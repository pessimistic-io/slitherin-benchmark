pragma solidity >=0.8.4;
import "./Ownable.sol";
import "./StringUtils.sol";
import "./SidGiftCardLedger.sol";
import "./ISidPriceOracle.sol";
import "./SidGiftCardVoucher.sol";

interface AggregatorInterface {
    function latestAnswer() external view returns (int256);
}

// StablePriceOracle sets a price in USD, based on an oracle.
contract SidPriceOracle is ISidPriceOracle, Ownable {
    using StringUtils for *;
    //price in USD per second
    uint256 private constant price1Letter = 100000000000000;
    uint256 private constant price2Letter = 50000000000000;
    uint256 private constant price3Letter = 15844369253405;
    uint256 private constant price4Letter = 3168873850681;
    uint256 private constant price5Letter = 158443692534;

    // Oracle address
    AggregatorInterface public immutable usdOracle;
    SidGiftCardLedger public immutable ledger;
    SidGiftCardVoucher public immutable voucher;

    constructor(
        AggregatorInterface _usdOracle,
        SidGiftCardLedger _ledger,
        SidGiftCardVoucher _voucher
    ) {
        usdOracle = _usdOracle;
        ledger = _ledger;
        voucher = _voucher;
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

    function giftcard(uint256[] calldata ids, uint256[] calldata amounts) public view returns (ISidPriceOracle.Price memory) {
        uint256 total = voucher.totalValue(ids, amounts);
        return ISidPriceOracle.Price({base: attoUSDToWei(total), premium: 0, usedPoint: 0});
    }

    function domain(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (ISidPriceOracle.Price memory) {
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
        return ISidPriceOracle.Price({base: attoUSDToWei(basePrice), premium: attoUSDToWei(_premium(name, expires, duration)), usedPoint: 0});
    }

    function domainWithPoint(
        string calldata name,
        uint256 expires,
        uint256 duration,
        address owner
    ) external view returns (ISidPriceOracle.Price memory) {
        uint256 len = name.strlen();
        uint256 basePrice;
        uint256 usedPoint;
        uint256 premiumPrice = _premium(name, expires, duration);
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
        uint256 pointRedemption = ledger.balanceOf(owner);

        //calculate base price with point redemption
        if (pointRedemption > basePrice) {
            usedPoint = basePrice;
            basePrice = 0;
        } else {
            basePrice = basePrice - pointRedemption;
            usedPoint = pointRedemption;
        }
        pointRedemption = pointRedemption - usedPoint;
        //calculate premium price with point redemption
        if (pointRedemption > 0) {
            if (pointRedemption > premiumPrice) {
                usedPoint = usedPoint + premiumPrice;
                premiumPrice = 0;
            } else {
                premiumPrice = premiumPrice - pointRedemption;
                usedPoint = usedPoint + pointRedemption;
            }
        }

        return ISidPriceOracle.Price({base: attoUSDToWei(basePrice), premium: attoUSDToWei(premiumPrice), usedPoint: usedPoint});
    }

    function attoUSDToWei(uint256 amount) internal view returns (uint256) {
        uint256 bnbPrice = uint256(usdOracle.latestAnswer());
        return (amount * 1e8) / bnbPrice;
    }
}

