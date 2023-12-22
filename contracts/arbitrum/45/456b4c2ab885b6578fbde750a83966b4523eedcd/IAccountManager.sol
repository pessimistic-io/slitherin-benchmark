pragma solidity 0.8.6;

interface IAccountManager {
    enum Symbols {
        ETH_USD_LONG,
        ETH_USD_SHORT
    }
    function keyData(uint256 id) external returns (
        Symbols symbol, 
        address doppelgangerContract, 
        bool isLong,
        address indexToken,
        address user
    );
    function indexTokenBySymbol(Symbols symbol) external returns (address indexToken);
    function getPositionDelta(uint256 id) external view returns (bool isProfit, uint256 profit);
    function getPosition(uint256 id) external view returns (
        uint256 size, 
        uint256 collateral, 
        uint256 averagePrice, 
        uint256 entryFundingRate, 
        uint256 reserveAmount, 
        uint256 realisedPnl,
        bool isProfit, 
        uint256 lastIncreasedTime
    );
    function currentPrice(uint256 id) external view returns (uint256 price);
    function isLong(uint256 id) external view returns (bool);
}
