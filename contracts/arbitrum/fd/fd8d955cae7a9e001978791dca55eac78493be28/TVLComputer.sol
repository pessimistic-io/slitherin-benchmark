// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Upgradeable.sol";
import "./Whitelist.sol";
import "./IRegistry.sol";
import "./ITrade.sol";

contract TVLComputer is Upgradeable {
    address[] public tokens;
    address public gmxReader;
    address public gmxVault;
    mapping (address => address) public priceFeeds;

    function initialize() public initializer {
        __Ownable_init();
    }

    function setPriceFeed(address token, address priceFeed) public onlyOwner {
        (, bool found) = registry.whitelist().getTokenIndex(token);
        require(found, "TC/TNF"); // token not found
        priceFeeds[token] = priceFeed;
    }

    function setGMXParams(address _gmxReader, address _gmxVault) public onlyOwner {
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
    }

    function getTVL(address trade) public view returns (uint256 balance) {
        balance = ITrade(trade).usdtAmount() - ITrade(trade).debt();
        bool[] memory indexes = convertToBoolArray(ITrade(trade).whitelistMask());
        for (uint256 i = 0; i < indexes.length; i++) {
            if (!indexes[i]) continue;
            address token = Whitelist(address(registry.whitelist())).tokens(i);
            if (token != address(0) && priceFeeds[token] != address(0)) continue; // TODO: should require be here?
            uint256 tokenBalance = IERC20(token).balanceOf(trade);
            (uint256 aaveBalance,,,,,,,,) = registry.aavePoolDataProvider().getUserReserveData(token, trade);
            balance += (aaveBalance + tokenBalance)
                * uint256(IPriceFeed(priceFeeds[token]).latestAnswer())
                / 10**uint256(IPriceFeed(priceFeeds[token]).decimals())
                * 10**(registry.usdt()).decimals();
            if (gmxReader != address(0) && gmxVault != address(0)) balance += getGMXValue(trade, token);
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

    function convertToBoolArray(bytes memory mask) private view returns (bool[] memory) {
        bool[] memory booleanArray = new bool[](mask.length * 8);
        uint256 index = 0;
        for (uint256 i = mask.length - 1; i >= 0; i--) {
            uint8 byteValue = uint8(mask[i]);
            for (uint8 j = 0; j < 8; j++) {
                booleanArray[index] = (byteValue & (1 << j)) != 0;
                index++;
            }
        }
        return booleanArray;
    }
}

