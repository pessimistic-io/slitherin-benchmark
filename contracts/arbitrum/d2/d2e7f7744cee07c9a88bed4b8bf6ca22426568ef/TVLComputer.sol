// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./console.sol";

import "./Upgradeable.sol";
import "./IWhitelist.sol";
import "./IRegistry.sol";
import "./ITrade.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0xe8258b0003CB159c75bfc2bC2D079d12E3774a80);

contract TVLComputer is Upgradeable {
    address public gmxReader;
    address public gmxVault;
    mapping (address => address) public priceFeeds;
    event PriceFeedChanged(address token, address priceFeed);
    event GMXParamsChanged(address gmxReader, address gmxVault);

    function initialize() public initializer {
        __Ownable_init();
    }

    function setPriceFeed(address token, address priceFeed) public onlyOwner {
        (, bool found) = registry.whitelist().getTokenIndex(token);
        require(found, "TC/TNF"); // token not found
        priceFeeds[token] = priceFeed;
        emit PriceFeedChanged(token, priceFeed);
    }

    function setGMXParams(address _gmxReader, address _gmxVault) public onlyOwner {
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        emit GMXParamsChanged(gmxReader, gmxVault);
    }

    function getTVL(address trade) public view returns (uint256 balance) {
        balance = ITrade(trade).usdtAmount();
        bool[] memory indexes = convertToBoolArray(ITrade(trade).whitelistMask());
        for (uint256 i = 0; i < indexes.length; i++) {
            if (!indexes[i]) continue;
            address token = IWhitelist(address(registry.whitelist())).tokens(i);
            require(token != address(0), "TC/ET"); // empty token
            require(priceFeeds[token] != address(0), "TC/EF"); // empty feed
            uint256 tokenBalance = IERC20(token).balanceOf(trade);
            if (address(registry.aavePoolDataProvider()) != address(0)) {
                DataTypes.ReserveData memory reserveData = registry.aavePool().getReserveData(token);
                if (reserveData.aTokenAddress != address(0)) {
                    (uint256 aaveBalance,,,,,,,,) = registry.aavePoolDataProvider().getUserReserveData(token, trade);
                    tokenBalance += aaveBalance;
                }
            }
            balance += tokenBalance * uint256(IPriceFeed(priceFeeds[token]).latestAnswer())
                / 10**uint256(IPriceFeed(priceFeeds[token]).decimals())
                * 10**(registry.usdt()).decimals()
                / 10**(IERC20MetadataUpgradeable(token).decimals());
            if (gmxReader != address(0) && gmxVault != address(0)) {
                balance += getGMXValue(trade, token);
            }
        }
        if (ITrade(trade).debt() >= balance) {
            balance = 0;
        } else {
            balance -= ITrade(trade).debt();
        }
    }

    function getGMXValue(address trade, address token) private view returns (uint256) {
        require(gmxReader != address(0) && gmxVault != address(0), "TC/NGP"); // no GMX params set
        address[] memory collateralTokens = new address[](2);
        address[] memory indexTokens = new address[](2);
        bool[] memory isLong = new bool[](2);

        collateralTokens[0] = token;
        indexTokens[0] = token;
        isLong[0] = true;
        collateralTokens[1] = address(registry.usdt());
        indexTokens[1] = token;
        isLong[1] = false;

        uint256[] memory positionList = IReader(gmxReader).getPositions(
            gmxVault,
            trade,
            collateralTokens,
            indexTokens,
            isLong
        );

        uint256 gmxPosition;
        for (uint256 i = 0; i < positionList.length; i += 9) {
            uint256 collateral = positionList[i + 1];
            bool hasProfit = positionList[i + 7] > 0;
            uint256 delta = positionList[i + 8];

            if (collateral > 0) {
                uint256 tokenPosition = hasProfit ? collateral + delta : collateral - delta;
                gmxPosition += tokenPosition;
            }
        }

        return gmxPosition;
    }

    function convertToBoolArray(bytes memory mask) private pure returns (bool[] memory) {
        bool[] memory booleanArray = new bool[](mask.length * 8);
        uint256 index = 0;
        for (int256 i = int256(mask.length) - 1; i >= 0; i--) {
            uint8 byteValue = uint8(mask[uint256(i)]);
            for (uint8 j = 0; j < 8; j++) {
                booleanArray[index] = (byteValue & (1 << j)) != 0;
                index++;
            }
        }
        return booleanArray;
    }
}

