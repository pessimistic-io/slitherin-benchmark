// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;
import "./LibEnums.sol";

struct Hedger {
    address addr;
    string[] pricingWssURLs;
    string[] marketsHttpsURLs;
}

struct Market {
    uint256 marketId;
    string identifier;
    MarketType marketType;
    bool active;
    string baseCurrency;
    string quoteCurrency;
    string symbol;
    bytes32 muonPriceFeedId;
    bytes32 fundingRateId;
}

struct RequestForQuote {
    uint256 creationTimestamp;
    uint256 mutableTimestamp;
    uint256 rfqId;
    RequestForQuoteState state;
    PositionType positionType;
    OrderType orderType;
    address partyA;
    address partyB;
    HedgerMode hedgerMode;
    uint256 marketId;
    Side side;
    uint256 notionalUsd;
    uint256 lockedMarginA;
    uint256 protocolFee;
    uint256 liquidationFee;
    uint256 cva;
    uint256 minExpectedUnits;
    uint256 maxExpectedUnits;
    address affiliate;
}

struct Position {
    uint256 creationTimestamp;
    uint256 mutableTimestamp;
    uint256 positionId;
    bytes16 uuid;
    PositionState state;
    PositionType positionType;
    uint256 marketId;
    address partyA;
    address partyB;
    Side side;
    uint256 lockedMarginA;
    uint256 lockedMarginB;
    uint256 protocolFeePaid;
    uint256 liquidationFee;
    uint256 cva;
    uint256 currentBalanceUnits;
    uint256 initialNotionalUsd;
    address affiliate;
}

struct Constants {
    address collateral;
    address muon;
    bytes32 muonAppId;
    uint8 minimumRequiredSignatures;
    uint256 protocolFee;
    uint256 liquidationFee;
    uint256 protocolLiquidationShare;
    uint256 cva;
    uint256 requestTimeout;
    uint256 maxOpenPositionsCross;
}

struct HedgersState {
    mapping(address => Hedger) _hedgerMap;
    Hedger[] _hedgerList;
}

struct MarketsState {
    mapping(uint256 => Market) _marketMap;
    Market[] _marketList;
}

struct MAState {
    // Balances
    mapping(address => uint256) _accountBalances;
    mapping(address => uint256) _marginBalances;
    mapping(address => uint256) _crossLockedMargin;
    mapping(address => uint256) _crossLockedMarginReserved;
    // RequestForQuotes
    mapping(uint256 => RequestForQuote) _requestForQuotesMap;
    uint256 _requestForQuotesLength;
    mapping(address => uint256) _crossRequestForQuotesLength;
    // Positions
    mapping(uint256 => Position) _allPositionsMap;
    uint256 _allPositionsLength;
    mapping(address => uint256) _openPositionsIsolatedLength;
    mapping(address => uint256) _openPositionsCrossLength;
}

struct AppStorage {
    bool paused;
    uint128 pausedAt;
    uint256 reentrantStatus;
    address ownerCandidate;
    Constants constants;
    HedgersState hedgers;
    MarketsState markets;
    MAState ma;
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage s) {
        assembly {
            s.slot := 0
        }
    }
}

