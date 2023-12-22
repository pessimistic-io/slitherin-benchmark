//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;

import "./HandlerInterfaces.sol";
import "./Ownable2Step.sol";
import "./Whitelist.sol";

contract LodestarHandler is Whitelist {
    RouterInterface public ROUTER;
    VotingInterface public VOTING;
    StakingRewardsInterface public STAKING;
    ComptrollerInterface public UNITROLLER;
    Whitelist WHITELIST;

    address[] public markets;

    struct MarketInfo {
        address marketAddress;
        string marketName;
        uint256 marketBaseSupplySpeed;
        uint256 marketBaseBorrowSpeed;
    }

    mapping(string => MarketInfo) public tokenMapping;

    event Updated(uint256 indexed timestamp);

    constructor(
        RouterInterface _router,
        VotingInterface _voting,
        StakingRewardsInterface _staking,
        ComptrollerInterface _unitroller,
        Whitelist _whitelist,
        address[] memory _marketAddresses,
        string[] memory _marketNames,
        uint256[] memory _marketBaseSupplySpeeds,
        uint256[] memory _marketBaseBorrowSpeeds
    ) {
        ROUTER = _router;
        VOTING = _voting;
        STAKING = _staking;
        UNITROLLER = _unitroller;
        WHITELIST = _whitelist;
        markets = _marketAddresses;

        for (uint256 i = 0; i < markets.length; i++) {
            MarketInfo memory market;
            market.marketAddress = _marketAddresses[i];
            market.marketName = _marketNames[i];
            market.marketBaseSupplySpeed = _marketBaseSupplySpeeds[i];
            market.marketBaseBorrowSpeed = _marketBaseBorrowSpeeds[i];
            tokenMapping[_marketNames[i]] = market;
        }
    }

    function updateStakingRewards() internal {
        bool stakingPaused = STAKING.paused();
        if (!stakingPaused) {
            ROUTER.withdrawRewards(markets);
        }
    }

    function updateLODESpeeds() internal {
        bool votingPaused = VOTING.paused();

        if (!votingPaused) {
            (string[] memory tokens, , uint256[] memory speeds) = VOTING.getResults();

            uint8 n = uint8(tokens.length);

            address[] memory marketAddresses = new address[](n);
            uint256[] memory supplySpeeds = new uint256[](n);
            uint256[] memory borrowSpeeds = new uint256[](n);

            for (uint8 i = 0; i < n; i++) {
                MarketInfo memory market = tokenMapping[tokens[i]];
                uint256 marketBaseSupplySpeed = market.marketBaseSupplySpeed;
                uint256 marketBaseBorrowSpeed = market.marketBaseBorrowSpeed;
                address marketAddress = market.marketAddress;

                uint8 supplySpeedIndex = i * 2;
                uint8 borrowSpeedIndex = supplySpeedIndex + 1;

                uint256 supplySpeed = speeds[supplySpeedIndex];
                uint256 borrowSpeed = speeds[borrowSpeedIndex];

                marketAddresses[i] = marketAddress;
                supplySpeeds[i] = supplySpeed + marketBaseSupplySpeed;
                borrowSpeeds[i] = borrowSpeed + marketBaseBorrowSpeed;
            }

            UNITROLLER._setCompSpeeds(marketAddresses, supplySpeeds, borrowSpeeds);
        }
    }

    function update() external {
        require(WHITELIST.isWhitelisted(msg.sender), "LodestarHandler: Unauthorized");
        updateStakingRewards();
        updateLODESpeeds();
        emit Updated(block.timestamp);
    }

    //ADMIN FUNCTIONS

    event RouterUpdated(
        RouterInterface indexed oldRouter,
        RouterInterface indexed newRouter,
        uint256 indexed timestamp
    );

    event VotingUpdated(
        VotingInterface indexed oldRouter,
        VotingInterface indexed newRouter,
        uint256 indexed timestamp
    );

    event UnitrollerUpdated(
        ComptrollerInterface indexed oldRouter,
        ComptrollerInterface indexed newRouter,
        uint256 indexed timestamp
    );

    event WhitelistUpdated(Whitelist indexed oldRouter, Whitelist indexed newRouter, uint256 indexed timestamp);

    event MarketAdded(
        address indexed newMarket,
        string indexed newMarketName,
        uint256 baseSupplySpeed,
        uint256 baseBorrowSpeed,
        uint256 timestamp
    );

    function updateRouter(RouterInterface newRouter) external onlyOwner {
        require(address(newRouter) != address(0), "LodestarHandler: Invalid Router Address");
        RouterInterface oldRouter = ROUTER;
        ROUTER = newRouter;
        emit RouterUpdated(oldRouter, newRouter, block.timestamp);
    }

    function updateVoting(VotingInterface newVoting) external onlyOwner {
        require(address(newVoting) != address(0), "LodestarHandler: Invalid Voting Address");
        VotingInterface oldVoting = VOTING;
        VOTING = newVoting;
        emit VotingUpdated(oldVoting, newVoting, block.timestamp);
    }

    function updateUnitroller(ComptrollerInterface newUnitroller) external onlyOwner {
        require(address(newUnitroller) != address(0), "LodestarHandler: Invalid Unitroller Address");
        ComptrollerInterface oldUnitroller = UNITROLLER;
        UNITROLLER = newUnitroller;
        emit UnitrollerUpdated(oldUnitroller, newUnitroller, block.timestamp);
    }

    function updateWhitelist(Whitelist newWhitelist) external onlyOwner {
        require(address(newWhitelist) != address(0), "LodestarHandler: Invalid Whitelist Address");
        Whitelist oldWhitelist = WHITELIST;
        WHITELIST = newWhitelist;
        emit WhitelistUpdated(oldWhitelist, newWhitelist, block.timestamp);
    }

    function addMarket(
        address newMarketAddress,
        string memory newMarketName,
        uint256 baseSupplySpeed,
        uint256 baseBorrowSpeed,
        bool isNewMarket
    ) external onlyOwner {
        require(address(newMarketAddress) != address(0), "LodestarHandler: Invalid Router Address");

        MarketInfo memory market;
        market.marketAddress = newMarketAddress;
        market.marketName = newMarketName;
        market.marketBaseSupplySpeed = baseSupplySpeed;
        market.marketBaseBorrowSpeed = baseBorrowSpeed;
        tokenMapping[newMarketName] = market;

        if (isNewMarket) {
            markets.push(newMarketAddress);
        }

        emit MarketAdded(newMarketAddress, newMarketName, baseSupplySpeed, baseBorrowSpeed, block.timestamp);
    }
}

